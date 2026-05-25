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
const STALE_DAYS = 10;
const NEAR_TARGET_PCT = 2;      // within 2% of SMA25 → YELLOW

// ── Types matching the bnf_candidates / bnf_positions DB schema ──
interface Candidate {
  id: string;
  ticker: string;
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
}

interface Position {
  id: string;
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
  const runScan = async () => {
    setScanning(true);
    setScanErr(null);
    try {
      const { data, error } = await supabase.functions.invoke('bnf-scan');
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
      qc.invalidateQueries({ queryKey: ['bnf_candidates'] });
    } catch (e) {
      setScanErr((e as Error).message);
    } finally {
      setScanning(false);
    }
  };

  // ── Derived sets ──
  const openPositions = positions.filter((p) => p.status === 'open');
  const closedPositions = positions.filter((p) => p.status === 'closed');

  // Map ticker → most recent candidate snapshot so open positions can show
  // a fresh SMA25 without re-running the scanner per row.
  const lastCandidateByTicker = useMemo(() => {
    const m = new Map<string, Candidate>();
    for (const c of candidates) m.set(c.ticker, c);
    return m;
  }, [candidates]);

  // Open positions with derived status (GREEN/YELLOW/GREY/RED)
  interface OpenView extends Position {
    currentPrice: number | null;
    sma25: number | null;
    distToSMA25Pct: number | null;
    unrealizedPct: number | null;
    daysHeld: number;
    status: 'green' | 'yellow' | 'grey' | 'red';
  }
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
    if (daysHeld > STALE_DAYS && status !== 'green') status = 'red';
    return { ...p, currentPrice, sma25, distToSMA25Pct, unrealizedPct, daysHeld, status };
  });

  const greenCount = openWithDerived.filter((o) => o.status === 'green').length;

  // Closed-trade summary
  const closedStats = useMemo(() => {
    if (closedPositions.length === 0) return null;
    let wins = 0;
    let sumReturn = 0;
    let sumDays = 0;
    for (const p of closedPositions) {
      const r = p.realized_pct ?? 0;
      if (r > 0) wins++;
      sumReturn += r;
      if (p.exit_date) sumDays += daysBetween(p.entry_date, p.exit_date);
    }
    return {
      total: closedPositions.length,
      winRate: (wins / closedPositions.length) * 100,
      avgReturn: sumReturn / closedPositions.length,
      avgDays: sumDays / closedPositions.length,
    };
  }, [closedPositions]);

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
            className="np-btn neon"
            disabled={scanning}
            onClick={runScan}
          >
            {scanning ? 'Scanning…' : '↻ Refresh scan'}
          </button>
        </div>
      </header>

      <main className="np-main">
        {scanErr && (
          <div className="bnf-banner err">Scan failed: {scanErr}</div>
        )}

        {greenCount > 0 && (
          <div className="bnf-banner ready">
            ▶ {greenCount} position{greenCount === 1 ? '' : 's'} ready to sell — price reached SMA25
          </div>
        )}

        {/* ────── TODAY'S CANDIDATES ────── */}
        <section className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Today's candidates · {candidates.length}
            </div>
            <div className="np-section-sub">
              Sorted by deviation (most dislocated first). Dev ∈ [−15%, −7%], close &gt; SMA200,
              today &gt; −5%, sector ETF still healthy.
            </div>
          </div>
          <div className="np-table-wrap">
            <table className="np-table bnf-candidates-table">
              <thead>
                <tr>
                  <th>Ticker</th>
                  <th>Sector</th>
                  <th className="num">Price</th>
                  <th className="num">SMA25</th>
                  <th className="num">Dev %</th>
                  <th className="num">SMA200</th>
                  <th className="num">ADV20 $M</th>
                  <th className="num">Earn</th>
                  <th className="num">IV</th>
                  <th className="num">Opt vol</th>
                  <th className="num">P/C</th>
                  <th className="num">OI</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {candidates.length === 0 ? (
                  <tr>
                    <td colSpan={13} className="bnf-empty">
                      No candidates yet. Click <b>Refresh scan</b> to run the universe.
                    </td>
                  </tr>
                ) : candidates.map((c) => (
                  <tr key={c.id}>
                    <td className="ticker">{c.ticker}</td>
                    <td className="sector-cell">{c.sector ?? '—'}</td>
                    <td className="num strong">{fmtUSD(c.price)}</td>
                    <td className="num">{fmtUSD(c.sma25)}</td>
                    <td className="num down strong">{fmtPct(c.deviation_pct)}</td>
                    <td className="num">{fmtUSD(c.sma200)}</td>
                    <td className="num">{c.adv20_m ? `$${c.adv20_m.toFixed(0)}M` : '—'}</td>
                    <td className="num">{fmtDays(c.days_to_earnings)}</td>
                    <td className="num">{fmtIV(c.iv30)}</td>
                    <td className="num">{fmtNum(c.options_volume)}</td>
                    <td className="num">{c.put_call_ratio != null ? c.put_call_ratio.toFixed(2) : '—'}</td>
                    <td className="num">{fmtNum(c.open_interest)}</td>
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
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* ────── OPEN POSITIONS ────── */}
        <section className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Open positions · {openWithDerived.length}
            </div>
            <div className="np-section-sub">
              Status follows distance to SMA25. Sell when ▲ green (target hit) or when stale (&gt;{STALE_DAYS}d).
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
                {openWithDerived.length === 0 ? (
                  <tr><td colSpan={11} className="bnf-empty">No open positions. Buy a candidate above to start one.</td></tr>
                ) : openWithDerived.map((p) => {
                  const exitPrice = p.currentPrice ?? p.entry_price;
                  const reason =
                    p.status === 'green' ? 'target_hit'
                    : p.status === 'red' ? 'stale'
                    : 'manual';
                  return (
                    <tr key={p.id}>
                      <td><StatusDot tone={p.status} /></td>
                      <td className="ticker">{p.ticker}</td>
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
                      <td className={'num ' + (p.daysHeld > STALE_DAYS ? 'down' : '')}>
                        {p.daysHeld}d
                      </td>
                      <td className="num">
                        <button
                          className="np-btn bnf-row-btn"
                          onClick={() => sellMutation.mutate({ p, reason, exitPrice })}
                          disabled={sellMutation.isPending}
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
                  win rate <b>{closedStats.winRate.toFixed(0)}%</b>
                  {' · '}
                  avg <b className={closedStats.avgReturn >= 0 ? 'up' : 'down'}>{fmtPct(closedStats.avgReturn, 1)}</b>
                  {' · '}
                  avg hold <b>{closedStats.avgDays.toFixed(1)}d</b>
                </span>
              )}
            </button>
            {closedOpen && (
              <div className="np-table-wrap">
                <table className="np-table">
                  <thead>
                    <tr>
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
