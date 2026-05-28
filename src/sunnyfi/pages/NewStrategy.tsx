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
import { BNF_UNIVERSE, type UniverseMember } from '@/sunnyfi/data/bnfUniverse';
import { CountUp } from '@/sunnyfi/lib/animation';
import { Section } from '@/sunnyfi/dashboard/atoms';
import { TickerStrip } from '@/sunnyfi/dashboard/blocks';
import '@/sunnyfi/pages/dashboard.css';
import './new-strategy.css';
import './new-strategy-v2.css';

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
  // Near-miss flag: true when one or more soft thresholds were within
  // BORDERLINE_SLACK (0.5%) of failing. Drives the yellow chip.
  borderline: boolean | null;
  borderline_reasons: string[] | null;
}

// Human-readable text per borderline reason code (matches bnf-scan tags).
const BORDERLINE_LABELS: Record<string, string> = {
  'dev-low':       'Deviation just past −15%',
  'dev-high':      'Deviation just past −7%',
  'intraday-near': 'Today\'s intraday just past −5%',
  'sector-near':   'Sector ETF just past −5%',
  'spy-near':      'SPY just past −5%',
};
function borderlineTooltip(reasons: string[] | null): string {
  if (!reasons || reasons.length === 0) return 'Near a filter threshold';
  return reasons.map((r) => BORDERLINE_LABELS[r] ?? r).join(' · ');
}

// One row of the bnf_universe_latest view — latest cached bar + derived
// SMA/dev per ticker. Used for the unified universe table where every
// ticker is rendered, not just the BNF survivors.
interface UniverseLatestRow {
  ticker: string;
  latest_date: string;
  latest_close: number;
  latest_open: number | null;
  latest_volume: number | null;
  sma25: number | null;
  sma200: number | null;
  deviation_pct: number | null;
  today_intraday_pct: number | null;
  adv20_m: number | null;
  bars_count: number;
}

// Highlight tier for a unified universe row. Drives the row's color
// treatment: 'match' = full neon green, 'borderline' = yellow chip,
// 'none' = grayed out / passive.
type RowTier = 'match' | 'borderline' | 'none';

