/**
 * NewStrategy — BNF / Kotegawa mean-reversion paper-trading workflow.
 *
 * Lives at /new-strategy. Uses the same .np-app shell + .np-table styling
 * as the Positions page so it feels of-a-piece.
 *
 * Three stacked tables:
 *   1) TODAY'S CANDIDATES — read from bnf_candidates, written by the
 *      bnf-scan edge function. Click Buy to move into Open Positions.
 *   2) OPEN POSITIONS — paper-traded entries with daily refresh of
 *      current price and SMA25, status chip (GREEN/YELLOW/GREY/RED),
 *      Sell action.
 *   3) CLOSED TRADES — collapsible audit log + summary stats.
 */
import { useEffect, useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import '@/positions/positions.css';
import './new-strategy.css';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';
const STALE_DAYS_EQUITY = 10;
const STALE_DAYS_ETF = 7;
const staleFor = (universe: Universe) => universe === 'ETF' ? STALE_DAYS_ETF : STALE_DAYS_EQUITY;
type Universe = 'EQUITY' | 'ETF';
const NEAR_TARGET_PCT = 2;      // within 2% of SMA25 → YELLOW

// ── Types matching the bnf_candidates / bnf_positions DB schema ──
interface Candidate {
  id: string;
  universe: Universe;
  category: 'Sector' | 'Industry' | 'Style' | null;
  signal_day_vol_ratio: number | null;
  ticker: string;
  name: string | null;
  sector: string | null;
  price: number;
  sma25: number;
  sma200: number;
  deviation_pct: number;
  adv20_m: number | null;
  days_to_earnings: number | null;
  today_intraday_pct: number | null;
  sector_etf: string | null;
  sector_etf_dev_pct: number | null;
  iv30: number | null;
  options_volume: number | null;
  put_call_ratio: number | null;
  open_interest: number | null;
  scanned_at: string;
  // Risk flag columns
  days_since_earnings: number | null;
  insider_sales: InsiderSales | null;
  recent_8ks: EightK[] | null;
}

interface InsiderDetail { name: string; role: string; date: string; usd: number; }
interface InsiderSales {
  sellers_count: number;
  total_sold_usd: number;
  details: InsiderDetail[];
}
interface EightK { date: string; items: string[]; url: string; }

// Scan progress — populated by the bnf-scan edge function in real time
// and streamed to the client via Supabase Realtime.
//
// `stage` is the overall lifecycle marker (starting / done / error).
// `equity_stage` and `etf_stage` track each universe's phase
// independently so the parallel scans don't clobber each other's label.
type OverallStage = 'starting' | 'done' | 'error';
type UniverseStage = 'idle' | 'pricing' | 'enriching' | 'done';

interface ScanStatusRow {
  scan_id: string;
  mode: 'equity' | 'etf' | 'both';
  stage: OverallStage;
  equity_stage: UniverseStage;
  etf_stage: UniverseStage;
  equity_scanned: number;
  equity_total: number;
  equity_candidates: number;
  equity_rate_limited: number;
  etf_scanned: number;
  etf_total: number;
  etf_candidates: number;
  etf_rate_limited: number;
  message: string | null;
  started_at: string;
  updated_at: string;
}

// Research status — survives daily re-scans. 'pending' = never reviewed
// (same as no row at all).
type ResearchStatus = 'pending' | 'skipped' | 'considering' | 'approved';
interface ResearchRow { ticker: string; status: ResearchStatus; }

const STATUS_OPTIONS: Array<{ value: ResearchStatus; label: string }> = [
  { value: 'pending',     label: '— pending' },
  { value: 'skipped',     label: '✕ skipped' },
  { value: 'considering', label: '◐ considering' },
  { value: 'approved',    label: '✓ approved' },
];

// 8-K items considered "material" — earnings, material agreements,
// officer changes, other material events. Anything else (regulation FD,
// exhibits-only filings) flags amber instead of red.
const MATERIAL_8K_ITEMS = new Set(['1.01', '2.02', '5.02', '8.01']);

type FlagTone = 'red' | 'amber' | 'none';

function earningsTone(daysSince: number | null): FlagTone {
  if (daysSince == null) return 'none';
  if (daysSince <= 7) return 'red';
  if (daysSince <= 14) return 'amber';
  return 'none';
}

function insiderTone(s: InsiderSales | null): FlagTone {
  if (!s || s.sellers_count === 0) return 'none';
  const m = s.total_sold_usd / 1_000_000;
  if (s.sellers_count >= 2 && m >= 3) return 'red';
  if (s.sellers_count >= 1 && m >= 1) return 'amber';
  return 'none';
}

function eightKTone(eightKs: EightK[] | null): FlagTone {
  if (!eightKs || eightKs.length === 0) return 'none';
  const hasMaterial = eightKs.some((f) => f.items.some((i) => MATERIAL_8K_ITEMS.has(i)));
  return hasMaterial ? 'red' : 'amber';
}

function setupQuality(...tones: FlagTone[]): 'clean' | 'review' | 'caution' {
  if (tones.some((t) => t === 'red')) return 'caution';
  if (tones.some((t) => t === 'amber')) return 'review';
  return 'clean';
}

interface Position {
  id: string;
  universe: Universe;
  ticker: string;
  status: 'open' | 'closed';
  entry_date: string;
  entry_price: number;
  entry_deviation_pct: number;
  entry_iv: number | null;
  exit_date: string | null;
  exit_price: number | null;
  exit_reason: string | null;
  realized_pct: number | null;
}

// ── Formatters ──────────────────────────────────────────────────
const fmtUSD = (n: number | null | undefined) =>
  n == null ? '—' : `$${n.toFixed(2)}`;
const fmtPct = (n: number | null | undefined, decimals = 1) =>
  n == null ? '—' : `${n >= 0 ? '+' : ''}${n.toFixed(decimals)}%`;
const fmtDays = (n: number | null | undefined) =>
  n == null ? '—' : `${n}d`;
const fmtNum = (n: number | null | undefined) =>
  n == null ? '—' : n.toLocaleString();
const fmtIV = (n: number | null | undefined) =>
  n == null ? '—' : `${(n * 100).toFixed(0)}%`;

// ── Risk-flag formatters ───────────────────────────────────────────
function fmtInsider(s: InsiderSales | null): string {
  if (!s || s.sellers_count === 0) return '—';
  const m = s.total_sold_usd / 1_000_000;
  return `${s.sellers_count} / $${m.toFixed(1)}M`;
}

function insiderTooltip(s: InsiderSales | null): string {
  if (!s || !s.details || s.details.length === 0) return '';
  return s.details
    .slice(0, 8)
    .map((d) => `${d.name} (${d.role}) · ${d.date} · $${(d.usd / 1_000_000).toFixed(2)}M`)
    .join('\n');
}

function eightKTooltip(eightKs: EightK[] | null): string {
  if (!eightKs || eightKs.length === 0) return '';
  return eightKs
    .slice(0, 6)
    .map((f) => `${f.date} · items ${f.items.join(', ') || '—'}`)
    .join('\n');
}

/** Render the 8-K cell as a count plus links to each filing on SEC.gov. */
function EightKLinks({ items }: { items: EightK[] }) {
  return (
    <span className="bnf-8k-cell">
      <span className="bnf-8k-count">{items.length}</span>
      <span className="bnf-8k-links">
        {items.slice(0, 3).map((f, i) => (
          <a
            key={i}
            href={f.url}
            target="_blank"
            rel="noopener noreferrer"
            onClick={(e) => e.stopPropagation()}
            className="bnf-8k-link"
          >
            ↗
          </a>
        ))}
      </span>
    </span>
  );
}

function daysBetween(fromIso: string, toIso: string): number {
  const a = new Date(fromIso + 'T00:00:00Z').getTime();
  const b = new Date(toIso + 'T00:00:00Z').getTime();
  return Math.max(0, Math.round((b - a) / 86400000));
}

// ── Page ─────────────────────────────────────────────────────────
export default function NewStrategy() {
  const qc = useQueryClient();
  const [scanning, setScanning] = useState(false);
  const [scanErr, setScanErr] = useState<string | null>(null);
  const [closedOpen, setClosedOpen] = useState(false);

  // Pull candidates (RLS scoped to this user)
  const { data: candidates = [] } = useQuery({
    queryKey: ['bnf_candidates'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bnf_candidates' as never)
        .select('*')
        .order('deviation_pct', { ascending: true });          // most negative first
      if (error) throw error;
      return (data ?? []) as unknown as Candidate[];
    },
  });

  // ── Live scan progress via Supabase Realtime ──
  // Initial fetch (so a refresh mid-scan still shows progress) + a
  // subscription that pushes UPDATE / INSERT events.
  const [scanStatus, setScanStatus] = useState<ScanStatusRow | null>(null);
  const [showStatus, setShowStatus] = useState(false);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('bnf_scan_status' as never)
        .select('*')
        .maybeSingle();
      if (!cancelled && data) {
        setScanStatus(data as unknown as ScanStatusRow);
        if ((data as { stage: OverallStage }).stage !== 'done') setShowStatus(true);
      }
    })();
    const channel = supabase
      .channel('bnf-scan-status')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'bnf_scan_status' },
        (payload) => {
          const row = payload.new as unknown as ScanStatusRow;
          setScanStatus(row);
          setShowStatus(true);
          // Auto-dismiss 5s after success (per spec). Errors stick until
          // the user clicks ✕.
          if (row.stage === 'done') {
            window.setTimeout(() => setShowStatus(false), 5000);
          }
        },
      )
      .subscribe();
    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, []);

  // Pull research-status rows — keyed by ticker. We turn it into a Map
  // for O(1) lookup per candidate row at render time.
  const { data: researchRows = [] } = useQuery({
    queryKey: ['bnf_research_status'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bnf_research_status' as never)
        .select('ticker, status');
      if (error) throw error;
      return (data ?? []) as unknown as ResearchRow[];
    },
  });
  const statusByTicker = useMemo(() => {
    const m = new Map<string, ResearchStatus>();
    for (const r of researchRows) m.set(r.ticker, r.status);
    return m;
  }, [researchRows]);

  // Hide-skipped filter — on by default per user spec ("when they repeat
  // tomorrow, we don't like look into them again").
  const [hideSkipped, setHideSkipped] = useState(true);

  // Pull positions (both open and closed in one fetch)
  const { data: positions = [] } = useQuery({
    queryKey: ['bnf_positions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bnf_positions' as never)
        .select('*')
        .order('entry_date', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as Position[];
    },
  });

  // Refresh current price for each open position on page load. Reuses
  // the existing quote-ticker edge function.
  const openTickers = useMemo(
    () => positions.filter((p) => p.status === 'open').map((p) => p.ticker),
    [positions],
  );
  const { data: quotes = {} } = useQuery({
    queryKey: ['bnf_open_quotes', openTickers.join(',')],
    enabled: openTickers.length > 0,
    queryFn: async () => {
      const out: Record<string, { price: number; sma25: number | null }> = {};
      // One quote-ticker call per ticker. SMA25 isn't returned by
      // quote-ticker; we'd need a separate endpoint to recompute it
      // intraday. For v1 we reuse the candidate's sma25 if available;
      // otherwise leave null and the status falls back to GREY.
      await Promise.all(openTickers.map(async (t) => {
        try {
          const { data, error } = await supabase.functions.invoke('quote-ticker', {
            body: { ticker: t },
          });
          if (!error && data?.price) {
            out[t] = { price: data.price, sma25: null };
          }
        } catch { /* ignore */ }
      }));
      return out;
    },
  });

  // ── Buy mutation: candidate row → bnf_positions ──
  const buyMutation = useMutation({
    mutationFn: async (c: Candidate) => {
      const { data: userData } = await supabase.auth.getUser();
      const userId = userData?.user?.id;
      if (!userId) throw new Error('Not signed in');
      const { error } = await supabase
        .from('bnf_positions' as never)
        .insert({
          user_id: userId,
          universe: c.universe,
          ticker: c.ticker,
          status: 'open',
          entry_price: c.price,
          entry_deviation_pct: c.deviation_pct,
          entry_iv: c.iv30,
        } as never);
      if (error) throw error;
      // Drop the candidate row so it doesn't keep haunting the table.
      await supabase.from('bnf_candidates' as never).delete().eq('id', c.id);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bnf_candidates'] });
      qc.invalidateQueries({ queryKey: ['bnf_positions'] });
    },
  });

  // ── Research-status mutation: upsert by (user, ticker) ──
  const setStatusMutation = useMutation({
    mutationFn: async ({ ticker, status }: { ticker: string; status: ResearchStatus }) => {
      const { data: userData } = await supabase.auth.getUser();
      const userId = userData?.user?.id;
      if (!userId) throw new Error('Not signed in');
      const { error } = await supabase
        .from('bnf_research_status' as never)
        .upsert(
          { user_id: userId, ticker, status, updated_at: new Date().toISOString() } as never,
          { onConflict: 'user_id,ticker' },
        );
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bnf_research_status'] }),
  });

  // ── Sell mutation: open position → closed ──
  const sellMutation = useMutation({
    mutationFn: async ({ p, reason, exitPrice }: {
      p: Position; reason: string; exitPrice: number;
    }) => {
      const realized = ((exitPrice - p.entry_price) / p.entry_price) * 100;
      const { error } = await supabase
        .from('bnf_positions' as never)
        .update({
          status: 'closed',
          exit_date: new Date().toISOString().slice(0, 10),
          exit_price: exitPrice,
          exit_reason: reason,
          realized_pct: realized,
        } as never)
        .eq('id', p.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bnf_positions'] }),
  });

  // ── Refresh-scan handler ──
  // The scan now reads from a pre-populated cache (bnf_universe_data),
  // so it's a single fast invocation. No more batching needed.
  const [scanMode, setScanMode] = useState<'equity' | 'etf' | 'both' | null>(null);
  const runScan = async (universe: 'equity' | 'etf' | 'both') => {
    setScanning(true);
    setScanMode(universe);
    setScanErr(null);
    try {
      const { data, error } = await supabase.functions.invoke('bnf-scan', {
        body: { universe },
      });
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
      qc.invalidateQueries({ queryKey: ['bnf_candidates'] });
    } catch (e) {
      setScanErr((e as Error).message);
    } finally {
      setScanning(false);
      setScanMode(null);
    }
  };

  // ── Universe cache refresh ──
  // The scan reads from bnf_universe_data which is populated by:
  //   • bnf-cache-update    — daily incremental (nightly cron + button)
  //   • bnf-cache-backfill  — multi-day load (first run, gap fills)
  // Both write progress to the same status row so the banner shows
  // cache activity the same way it shows scan activity.
  const [refreshingCache, setRefreshingCache] = useState(false);
  const runCacheUpdate = async () => {
    setRefreshingCache(true);
    setScanErr(null);
    try {
      const { data, error } = await supabase.functions.invoke('bnf-cache-update');
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
    } catch (e) {
      setScanErr(`Cache update failed: ${(e as Error).message}`);
    } finally {
      setRefreshingCache(false);
    }
  };

  /** Initial cache backfill — 260 calendar days back, in 5 batches of
   *  ~52 dates each so each invocation finishes well under the timeout.
   *  Only needed once; the nightly cron keeps the cache fresh after. */
  const [backfilling, setBackfilling] = useState(false);
  const runCacheBackfill = async () => {
    setBackfilling(true);
    setScanErr(null);
    try {
      // Compute date windows on the client and call sequentially.
      const today = new Date();
      const end = new Date(today);
      end.setUTCDate(end.getUTCDate() - 1);
      const totalDaysBack = 260;
      const BATCH_DAYS = 52;
      for (let offset = 0; offset < totalDaysBack; offset += BATCH_DAYS) {
        const batchEnd = new Date(end);
        batchEnd.setUTCDate(batchEnd.getUTCDate() - offset);
        const batchStart = new Date(batchEnd);
        batchStart.setUTCDate(batchStart.getUTCDate() - (BATCH_DAYS - 1));
        const { data, error } = await supabase.functions.invoke('bnf-cache-backfill', {
          body: {
            from_date: batchStart.toISOString().slice(0, 10),
            to_date: batchEnd.toISOString().slice(0, 10),
          },
        });
        if (error) throw new Error(error.message);
        if (data?.error) throw new Error(data.error);
      }
    } catch (e) {
      setScanErr(`Cache backfill failed: ${(e as Error).message}`);
    } finally {
      setBackfilling(false);
    }
  };

  // ── Refresh-flags handler (re-pulls SEC + earnings only, much faster) ──
  const [refreshingFlags, setRefreshingFlags] = useState(false);
  const runRefreshFlags = async () => {
    setRefreshingFlags(true);
    setScanErr(null);
    try {
      const { data, error } = await supabase.functions.invoke('bnf-refresh-flags');
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
      qc.invalidateQueries({ queryKey: ['bnf_candidates'] });
    } catch (e) {
      setScanErr((e as Error).message);
    } finally {
      setRefreshingFlags(false);
    }
  };

  // ── Derived sets, per universe ──
  // Candidate rows are split by universe; positions same. Closed trades
  // stay merged because the closed-trades section shows both.
  const equityCandidates = candidates.filter((c) => c.universe === 'EQUITY');
  const etfCandidates = candidates.filter((c) => c.universe === 'ETF');
  const openPositions = positions.filter((p) => p.status === 'open');
  const closedPositions = positions.filter((p) => p.status === 'closed');

  // Hide-skipped filter applies to BOTH universes — research status is
  // ticker-keyed, not universe-keyed.
  const skippedCount = candidates.filter(
    (c) => statusByTicker.get(c.ticker) === 'skipped',
  ).length;
  const filterSkipped = (rows: Candidate[]) => hideSkipped
    ? rows.filter((c) => statusByTicker.get(c.ticker) !== 'skipped')
    : rows;
  const visibleEquityCandidates = filterSkipped(equityCandidates);
  const visibleEtfCandidates = filterSkipped(etfCandidates);
  // Kept for backward-compat with the existing section title/empty-state.
  const visibleCandidates = filterSkipped(candidates);

  // Map ticker → most recent candidate snapshot so open positions can show
  // a fresh SMA25 without re-running the scanner per row.
  const lastCandidateByTicker = useMemo(() => {
    const m = new Map<string, Candidate>();
    for (const c of candidates) m.set(c.ticker, c);
    return m;
  }, [candidates]);

  // Open positions with derived status (GREEN/YELLOW/GREY/RED)
  const openWithDerived: OpenView[] = openPositions.map((p) => {
    const quote = quotes[p.ticker];
    const currentPrice = quote?.price ?? null;
    // Use today's candidate sma25 if available; falls back to the entry
    // anchor (price × (1 + |entry_deviation_pct|/100)) so distance is at
    // least sensible until next scan.
    const candidate = lastCandidateByTicker.get(p.ticker);
    const sma25 =
      candidate?.sma25 ??
      p.entry_price * (1 + Math.abs(p.entry_deviation_pct) / 100);
    const distToSMA25Pct =
      currentPrice && sma25 ? ((sma25 - currentPrice) / currentPrice) * 100 : null;
    const unrealizedPct =
      currentPrice ? ((currentPrice - p.entry_price) / p.entry_price) * 100 : null;
    const daysHeld = daysBetween(p.entry_date, new Date().toISOString().slice(0, 10));
    let status: OpenView['status'] = 'grey';
    if (currentPrice != null && sma25 != null) {
      if (currentPrice >= sma25) status = 'green';
      else if (Math.abs(distToSMA25Pct ?? 99) <= NEAR_TARGET_PCT) status = 'yellow';
    }
    // STALE threshold is universe-aware: ETFs mean-revert faster than
    // single names, so they go red at 7d vs 10d for equities.
    if (daysHeld > staleFor(p.universe) && status !== 'green') status = 'red';
    return { ...p, currentPrice, sma25, distToSMA25Pct, unrealizedPct, daysHeld, status };
  });
  const equityOpenView = openWithDerived.filter((o) => o.universe === 'EQUITY');
  const etfOpenView = openWithDerived.filter((o) => o.universe === 'ETF');

  const greenCount = openWithDerived.filter((o) => o.status === 'green').length;

  // Closed-trade summary
  /** Aggregate stats for a single universe slice of closed positions.
   *  Returns null when the slice is empty so the UI can hide that block. */
  const statsFor = (rows: Position[]) => {
    if (rows.length === 0) return null;
    let wins = 0, sumReturn = 0, sumDays = 0;
    for (const p of rows) {
      const r = p.realized_pct ?? 0;
      if (r > 0) wins++;
      sumReturn += r;
      if (p.exit_date) sumDays += daysBetween(p.entry_date, p.exit_date);
    }
    return {
      total: rows.length,
      winRate: (wins / rows.length) * 100,
      avgReturn: sumReturn / rows.length,
      avgDays: sumDays / rows.length,
    };
  };
  const closedStats = useMemo(() => statsFor(closedPositions), [closedPositions]);
  const closedEquityStats = useMemo(
    () => statsFor(closedPositions.filter((p) => p.universe === 'EQUITY')),
    [closedPositions],
  );
  const closedEtfStats = useMemo(
    () => statsFor(closedPositions.filter((p) => p.universe === 'ETF')),
    [closedPositions],
  );

  // ── render ──
  return (
    <div className="np-app">
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">NEW STRATEGY</span>
          <span className="np-crumb-sub"> · BNF mean-reversion</span>
        </div>
        <div className="bnf-top-actions">
          <button
            className="np-btn"
            disabled={backfilling || refreshingCache || scanning}
            onClick={runCacheBackfill}
            title="One-time + manual: load 260 trading days of OHLCV into the cache. Takes ~3–5 minutes."
          >
            {backfilling ? 'Backfilling cache…' : '⤓ Backfill cache'}
          </button>
          <button
            className="np-btn"
            disabled={refreshingCache || backfilling || scanning}
            onClick={runCacheUpdate}
            title="Daily incremental: pull yesterday's grouped snapshot into the cache. Fast (~10s)."
          >
            {refreshingCache ? 'Updating cache…' : '↻ Refresh cache'}
          </button>
          <button
            className="np-btn"
            disabled={refreshingFlags || candidates.length === 0}
            onClick={runRefreshFlags}
            title="Re-pull SEC EDGAR (8-K + insider) + earnings dates for current candidates without re-running the universe scan."
          >
            {refreshingFlags ? 'Refreshing flags…' : '↻ Refresh risk flags'}
          </button>
          <button
            className="np-btn"
            disabled={scanning}
            onClick={() => runScan('etf')}
            title="Scan only the ~30 sector & industry ETFs (fast)."
          >
            {scanning && scanMode === 'etf' ? 'Scanning…' : '↻ Refresh ETF scan'}
          </button>
          <button
            className="np-btn"
            disabled={scanning}
            onClick={() => runScan('equity')}
            title="Scan only the ~1000-name equity universe."
          >
            {scanning && scanMode === 'equity' ? 'Scanning…' : '↻ Refresh equity scan'}
          </button>
          <button
            className="np-btn neon"
            disabled={scanning}
            onClick={() => runScan('both')}
            title="Run both universes."
          >
            {scanning && scanMode === 'both' ? 'Scanning…' : '↻ Refresh all'}
          </button>
        </div>
      </header>

      <main className="np-main">
        {scanErr && (
          <div className="bnf-banner err">Scan failed: {scanErr}</div>
        )}

        {/* Live scan progress banner — fades 5s after success, sticks on error */}
        {showStatus && scanStatus && (
          <ScanProgressBanner
            status={scanStatus}
            onDismiss={() => setShowStatus(false)}
          />
        )}

        {greenCount > 0 && (
          <div className="bnf-banner ready">
            ▶ {greenCount} position{greenCount === 1 ? '' : 's'} ready to sell — price reached SMA25
          </div>
        )}

        {/* ────── TODAY'S EQUITY CANDIDATES ────── */}
        <section className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Today's equity candidates · {visibleEquityCandidates.length}
              {hideSkipped && skippedCount > 0 && (
                <span className="bnf-section-sub-inline">
                  {' '}· {skippedCount} skipped hidden
                </span>
              )}
            </div>
            <div className="np-section-sub">
              Sorted by deviation (most dislocated first). Dev ∈ [−15%, −7%], close &gt; SMA200,
              today &gt; −5%, sector ETF still healthy.
            </div>
            <div className="bnf-filter-row">
              <label className="bnf-filter-toggle">
                <input
                  type="checkbox"
                  checked={hideSkipped}
                  onChange={(e) => setHideSkipped(e.target.checked)}
                />
                Hide skipped
              </label>
            </div>
          </div>
          <div className="np-table-wrap">
            <table className="np-table bnf-candidates-table">
              <thead>
                <tr>
                  <th>Ticker</th>
                  <th>Name</th>
                  <th>Sector</th>
                  <th className="num">Price</th>
                  <th className="num">SMA25</th>
                  <th className="num">Dev %</th>
                  <th className="num">SMA200</th>
                  <th className="num">ADV20 $M</th>
                  <th className="num">Earn</th>
                  <th className="num bnf-flag-th">Days since earn</th>
                  <th className="num bnf-flag-th">Insider sales (14d)</th>
                  <th className="num bnf-flag-th">8-K (14d)</th>
                  <th className="num">IV</th>
                  <th className="num">Opt vol</th>
                  <th className="num">P/C</th>
                  <th className="num">OI</th>
                  <th>Setup</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {visibleEquityCandidates.length === 0 ? (
                  <tr>
                    <td colSpan={18} className="bnf-empty">
                      {equityCandidates.length === 0
                        ? <>No equity candidates yet. Click <b>Refresh equity scan</b>.</>
                        : <>All {equityCandidates.length} equity candidate{equityCandidates.length === 1 ? '' : 's'} are skipped. Toggle "Hide skipped" off to see them.</>}
                    </td>
                  </tr>
                ) : visibleEquityCandidates.map((c) => {
                  const tEarn = earningsTone(c.days_since_earnings);
                  const tIns = insiderTone(c.insider_sales);
                  const t8K = eightKTone(c.recent_8ks);
                  const quality = setupQuality(tEarn, tIns, t8K);
                  const status = statusByTicker.get(c.ticker) ?? 'pending';
                  return (
                    <tr key={c.id} className={`bnf-row status-${status}`}>
                      <td className="ticker">{c.ticker}</td>
                      <td className="bnf-name" title={c.name ?? ''}>{c.name ?? '—'}</td>
                      <td className="sector-cell">{c.sector ?? '—'}</td>
                      <td className="num strong">{fmtUSD(c.price)}</td>
                      <td className="num">{fmtUSD(c.sma25)}</td>
                      <td className="num down strong">{fmtPct(c.deviation_pct)}</td>
                      <td className="num">{fmtUSD(c.sma200)}</td>
                      <td className="num">{c.adv20_m ? `$${c.adv20_m.toFixed(0)}M` : '—'}</td>
                      <td className="num">{fmtDays(c.days_to_earnings)}</td>

                      {/* Risk flag cells — color-coded backgrounds per spec */}
                      <td className={`num bnf-flag tone-${tEarn}`}>
                        {c.days_since_earnings != null ? `${c.days_since_earnings}d` : '—'}
                      </td>
                      <td
                        className={`num bnf-flag tone-${tIns}`}
                        title={insiderTooltip(c.insider_sales)}
                      >
                        {fmtInsider(c.insider_sales)}
                      </td>
                      <td
                        className={`num bnf-flag tone-${t8K}`}
                        title={eightKTooltip(c.recent_8ks)}
                      >
                        {c.recent_8ks && c.recent_8ks.length > 0
                          ? <EightKLinks items={c.recent_8ks} />
                          : '—'}
                      </td>

                      <td className="num">{fmtIV(c.iv30)}</td>
                      <td className="num">{fmtNum(c.options_volume)}</td>
                      <td className="num">{c.put_call_ratio != null ? c.put_call_ratio.toFixed(2) : '—'}</td>
                      <td className="num">{fmtNum(c.open_interest)}</td>
                      <td className={`bnf-quality tone-${quality}`}>
                        {quality === 'clean' ? 'Clean' : quality === 'review' ? 'Review' : 'Caution'}
                      </td>
                      <td className="bnf-status-cell">
                        <select
                          className={`bnf-status-select status-${status}`}
                          value={status}
                          onChange={(e) =>
                            setStatusMutation.mutate({
                              ticker: c.ticker,
                              status: e.target.value as ResearchStatus,
                            })
                          }
                          disabled={setStatusMutation.isPending}
                          aria-label="Research status"
                        >
                          {STATUS_OPTIONS.map((o) => (
                            <option key={o.value} value={o.value}>{o.label}</option>
                          ))}
                        </select>
                      </td>
                      <td className="num">
                        <button
                          className="np-btn neon bnf-row-btn"
                          onClick={() => buyMutation.mutate(c)}
                          disabled={buyMutation.isPending}
                        >
                          Buy
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>

        <OpenPositionsTable
          title="Open equity positions"
          rows={equityOpenView}
          universe="EQUITY"
          stale={STALE_DAYS_EQUITY}
          onSell={(p, reason, exitPrice) =>
            sellMutation.mutate({ p, reason, exitPrice })
          }
          sellPending={sellMutation.isPending}
        />

        {/* ────── TODAY'S ETF CANDIDATES ────── */}
        <section className="np-section bnf-etf-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Today's ETF candidates · {visibleEtfCandidates.length}
            </div>
            <div className="np-section-sub">
              Sector + industry + style ETFs. Same SMA logic; SPY broad-market guard replaces
              the sector breadth filter. No earnings / insider / 8-K risk to display.
            </div>
          </div>
          <div className="np-table-wrap">
            <table className="np-table bnf-etf-table">
              <thead>
                <tr>
                  <th>Ticker</th>
                  <th>ETF Name</th>
                  <th>Category</th>
                  <th className="num">Price</th>
                  <th className="num">SMA25</th>
                  <th className="num">Dev %</th>
                  <th className="num">SMA200</th>
                  <th className="num">IV</th>
                  <th className="num">Opt vol</th>
                  <th className="num">P/C</th>
                  <th className="num">Vol vs 20d</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {visibleEtfCandidates.length === 0 ? (
                  <tr><td colSpan={13} className="bnf-empty">
                    {etfCandidates.length === 0
                      ? <>No ETF candidates yet. Click <b>Refresh ETF scan</b>.</>
                      : <>All ETF candidates are skipped. Toggle "Hide skipped" off to see them.</>}
                  </td></tr>
                ) : visibleEtfCandidates.map((c) => {
                  const status = statusByTicker.get(c.ticker) ?? 'pending';
                  return (
                    <tr key={c.id} className={`bnf-row status-${status}`}>
                      <td className="ticker">
                        <span className="bnf-univ-badge etf">ETF</span> {c.ticker}
                      </td>
                      <td className="bnf-name" title={c.name ?? ''}>{c.name ?? '—'}</td>
                      <td className="sector-cell">{c.category ?? '—'}</td>
                      <td className="num strong">{fmtUSD(c.price)}</td>
                      <td className="num">{fmtUSD(c.sma25)}</td>
                      <td className="num down strong">{fmtPct(c.deviation_pct)}</td>
                      <td className="num">{fmtUSD(c.sma200)}</td>
                      <td className="num">{fmtIV(c.iv30)}</td>
                      <td className="num">{fmtNum(c.options_volume)}</td>
                      <td className="num">{c.put_call_ratio != null ? c.put_call_ratio.toFixed(2) : '—'}</td>
                      <td className="num">
                        {c.signal_day_vol_ratio != null
                          ? `${c.signal_day_vol_ratio.toFixed(2)}x`
                          : '—'}
                      </td>
                      <td className="bnf-status-cell">
                        <select
                          className={`bnf-status-select status-${status}`}
                          value={status}
                          onChange={(e) =>
                            setStatusMutation.mutate({
                              ticker: c.ticker,
                              status: e.target.value as ResearchStatus,
                            })
                          }
                          disabled={setStatusMutation.isPending}
                          aria-label="Research status"
                        >
                          {STATUS_OPTIONS.map((o) => (
                            <option key={o.value} value={o.value}>{o.label}</option>
                          ))}
                        </select>
                      </td>
                      <td className="num">
                        <button
                          className="np-btn neon bnf-row-btn"
                          onClick={() => buyMutation.mutate(c)}
                          disabled={buyMutation.isPending}
                        >
                          Buy
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>

        <OpenPositionsTable
          title="Open ETF positions"
          rows={etfOpenView}
          universe="ETF"
          stale={STALE_DAYS_ETF}
          onSell={(p, reason, exitPrice) =>
            sellMutation.mutate({ p, reason, exitPrice })
          }
          sellPending={sellMutation.isPending}
        />

        {/* ────── CLOSED TRADES (collapsible) ────── */}
        {closedPositions.length > 0 && (
          <section className="np-section">
            <button
              className="bnf-closed-toggle"
              onClick={() => setClosedOpen((v) => !v)}
            >
              {closedOpen ? '▾' : '▸'} Closed trades · {closedPositions.length}
              {closedStats && (
                <span className="bnf-closed-stats">
                  {closedEquityStats && (
                    <span className="bnf-closed-univ">
                      <b className="bnf-univ-badge equity">E</b> {closedEquityStats.total}
                      {' · '}win <b>{closedEquityStats.winRate.toFixed(0)}%</b>
                      {' · '}avg <b className={closedEquityStats.avgReturn >= 0 ? 'up' : 'down'}>{fmtPct(closedEquityStats.avgReturn, 1)}</b>
                    </span>
                  )}
                  {closedEtfStats && (
                    <span className="bnf-closed-univ">
                      <b className="bnf-univ-badge etf">ETF</b> {closedEtfStats.total}
                      {' · '}win <b>{closedEtfStats.winRate.toFixed(0)}%</b>
                      {' · '}avg <b className={closedEtfStats.avgReturn >= 0 ? 'up' : 'down'}>{fmtPct(closedEtfStats.avgReturn, 1)}</b>
                    </span>
                  )}
                  <span className="bnf-closed-univ combined">
                    all · win <b>{closedStats.winRate.toFixed(0)}%</b>
                    {' · '}avg <b className={closedStats.avgReturn >= 0 ? 'up' : 'down'}>{fmtPct(closedStats.avgReturn, 1)}</b>
                    {' · '}{closedStats.avgDays.toFixed(1)}d
                  </span>
                </span>
              )}
            </button>
            {closedOpen && (
              <div className="np-table-wrap">
                <table className="np-table">
                  <thead>
                    <tr>
                      <th>Univ</th>
                      <th>Ticker</th>
                      <th className="num">Entry</th>
                      <th className="num">Exit</th>
                      <th className="num">Entry $</th>
                      <th className="num">Exit $</th>
                      <th className="num">Return %</th>
                      <th className="num">Hold</th>
                      <th>Reason</th>
                    </tr>
                  </thead>
                  <tbody>
                    {closedPositions.map((p) => {
                      const hold = p.exit_date ? daysBetween(p.entry_date, p.exit_date) : 0;
                      return (
                        <tr key={p.id}>
                          <td>
                            <span className={`bnf-univ-badge ${p.universe === 'ETF' ? 'etf' : 'equity'}`}>
                              {p.universe === 'ETF' ? 'ETF' : 'E'}
                            </span>
                          </td>
                          <td className="ticker">{p.ticker}</td>
                          <td className="num">{p.entry_date}</td>
                          <td className="num">{p.exit_date}</td>
                          <td className="num">{fmtUSD(p.entry_price)}</td>
                          <td className="num">{fmtUSD(p.exit_price)}</td>
                          <td className={'num strong ' + ((p.realized_pct ?? 0) >= 0 ? 'up' : 'down')}>
                            {fmtPct(p.realized_pct, 2)}
                          </td>
                          <td className="num">{hold}d</td>
                          <td>{p.exit_reason}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        )}
      </main>
    </div>
  );
}

// Open-positions derived view — one row per open position with computed
// status indicator, current price, distance to SMA25, etc. Hoisted to
// module scope so the OpenPositionsTable helper can type its rows prop.
interface OpenView extends Position {
  currentPrice: number | null;
  sma25: number | null;
  distToSMA25Pct: number | null;
  unrealizedPct: number | null;
  daysHeld: number;
  status: 'green' | 'yellow' | 'grey' | 'red';
}

/** Reusable open-positions section. Rendered twice on the page — once
 *  for EQUITY and once for ETF — with different rows + stale thresholds. */
function OpenPositionsTable({
  title, rows, universe, stale, onSell, sellPending,
}: {
  title: string;
  rows: OpenView[];
  universe: Universe;
  stale: number;
  onSell: (p: OpenView, reason: string, exitPrice: number) => void;
  sellPending: boolean;
}) {
  const sectionClass = 'np-section' + (universe === 'ETF' ? ' bnf-etf-section' : '');
  return (
    <section className={sectionClass}>
      <div className="np-section-hd">
        <div className="np-section-title">{title} · {rows.length}</div>
        <div className="np-section-sub">
          Status follows distance to SMA25. Sell when ▲ green (target hit) or when stale (&gt;{stale}d).
        </div>
      </div>
      <div className="np-table-wrap">
        <table className="np-table">
          <thead>
            <tr>
              <th>Status</th>
              <th>Ticker</th>
              <th className="num">Entry</th>
              <th className="num">Entry $</th>
              <th className="num">Entry dev</th>
              <th className="num">Now $</th>
              <th className="num">SMA25</th>
              <th className="num">To SMA25</th>
              <th className="num">UPnL %</th>
              <th className="num">Days</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr><td colSpan={11} className="bnf-empty">
                No {universe === 'ETF' ? 'ETF ' : ''}open positions. Buy a candidate above to start one.
              </td></tr>
            ) : rows.map((p) => {
              const exitPrice = p.currentPrice ?? p.entry_price;
              const reason =
                p.status === 'green' ? 'target_hit'
                : p.status === 'red'   ? 'stale'
                : 'manual';
              return (
                <tr key={p.id}>
                  <td><StatusDot tone={p.status} /></td>
                  <td className="ticker">
                    <span className={`bnf-univ-badge ${universe === 'ETF' ? 'etf' : 'equity'}`}>
                      {universe === 'ETF' ? 'ETF' : 'E'}
                    </span>
                    {' '}{p.ticker}
                  </td>
                  <td className="num">{p.entry_date}</td>
                  <td className="num">{fmtUSD(p.entry_price)}</td>
                  <td className="num down">{fmtPct(p.entry_deviation_pct)}</td>
                  <td className="num strong">{fmtUSD(p.currentPrice)}</td>
                  <td className="num">{fmtUSD(p.sma25)}</td>
                  <td className={'num ' + (
                    p.distToSMA25Pct != null && p.distToSMA25Pct < 0 ? 'up' : ''
                  )}>{fmtPct(p.distToSMA25Pct)}</td>
                  <td className={'num strong ' + (
                    (p.unrealizedPct ?? 0) >= 0 ? 'up' : 'down'
                  )}>{fmtPct(p.unrealizedPct, 2)}</td>
                  <td className={'num ' + (p.daysHeld > stale ? 'down' : '')}>
                    {p.daysHeld}d
                  </td>
                  <td className="num">
                    <button
                      className="np-btn bnf-row-btn"
                      onClick={() => onSell(p, reason, exitPrice)}
                      disabled={sellPending}
                    >
                      Sell
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}

// ── Scan progress banner ────────────────────────────────────────
/** Shows under the refresh buttons while a scan is in flight. Pulls
 *  live updates from bnf_scan_status via Supabase Realtime. Fades
 *  5s after stage='done', sticks on stage='error'. */
function ScanProgressBanner({
  status, onDismiss,
}: {
  status: ScanStatusRow;
  onDismiss: () => void;
}) {
  const UNIVERSE_STAGE_LABEL: Record<UniverseStage, string> = {
    idle:       'idle',
    pricing:    'scanning prices',
    enriching:  'enriching survivors',
    done:       'done',
  };

  // Progress percentage. Each universe contributes proportionally to its
  // stage progress; we average them when both are active. Pricing is 80%
  // of a universe's work, enrichment the last 20%.
  const universePct = (stage: UniverseStage, scanned: number, total: number) => {
    if (stage === 'idle') return 0;
    if (stage === 'done') return 100;
    if (stage === 'enriching') return 90;
    // pricing
    return total > 0 ? (scanned / total) * 80 : 0;
  };
  const isEquity = status.mode === 'equity' || status.mode === 'both';
  const isEtf = status.mode === 'etf' || status.mode === 'both';
  const equityPctRaw = isEquity ? universePct(status.equity_stage, status.equity_scanned, status.equity_total) : 0;
  const etfPctRaw    = isEtf    ? universePct(status.etf_stage, status.etf_scanned, status.etf_total) : 0;
  const universesActive = (isEquity ? 1 : 0) + (isEtf ? 1 : 0);
  let pct = universesActive > 0 ? (equityPctRaw + etfPctRaw) / universesActive : 0;
  if (status.stage === 'done') pct = 100;
  pct = Math.max(0, Math.min(100, pct));

  const elapsed = Math.max(
    0,
    Math.round((new Date(status.updated_at).getTime() - new Date(status.started_at).getTime()) / 1000),
  );

  const tone = status.stage === 'error'
    ? 'err'
    : status.stage === 'done' ? 'ok' : 'live';

  return (
    <div className={`bnf-progress ${tone}`}>
      <div className="bnf-progress-head">
        <span className="bnf-progress-icon">
          {tone === 'err' ? '✕' : tone === 'ok' ? '✓' : '↻'}
        </span>
        <span className="bnf-progress-title">
          {tone === 'err' ? 'Scan failed'
            : tone === 'ok' ? 'Scan complete'
            : 'Scanning…'}
        </span>
        <span className="bnf-progress-elapsed">{elapsed}s elapsed</span>
        <button
          type="button"
          className="bnf-progress-close"
          onClick={onDismiss}
          aria-label="Dismiss"
        >×</button>
      </div>
      {status.message && (
        <div className="bnf-progress-msg">{status.message}</div>
      )}
      <div className="bnf-progress-rows">
        {isEquity && (
          <div className="bnf-progress-row">
            <span className="bnf-progress-lbl">Equity</span>
            <span className="bnf-progress-counters">
              <span className={`bnf-progress-univstage stage-${status.equity_stage}`}>
                {UNIVERSE_STAGE_LABEL[status.equity_stage]}
              </span>
              {' · '}
              {status.equity_scanned} / {status.equity_total || '—'} scanned
              {' · '}
              <b>{status.equity_candidates}</b> candidate{status.equity_candidates === 1 ? '' : 's'}
              {status.equity_rate_limited > 0 && (
                <span className="bnf-progress-throttle">
                  {' · '}⚠ {status.equity_rate_limited} rate-limited
                </span>
              )}
            </span>
          </div>
        )}
        {isEtf && (
          <div className="bnf-progress-row">
            <span className="bnf-progress-lbl">ETF</span>
            <span className="bnf-progress-counters">
              <span className={`bnf-progress-univstage stage-${status.etf_stage}`}>
                {UNIVERSE_STAGE_LABEL[status.etf_stage]}
              </span>
              {' · '}
              {status.etf_scanned} / {status.etf_total || '—'} scanned
              {' · '}
              <b>{status.etf_candidates}</b> candidate{status.etf_candidates === 1 ? '' : 's'}
              {status.etf_rate_limited > 0 && (
                <span className="bnf-progress-throttle">
                  {' · '}⚠ {status.etf_rate_limited} rate-limited
                </span>
              )}
            </span>
          </div>
        )}
      </div>
      <div className="bnf-progress-bar">
        <div className={`bnf-progress-fill ${tone}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

function StatusDot({ tone }: { tone: 'green' | 'yellow' | 'grey' | 'red' }) {
  const label =
    tone === 'green' ? 'Target hit — ready to sell' :
    tone === 'yellow' ? 'Approaching SMA25' :
    tone === 'red' ? 'Stale — consider exit' :
    'Holding';
  return <span className={`bnf-dot ${tone}`} title={label} aria-label={label} />;
}

// Unused-import shield so this compiles even when React Query types
// emit warnings about implicit any in some toolchains.
void useEffect;