// Universe filter dropdown options.
type UniverseFilter = 'all' | 'matches' | 'near-miss' | 'watchlist' | 'equity' | 'etf';

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

  // Pull latest-price snapshot for the FULL universe (~1030 rows) from
  // the bnf_universe_latest SQL view. Drives the unified universe table
  // where every ticker is visible, gray by default and colored when the
  // BNF setup criteria are hit.
  const { data: universeLatest = [] } = useQuery({
    queryKey: ['bnf_universe_latest'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bnf_universe_latest' as never)
        .select('*');
      if (error) throw error;
      return (data ?? []) as unknown as UniverseLatestRow[];
    },
    staleTime: 5 * 60 * 1000,    // 5 minutes — refreshes after a cache update invalidates
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
      qc.invalidateQueries({ queryKey: ['bnf_universe_latest'] });
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
      // Cache update may shift latest_close / deviation_pct in the view —
      // refetch so the unified universe table reflects the new prices.
      qc.invalidateQueries({ queryKey: ['bnf_universe_latest'] });
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

  // Candidate lookup by ticker — used to merge BNF-survivor metadata
  // (risk flags, options, name) into the unified universe row.
  const candidateByTicker = useMemo(() => {
    const m = new Map<string, Candidate>();
    for (const c of candidates) m.set(c.ticker, c);
    return m;
  }, [candidates]);

  // Latest-bar lookup by ticker — view returns one row per ticker.
  const latestByTicker = useMemo(() => {
    const m = new Map<string, UniverseLatestRow>();
    for (const r of universeLatest) m.set(r.ticker, r);
    return m;
  }, [universeLatest]);

  // ── Unified universe rows ──
  // Each row carries metadata (from BNF_UNIVERSE) + latest-price snapshot
  // (from the view) + optional BNF candidate match (from bnf_candidates).
  // The tier drives the row's color treatment.
  // UniverseRow is module-scoped (defined near the bottom) so the new
  // presentation helpers (UniRow, TriageRail) can share the type.
  const universeRows: UniverseRow[] = useMemo(() => BNF_UNIVERSE.map((member) => {
    const latest = latestByTicker.get(member.ticker) ?? null;
    const candidate = candidateByTicker.get(member.ticker) ?? null;
    let tier: RowTier = 'none';
    if (candidate) tier = candidate.borderline ? 'borderline' : 'match';
    return {
      member,
      latest,
      candidate,
      tier,
      researchStatus: statusByTicker.get(member.ticker) ?? 'pending',
    };
  }), [latestByTicker, candidateByTicker, statusByTicker]);

  // Sort: matches first (by deviation, most-dislocated first), then
  // borderline (same ordering), then everyone else alphabetical. Within
  // a tier we want today's most-actionable names on top.
  const sortedUniverseRows: UniverseRow[] = useMemo(() => {
    const tierWeight: Record<RowTier, number> = { match: 0, borderline: 1, none: 2 };
    return [...universeRows].sort((a, b) => {
      const t = tierWeight[a.tier] - tierWeight[b.tier];
      if (t !== 0) return t;
      // Within matches / borderline, sort by deviation (most-negative first).
      if (a.tier !== 'none') {
        const ad = a.candidate?.deviation_pct ?? a.latest?.deviation_pct ?? 0;
        const bd = b.candidate?.deviation_pct ?? b.latest?.deviation_pct ?? 0;
        return ad - bd;
      }
      // Otherwise alphabetical so the long tail is browsable.
      return a.member.ticker.localeCompare(b.member.ticker);
    });
  }, [universeRows]);

  // ── Universe filter dropdown ──
  const [universeFilter, setUniverseFilter] = useState<UniverseFilter>('all');
  const filteredUniverseRows = useMemo(() => {
    return sortedUniverseRows.filter((r) => {
      switch (universeFilter) {
        case 'matches':    return r.tier === 'match';
        case 'near-miss':  return r.tier === 'borderline';
        case 'watchlist':  return r.researchStatus === 'considering' || r.researchStatus === 'approved';
        case 'equity':     return r.member.universe === 'EQUITY';
        case 'etf':        return r.member.universe === 'ETF';
        case 'all':
        default:           return true;
      }
    });
  }, [sortedUniverseRows, universeFilter]);

  // Counts for the filter chip + dashboard surface.
  const matchCount = universeRows.filter((r) => r.tier === 'match').length;
  const borderlineCount = universeRows.filter((r) => r.tier === 'borderline').length;
  const watchlistCount = universeRows.filter(
    (r) => r.researchStatus === 'considering' || r.researchStatus === 'approved',
  ).length;

  // Most recent latest_date across the universe — fed to the "last
  // updated" pill in the header so the user can see at a glance how
  // fresh the data is.
  const latestUniverseDate = useMemo(() => {
    let max = '';
    for (const r of universeLatest) {
      if (r.latest_date > max) max = r.latest_date;
    }
    return max || null;
  }, [universeLatest]);
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
  // Root carries `dash` (design tokens/atoms) + `np-app` so the legacy
  // ScanProgressBanner (.np-app .bnf-progress …) stays styled. positions.css
  // isn't imported here, so np-app only activates the bnf-* rules from
  // new-strategy.css — no token conflict with .dash.
  return (
    <div className="dash np-app">
      <div className="dash-inner">
        {/* Brand bar — same shell as Dashboard / Positions */}
        <div className="row first">
          <div className="brandbar">
            <div className="mark">
              <a className="logo" href={DASHBOARD_URL} style={{ textDecoration: 'none', cursor: 'pointer' }}>◆ SUNNYFI</a>
              <span className="slash">/</span>
              <span className="route">New Strategy<span className="cursor" /></span>
              <nav className="top-nav">
                <a className="nav-link" href="https://positions.sunnyfi.co">Positions</a>
                <a className="nav-link on">New Strategy</a>
              </nav>
            </div>
            <div className="actions ns-actions">
              <span className={'pill muted' + (backfilling || refreshingCache || scanning ? ' busy' : '')}
                onClick={() => !(backfilling || refreshingCache || scanning) && runCacheBackfill()}
                title="One-time: load 260 trading days of OHLCV into the cache (~3–5 min).">
                {backfilling ? 'Backfilling…' : '⤓ Backfill'}
              </span>
              <span className={'pill muted' + (refreshingCache || backfilling || scanning ? ' busy' : '')}
                onClick={() => !(refreshingCache || backfilling || scanning) && runCacheUpdate()}
                title="Daily incremental cache update (~10s).">
                {refreshingCache ? 'Updating…' : '↻ Refresh cache'}
              </span>
              <span className={'pill muted' + (refreshingFlags || candidates.length === 0 ? ' busy' : '')}
                onClick={() => !(refreshingFlags || candidates.length === 0) && runRefreshFlags()}
                title="Re-pull SEC EDGAR + earnings for current candidates.">
                {refreshingFlags ? 'Flags…' : '↻ Risk flags'}
              </span>
              <span className={'pill muted' + (scanning ? ' busy' : '')} onClick={() => !scanning && runScan('etf')} title="Scan the ~30 sector/industry ETFs.">
                {scanning && scanMode === 'etf' ? 'Scanning…' : '↻ ETF scan'}
              </span>
              <span className={'pill muted' + (scanning ? ' busy' : '')} onClick={() => !scanning && runScan('equity')} title="Scan the ~1000-name equity universe.">
                {scanning && scanMode === 'equity' ? 'Scanning…' : '↻ Equity scan'}
              </span>
              <span className={'pill refresh-all' + (scanning ? ' busy' : '')} onClick={() => !scanning && runScan('both')} title="Run both universes.">
                {scanning && scanMode === 'both' ? 'Scanning…' : '↻ Refresh all'}
              </span>
            </div>
          </div>
        </div>

        {/* Market context strip */}
        <div className="row tight" style={{ marginTop: 28 }}>
          <TickerStrip compact />
        </div>

        {/* Banners */}
        {scanErr && (
          <div className="row tight" style={{ marginTop: 18 }}>
            <div className="ns-banner err">Scan failed: {scanErr}</div>
          </div>
        )}
        {showStatus && scanStatus && (
          <div className="row tight" style={{ marginTop: 12 }}>
            <ScanProgressBanner status={scanStatus} onDismiss={() => setShowStatus(false)} />
          </div>
        )}
        {greenCount > 0 && (
          <div className="row tight" style={{ marginTop: 12 }}>
            <div className="ns-banner ready">▶ {greenCount} position{greenCount === 1 ? '' : 's'} ready to sell — price reached SMA25</div>
          </div>
        )}

        {/* § 00 — Today's scan hero + dev-band scatter */}
        <div className="row" style={{ marginTop: 56 }}>
          <Section n="00" right={<span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}><span className="live-dot" />{latestUniverseDate ? `last close ${latestUniverseDate}` : 'scan'}</span>}>Today's scan · BNF mean-reversion</Section>
          <div className="scan-hero">
            <div className="col"><div className="label">BNF match</div><div className="big neon"><CountUp value={matchCount} delay={50} /></div><div className="cap">dev ∈ [−15%, −7%] · close &gt; SMA200 · today &gt; −5%</div></div>
            <div className="col"><div className="label">Near miss</div><div className="big warn"><CountUp value={borderlineCount} delay={150} /></div><div className="cap">within 0.5% of any threshold</div></div>
            <div className="col"><div className="label">On watch</div><div className="big fg2"><CountUp value={watchlistCount} delay={250} /></div><div className="cap">considering or approved · not yet bought</div></div>
            <div className="col meta">
              <div><div className="label">Universe scanned</div><div className="scan-cnt"><CountUp value={universeRows.length} duration={1400} /> <span className="of">/ {universeRows.length}</span></div></div>
              <div><div className="stamp">S&amp;P 400 + 600 · <b>~30 sector ETFs</b></div>{latestUniverseDate && <div className="stamp" style={{ marginTop: 6 }}>Last close <b>{latestUniverseDate}</b></div>}</div>
            </div>
          </div>
          <ScanBand rows={sortedUniverseRows} />
        </div>

        {/* § 01 — Triage queue */}
        <div className="row" style={{ marginTop: 64 }}>
          <TriageRail
            rows={sortedUniverseRows}
            onStatus={(t, s) => setStatusMutation.mutate({ ticker: t, status: s })}
            onBuy={(c) => buyMutation.mutate(c)}
            buyPending={buyMutation.isPending}
          />
        </div>

        {/* § 02 — Pipeline */}
        <div className="row" style={{ marginTop: 72 }}>
          <Section n="02" right={<span style={{ color: 'var(--fg3)' }}>Approved → buy</span>}>Pipeline</Section>
          <div className="pipeline">
            {(() => {
              const consideringN = universeRows.filter((r) => r.researchStatus === 'considering').length;
              const approvedN = universeRows.filter((r) => r.researchStatus === 'approved').length;
              const boughtN = openPositions.length;
              const pendingN = matchCount + borderlineCount - consideringN - approvedN;
              const stage = (cls: string, label: string, v: number, sub: string, delay: number) => (
                <div className={'stage ' + cls}><span className="l">{label}</span><span className="v"><CountUp value={Math.max(0, v)} delay={delay} /></span><span className="sub">{sub}</span></div>
              );
              return (<>
                {stage('pending', 'Pending', pendingN, 'untouched', 0)}
                <div className="sep" />
                {stage('considering', 'Considering', consideringN, 'in research', 120)}
                <div className="sep" />
                {stage('approved', 'Approved', approvedN, 'ready to buy', 240)}
                <div className="sep" />
                {stage('bought', 'Bought', boughtN, 'in positions', 360)}
              </>);
            })()}
          </div>
        </div>

        {/* § 03 — Universe firehose */}
        <section className="np-section uni-section">
          <Section right={
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 12 }}>
              <span className="meta">{filteredUniverseRows.length} of {universeRows.length} shown</span>
              <span className={'pill muted' + (scanning ? ' busy' : '')} onClick={() => !scanning && runScan('both')} style={{ cursor: 'pointer' }}>↻ Rescan</span>
            </span>
          }>Universe</Section>
          <div className="uni-tools">
            <div className="group">
              <select className="sel" value={universeFilter} onChange={(e) => setUniverseFilter(e.target.value as UniverseFilter)} aria-label="Universe filter">
                <option value="all">All tickers</option>
                <option value="matches">BNF matches only</option>
                <option value="near-miss">Near miss only</option>
                <option value="watchlist">Watchlist (considering + approved)</option>
                <option value="equity">Equities only</option>
                <option value="etf">ETFs only</option>
              </select>
            </div>
            <div className="group">
              <label className="toggle">
                <input type="checkbox" checked={hideSkipped} onChange={(e) => setHideSkipped(e.target.checked)} />
                Hide skipped
              </label>
            </div>
          </div>
          <div className="uni-table-wrap">
            <table className="uni-table">
              <thead>
                <tr>
                  <th>Ticker</th>
                  <th>Name / sector</th>
                  <th className="num">Price</th>
                  <th className="num">SMA25</th>
                  <th className="num">Dev %</th>
                  <th className="num">Today</th>
                  <th className="num">ADV $M</th>
                  <th className="ctr">Risk</th>
                  <th>Setup</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {filteredUniverseRows.filter((r) => !hideSkipped || r.researchStatus !== 'skipped').length === 0 ? (
                  <tr><td colSpan={11} className="uni-empty">
                    {universeRows.length === 0
                      ? <>Universe cache is empty. Click <b>Backfill</b> to load history, then <b>Refresh all</b>.</>
                      : <>No tickers match this filter.</>}
                  </td></tr>
                ) : filteredUniverseRows
                    .filter((r) => !hideSkipped || r.researchStatus !== 'skipped')
                    .map((r) => (
                      <UniRow
                        key={`${r.member.universe}:${r.member.ticker}`}
                        row={r}
                        onTicker={() => setStatusMutation.mutate({ ticker: r.member.ticker, status: r.researchStatus })}
                        onStatus={(s) => setStatusMutation.mutate({ ticker: r.member.ticker, status: s })}
                        onBuy={() => r.candidate && buyMutation.mutate(r.candidate)}
                        busy={setStatusMutation.isPending || buyMutation.isPending}
                      />
                    ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* § 04 / 05 — open positions */}
        <div className="row" style={{ marginTop: 72 }}>
          <OpenPositionsV2
            title="Open equity positions"
            rows={equityOpenView}
            universe="EQUITY"
            stale={STALE_DAYS_EQUITY}
            onSell={(p, reason, exitPrice) => sellMutation.mutate({ p, reason, exitPrice })}
            sellPending={sellMutation.isPending}
          />
        </div>
        <div className="row" style={{ marginTop: 56 }}>
          <OpenPositionsV2
            title="Open ETF positions"
            rows={etfOpenView}
            universe="ETF"
            stale={STALE_DAYS_ETF}
            onSell={(p, reason, exitPrice) => sellMutation.mutate({ p, reason, exitPrice })}
            sellPending={sellMutation.isPending}
          />
        </div>

        {/* § 06 — closed trades */}
        {closedPositions.length > 0 && (
          <div className="row" style={{ marginTop: 72 }}>
            <ClosedV2
              rows={closedPositions}
              stats={closedStats}
              eq={closedEquityStats}
              etf={closedEtfStats}
              open={closedOpen}
              onToggle={() => setClosedOpen((v) => !v)}
            />
          </div>
        )}
      </div>
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
// ── Module-scoped row type, shared by the new presentation helpers ──
interface UniverseRow {
  member: UniverseMember;
  latest: UniverseLatestRow | null;
  candidate: Candidate | null;
  tier: RowTier;
  researchStatus: ResearchStatus;
}

// Effective per-row values — a fresh candidate snapshot beats the cache.
function rowVals(r: UniverseRow) {
  const c = r.candidate, l = r.latest;
  return {
    price: c?.price ?? l?.latest_close ?? null,
    sma25: c?.sma25 ?? l?.sma25 ?? null,
    dev: c?.deviation_pct ?? l?.deviation_pct ?? null,
    adv: c?.adv20_m ?? l?.adv20_m ?? null,
    today: c?.today_intraday_pct ?? l?.today_intraday_pct ?? null,
  };
}
// FlagTone (red/amber/none) → risk-dot class. A candidate with no concern
// reads green ('clean'); a non-candidate / no-data flag is grey ('none').
const dotCls = (t: FlagTone, isCand: boolean) =>
  t === 'red' ? 'caution' : t === 'amber' ? 'review' : isCand ? 'clean' : 'none';
const verdictLabel = (v: string | null) => (!v || v === 'none' ? '—' : v.charAt(0).toUpperCase() + v.slice(1));
const STATUS_CYCLE: Record<ResearchStatus, ResearchStatus> = {
  pending: 'considering', considering: 'approved', approved: 'pending', skipped: 'pending',
};
// Dev band: position a marker on the −15%…+5% axis.
const devBandPct = (v: number) => Math.max(2, Math.min(98, ((v - -15) / (5 - -15)) * 100));

// ── § 00 — dev% scatter band ──
function ScanBand({ rows }: { rows: UniverseRow[] }) {
  const min = -16, max = 5;
  const pct = (v: number) => ((v - min) / (max - min)) * 100;
  const ticks = [-15, -10, -7, -5, 0, 5];
  const dots = rows
    .map((r) => ({ x: rowVals(r).dev, tier: r.tier }))
    .filter((d): d is { x: number; tier: RowTier } => d.x != null && d.x >= min && d.x <= max);
  return (
    <div className="scan-band">
      <div className="axis">
        <div className="band-zone" style={{ left: pct(-15) + '%', right: (100 - pct(-7)) + '%' }} />
        <div className="axis-line" />
        {ticks.map((v) => (
          <div key={'t' + v}>
            <div className={'axis-tick' + (v === 0 ? ' zero' : '') + (v === -7 ? ' threshold' : '')} style={{ left: pct(v) + '%' }} />
            <div className={'axis-label' + (v === 0 ? ' zero' : '') + (v === -7 ? ' threshold' : '')} style={{ left: pct(v) + '%' }}>
              {v === -7 ? '−7% threshold' : v === 0 ? '0%' : v > 0 ? `+${v}%` : `${v}%`}
            </div>
          </div>
        ))}
        {dots.map((d, i) => (
          <div key={i} className={'dot ' + (d.tier === 'match' ? 'match' : d.tier === 'borderline' ? 'borderline' : 'muted')} style={{ left: pct(d.x) + '%' }} />
        ))}
      </div>
    </div>
  );
}

// ── § 01 — triage card ──
function TriageCard({ row, onStatus, onBuy, buyPending }: {
  row: UniverseRow;
  onStatus: (t: string, s: ResearchStatus) => void;
  onBuy: (c: Candidate) => void;
  buyPending: boolean;
}) {
  const { member, candidate, tier, researchStatus: status } = row;
  const v = rowVals(row);
  const tones = { earn: candidate ? earningsTone(candidate.days_since_earnings) : 'none' as FlagTone,
    ins: candidate ? insiderTone(candidate.insider_sales) : 'none' as FlagTone,
    k: candidate ? eightKTone(candidate.recent_8ks) : 'none' as FlagTone };
  const quality = candidate ? setupQuality(tones.earn, tones.ins, tones.k) : null;
  const cls = ['tcard', tier === 'match' ? 'match' : '', tier === 'borderline' ? 'borderline' : '',
    status === 'approved' ? 'approved' : '',
    tier === 'match' && (status === 'considering' || status === 'pending') ? 'breath' : ''].filter(Boolean).join(' ');
  const todayTone = (v.today ?? 0) < 0 ? 'neg' : 'pos';
  const markCls = tier === 'match' ? 'neon' : tier === 'borderline' ? 'warn' : '';
  const flagTile = (label: string, tone: FlagTone, val: string) => {
    const cl = tone === 'red' ? 'caution' : tone === 'amber' ? 'review' : (candidate ? 'clean' : 'none');
    return <div className={'flag ' + cl}><span className="fl">{label}</span><span className="fv">{val}</span></div>;
  };
  return (
    <div className={cls}>
      <div className="head">
        <div className="id">
          {member.universe === 'ETF' && <span className="badge etf">ETF</span>}
          <span className="t">{member.ticker}</span>
        </div>
        <span className={'verdict ' + (quality ?? 'none')}>{verdictLabel(quality)}</span>
      </div>
      <div className="name">{candidate?.name ?? member.name ?? '—'}</div>
      <div className="sector">{member.sector ?? member.category ?? ''}</div>
      <div className="price-block">
        <span className="price">{v.price != null ? fmtUSD(v.price) : '—'}</span>
        <div className="price-sub">
          <span className={'today ' + todayTone}>Today {v.today != null ? fmtPct(v.today) : '—'}</span>
          <span style={{ color: 'var(--fg5)' }}>·</span>
          <span>ADV {v.adv != null ? `$${v.adv.toFixed(0)}M` : '—'}</span>
        </div>
      </div>
      <div className="dev-wrap">
        <div className="dev-row">
          <span className="l">Dev from SMA25</span>
          <span className={'v ' + (v.dev != null && v.dev < 0 ? (tier === 'match' ? 'neon' : '') : 'up')}>{v.dev != null ? fmtPct(v.dev) : '—'}</span>
        </div>
        <div className="dev-band">
          <div className="zone" style={{ left: devBandPct(-15) + '%', right: (100 - devBandPct(-7)) + '%' }} />
          {v.dev != null && <div className={'marker ' + markCls} style={{ left: devBandPct(v.dev) + '%' }} />}
        </div>
        <div className="dev-axis"><span>−15%</span><span className="neon">−7%</span><span>0</span><span>+5%</span></div>
      </div>
      <div className="flags">
        {flagTile('Earnings', tones.earn, candidate?.days_since_earnings != null ? `${candidate.days_since_earnings}d` : '—')}
        {flagTile('Insider 14d', tones.ins, candidate ? fmtInsider(candidate.insider_sales) : '—')}
        {flagTile('8-K 14d', tones.k, candidate?.recent_8ks?.length ? String(candidate.recent_8ks.length) : '—')}
      </div>
      <div className="seg">
        {STATUS_OPTIONS.map((o) => (
          <button key={o.value} className={status === o.value ? 'on ' + o.value : ''} onClick={() => onStatus(member.ticker, o.value)}>
            {o.value === 'pending' ? '— pending' : o.value === 'skipped' ? '✕ skipped' : o.value === 'considering' ? '◐ consider' : '✓ approved'}
          </button>
        ))}
      </div>
      <div className="actions">
        <div className="left">
          {status === 'approved' ? <span className="neon">Ready to buy</span>
            : tier === 'match' ? <span>BNF match · {(v.dev ?? 0) <= -10 ? 'deep dip' : 'classic'}</span>
            : tier === 'borderline' ? <span>near miss</span> : <span>watching</span>}
        </div>
        {candidate && (
          <button className={'btn-buy' + (status === 'approved' ? ' neon' : '')} disabled={buyPending} onClick={() => onBuy(candidate)}>Buy →</button>
        )}
      </div>
    </div>
  );
}

// ── § 01 — triage rail (tabs + grid) ──
function TriageRail({ rows, onStatus, onBuy, buyPending }: {
  rows: UniverseRow[];
  onStatus: (t: string, s: ResearchStatus) => void;
  onBuy: (c: Candidate) => void;
  buyPending: boolean;
}) {
  const [tab, setTab] = useState<'match' | 'borderline' | 'watch' | 'approved'>('match');
  const counts = {
    match: rows.filter((r) => r.tier === 'match' && r.researchStatus !== 'skipped').length,
    borderline: rows.filter((r) => r.tier === 'borderline').length,
    watch: rows.filter((r) => r.researchStatus === 'considering' || r.researchStatus === 'approved').length,
    approved: rows.filter((r) => r.researchStatus === 'approved').length,
  };
  const shown = rows.filter((r) => {
    const s = r.researchStatus;
    if (tab === 'match') return r.tier === 'match' && s !== 'skipped';
    if (tab === 'borderline') return r.tier === 'borderline';
    if (tab === 'watch') return s === 'considering' || s === 'approved';
    return s === 'approved';
  }).slice(0, 6);
  return (
    <div>
      <Section n="01" right={<span style={{ color: 'var(--fg3)' }}>Triage queue · highest signal first</span>}>Today's decisions</Section>
      <div className="triage-tabs">
        {([['match', 'Matches'], ['borderline', 'Near miss'], ['watch', 'On watch'], ['approved', 'Approved']] as const).map(([k, label]) => (
          <button key={k} className={'tri-tab' + (tab === k ? ' on' : '')} onClick={() => setTab(k)}>
            {label} <span className="count">{counts[k]}</span>
          </button>
        ))}
      </div>
      {shown.length === 0 ? (
        <div className="triage-empty">Nothing in this lane right now.</div>
      ) : (
        <div className="triage-grid">
          {shown.map((r) => (
            <TriageCard key={`${r.member.universe}:${r.member.ticker}`} row={r} onStatus={onStatus} onBuy={onBuy} buyPending={buyPending} />
          ))}
        </div>
      )}
    </div>
  );
}

// ── § 03 — universe row ──
function UniRow({ row, onTicker, onStatus, onBuy, busy }: {
  row: UniverseRow;
  onTicker: () => void;
  onStatus: (s: ResearchStatus) => void;
  onBuy: () => void;
  busy: boolean;
}) {
  const { member, candidate, tier, researchStatus: status } = row;
  const v = rowVals(row);
  const tEarn = candidate ? earningsTone(candidate.days_since_earnings) : 'none';
  const tIns = candidate ? insiderTone(candidate.insider_sales) : 'none';
  const t8K = candidate ? eightKTone(candidate.recent_8ks) : 'none';
  const quality = candidate ? setupQuality(tEarn, tIns, t8K) : null;
  const rowCls = [
    tier === 'match' ? (status !== 'skipped' ? 'match breath' : 'match') : '',
    tier === 'borderline' ? 'borderline' : '',
    status === 'skipped' ? 'skipped' : '',
  ].filter(Boolean).join(' ');
  const devCls = tier === 'match' ? 'neon' : tier === 'borderline' ? 'warn' : (v.dev != null && v.dev > 0 ? 'up' : '');
  const todayCls = v.today != null && v.today < 0 ? 'down' : v.today != null && v.today > 0 ? 'up' : '';
  return (
    <tr className={rowCls}>
      <td>
        <span className="tk">
          <span className={'b ' + (member.universe === 'ETF' ? 'etf' : 'eq')}>{member.universe === 'ETF' ? 'ETF' : 'EQ'}</span>
          <span className="t" onClick={onTicker}>{member.ticker}</span>
        </span>
      </td>
      <td><span className="nm">{candidate?.name ?? member.name ?? '—'}{member.sector && <span className="sec">{member.sector}</span>}</span></td>
      <td className="num"><span className="px">{v.price != null ? fmtUSD(v.price) : '—'}</span></td>
      <td className="num muted">{v.sma25 != null ? fmtUSD(v.sma25) : '—'}</td>
      <td className="num">
        <span className={'dev ' + devCls}>{v.dev != null ? fmtPct(v.dev) : '—'}</span>
        {v.dev != null && (
          <div className="devbar-wrap">
            <div className="devbar-zone" style={{ left: devBandPct(-15) + '%', right: (100 - devBandPct(-7)) + '%' }} />
            <div className={'devbar-mk ' + devCls} style={{ left: devBandPct(v.dev) + '%' }} />
          </div>
        )}
      </td>
      <td className={'num ' + todayCls}>{v.today != null ? fmtPct(v.today) : '—'}</td>
      <td className="num muted">{v.adv != null ? `$${v.adv.toFixed(0)}` : '—'}</td>
      <td className="ctr">
        <span className="risk">
          <span className={'dot ' + dotCls(tEarn, !!candidate)} title={'Earnings: ' + (candidate?.days_since_earnings != null ? `${candidate.days_since_earnings}d` : '—')} />
          <span className={'dot ' + dotCls(tIns, !!candidate)} title={candidate ? insiderTooltip(candidate.insider_sales) || 'Insider: none' : 'Insider: —'} />
          <span className={'dot ' + dotCls(t8K, !!candidate)} title={candidate ? eightKTooltip(candidate.recent_8ks) || '8-K: none' : '8-K: —'} />
        </span>
      </td>
      <td><span className={'verdict ' + (quality ?? 'none')}>{verdictLabel(quality)}</span></td>
      <td>
        <button className={'stat ' + status} onClick={() => onStatus(STATUS_CYCLE[status])} disabled={busy} title="Cycle status">
          {status === 'pending' ? '— pending' : status === 'skipped' ? '✕ skipped' : status === 'considering' ? '◐ consider' : '✓ approved'}
        </button>
      </td>
      <td className="num">
        {candidate ? <button className={'ico-btn' + (status === 'approved' ? ' neon' : '')} disabled={busy} onClick={onBuy}>Buy</button> : null}
      </td>
    </tr>
  );
}

// ── § 04 / 05 — open positions table ──
function OpenPositionsV2({ title, rows, universe, stale, onSell, sellPending }: {
  title: string;
  rows: OpenView[];
  universe: Universe;
  stale: number;
  onSell: (p: OpenView, reason: string, exitPrice: number) => void;
  sellPending: boolean;
}) {
  return (
    <div>
      <Section n={universe === 'ETF' ? '05' : '04'} right={<span style={{ color: 'var(--fg3)' }}>Sell when ▲ green (target hit) or stale &gt;{stale}d</span>}>
        {title} · {rows.length}
      </Section>
      <table className="openpos-table">
        <thead>
          <tr>
            <th className="ctr">Status</th><th>Ticker</th><th className="num">Entry</th><th className="num">Entry $</th>
            <th className="num">Entry dev</th><th className="num">Now $</th><th className="num">SMA25</th>
            <th className="num">To SMA25</th><th className="num">UPnL %</th><th className="num">Days</th><th></th>
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr><td colSpan={11} className="openpos-empty">No {universe === 'ETF' ? 'ETF ' : ''}open positions. Buy a candidate above to start one.</td></tr>
          ) : rows.map((p) => {
            const exitPrice = p.currentPrice ?? p.entry_price;
            const reason = p.status === 'green' ? 'target_hit' : p.status === 'red' ? 'stale' : 'manual';
            return (
              <tr key={p.id}>
                <td className="ctr"><span className={'dot-status ' + p.status} /></td>
                <td><span className="t">{p.ticker}</span><span className="uni-tag">{universe === 'ETF' ? 'ETF' : 'EQ'}</span></td>
                <td className="num">{p.entry_date}</td>
                <td className="num">{fmtUSD(p.entry_price)}</td>
                <td className="num down">{fmtPct(p.entry_deviation_pct)}</td>
                <td className="num strong">{fmtUSD(p.currentPrice)}</td>
                <td className="num">{fmtUSD(p.sma25)}</td>
                <td className={'num ' + (p.distToSMA25Pct != null && p.distToSMA25Pct < 0 ? 'up' : '')}>{fmtPct(p.distToSMA25Pct)}</td>
                <td className={'num strong ' + ((p.unrealizedPct ?? 0) >= 0 ? 'up' : 'down')}>{fmtPct(p.unrealizedPct, 2)}</td>
                <td className={'num ' + (p.daysHeld > stale ? 'down' : '')}>{p.daysHeld}d</td>
                <td className="num"><button className={'ico-btn' + (p.status === 'green' ? ' neon' : '')} onClick={() => onSell(p, reason, exitPrice)} disabled={sellPending}>Sell</button></td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ── § 06 — closed trades ──
type ClosedStat = { total: number; winRate: number; avgReturn: number; avgDays: number } | null;
function ClosedV2({ rows, stats, eq, etf, open, onToggle }: {
  rows: Position[];
  stats: ClosedStat; eq: ClosedStat; etf: ClosedStat;
  open: boolean; onToggle: () => void;
}) {
  return (
    <div>
      <Section n="06">Closed trades</Section>
      <div className="closed-bar" onClick={onToggle}>
        <span className="caret">{open ? '▾' : '▸'}</span>
        <span className="title">{rows.length} trades</span>
        {eq && <span className="stat"><span className="b-eq">EQ</span> {eq.total} · win <b>{eq.winRate.toFixed(0)}%</b> · avg <b className={eq.avgReturn >= 0 ? 'pos' : 'neg'}>{fmtPct(eq.avgReturn, 1)}</b></span>}
        {etf && <span className="stat"><span className="b-etf">ETF</span> {etf.total} · win <b>{etf.winRate.toFixed(0)}%</b> · avg <b className={etf.avgReturn >= 0 ? 'pos' : 'neg'}>{fmtPct(etf.avgReturn, 1)}</b></span>}
        {stats && <span className="stat combined">all · win <b>{stats.winRate.toFixed(0)}%</b> · avg <b className={stats.avgReturn >= 0 ? 'pos' : 'neg'}>{fmtPct(stats.avgReturn, 1)}</b> · {stats.avgDays.toFixed(1)}d</span>}
      </div>
      {open && (
        <table className="openpos-table">
          <thead>
            <tr>
              <th className="ctr">Univ</th><th>Ticker</th><th className="num">Entry</th><th className="num">Exit</th>
              <th className="num">Entry $</th><th className="num">Exit $</th><th className="num">Return %</th><th className="num">Hold</th><th>Reason</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => {
              const hold = p.exit_date ? daysBetween(p.entry_date, p.exit_date) : 0;
              return (
                <tr key={p.id}>
                  <td className="ctr"><span className={'uni-badge' + (p.universe === 'ETF' ? ' etf' : '')}>{p.universe === 'ETF' ? 'ETF' : 'EQ'}</span></td>
                  <td><span className="t">{p.ticker}</span></td>
                  <td className="num">{p.entry_date}</td>
                  <td className="num">{p.exit_date}</td>
                  <td className="num">{fmtUSD(p.entry_price)}</td>
                  <td className="num">{fmtUSD(p.exit_price)}</td>
                  <td className={'num strong ' + ((p.realized_pct ?? 0) >= 0 ? 'up' : 'down')}>{fmtPct(p.realized_pct, 2)}</td>
                  <td className="num">{hold}d</td>
                  <td>{p.exit_reason}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
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
