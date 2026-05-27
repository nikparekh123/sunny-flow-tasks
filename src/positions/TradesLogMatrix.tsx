import { useMemo, useState } from 'react';
import {
  closeRealizedPL,
  fmtCompact,
  fmtQty,
  fmtUSD,
  fmtUSD2,
  type LiveOption,
  type OptionTrade,
  type PositionComputed,
  type ShareSell,
} from './types';

/**
 * Unified trades matrix.
 *
 * Per row (ticker), columns in order:
 *   Col 0           — Shares  (current live share position)
 *   Cols 1..N (N=OPTIONS_OPEN_COLS)
 *                   — live option opens (one per slot, leftmost = oldest
 *                     protective put → newest other; closed never
 *                     backfills here)
 *   Cols N+1..      — closed zone, mixed option closes + share sells,
 *                     sorted by close date desc
 *   Last col        — Realized total (option realized + stock realized)
 *
 * Click routing:
 *   • Shares cell        → onSharesCellClick(ticker)        — sell shares
 *   • Empty options slot → onOpenSlotClick(ticker)          — log new open
 *   • Live   options slot→ onOpenSlotClick(ticker)          — close / edit
 *   • Expired options    → onResolveCellClick(ticker, open) — resolve flow
 *   • Closed cells       — no-op (info only)
 */

const SHARES_COL = 0;          // index of the shares column
const OPTIONS_OPEN_COLS = 4;   // reserved live-options slots
const CLOSED_START_COL = SHARES_COL + 1 + OPTIONS_OPEN_COLS; // = 5

const WEEK_OPTIONS = [12, 26, 52, 104] as const;
type Weeks = typeof WEEK_OPTIONS[number];
const LS_TRADES_WEEKS = 'np:tradesWeeks';
function readWeeksLS(): Weeks {
  if (typeof window === 'undefined') return 52;
  const v = parseInt(window.localStorage.getItem(LS_TRADES_WEEKS) ?? '', 10);
  return (WEEK_OPTIONS as readonly number[]).includes(v) ? (v as Weeks) : 52;
}

const todayIso = (): string => new Date().toISOString().slice(0, 10);

/** Days between today and an ISO YYYY-MM-DD date. Positive = future, 0 = today,
 *  negative = past. Uses UTC midnight so timezone wobble doesn't shift the bucket. */
function daysFromToday(iso: string, todayIsoStr: string): number {
  const a = new Date(todayIsoStr + 'T00:00:00Z').getTime();
  const b = new Date(iso + 'T00:00:00Z').getTime();
  return Math.round((b - a) / 86400000);
}

/** Dynamic state label for a live option open. Replaces the static "open"
 *  pill with one that surfaces expiry proximity:
 *    expired        → past expiry        (negative tone)
 *    today          → expires 0 days     (warning tone — needs action today)
 *    tomorrow       → expires 1 day      (warning)
 *    in Nd          → 2..7 days out      (warning)
 *    open           → > 7 days           (neutral, today's behaviour)
 *  Returns `tone` as a class suffix and `title` for tooltip with the full date.
 */
function liveStateLabel(
  open: OptionTrade,
  todayIsoStr: string,
): { label: string; tone: 'expired' | 'urgent' | 'open'; title: string } {
  const d = daysFromToday(open.expiry, todayIsoStr);
  const niceDate = new Date(open.expiry + 'T00:00:00Z').toLocaleDateString(undefined, {
    month: 'short', day: 'numeric', year: 'numeric',
  });
  if (d < 0)   return { label: 'expired',  tone: 'expired', title: `expired ${niceDate} (${-d}d ago)` };
  if (d === 0) return { label: 'today',    tone: 'urgent',  title: `expires today · ${niceDate}` };
  if (d === 1) return { label: 'tomorrow', tone: 'urgent',  title: `expires tomorrow · ${niceDate}` };
  if (d <= 7)  return { label: `in ${d}d`, tone: 'urgent',  title: `expires in ${d} days · ${niceDate}` };
  return { label: 'open', tone: 'open', title: `expires ${niceDate} · ${d}d out` };
}

type StatusFilter = 'all' | 'active' | 'open' | 'closed';

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  liveByTicker: Map<string, LiveOption[]>;
  realizedByTicker: Map<string, number>;
  shareSellsByTicker: Map<string, ShareSell[]>;
  onTickerClick: (ticker: string) => void;
  /** Click on the leftmost Shares cell — opens Sell Shares flow. */
  onSharesCellClick: (ticker: string) => void;
  /** Click on an open-zone cell (empty or live, non-expired) — opens
   *  the Open/Close/Edit flow as today. */
  onOpenSlotClick: (ticker: string) => void;
  /** Click on an EXPIRED option open — opens the Resolve flow. */
  onResolveCellClick: (ticker: string, open: OptionTrade) => void;
}

/** Sentinel used in closed-zone slot resolution. */
type ClosedEntry =
  | { kind: 'live-overflow'; open: OptionTrade; sortDate: string }
  | { kind: 'option-closed'; open: OptionTrade; closes: OptionTrade[]; sortDate: string }
  | { kind: 'share-sell'; sell: ShareSell; sortDate: string };

export function TradesLogMatrix({
  rows,
  tradesByTicker,
  liveByTicker,
  realizedByTicker,
  shareSellsByTicker,
  onTickerClick,
  onSharesCellClick,
  onOpenSlotClick,
  onResolveCellClick,
}: Props) {
  const [filter, setFilter] = useState<StatusFilter>('all');
  const [weeks, setWeeksState] = useState<Weeks>(() => readWeeksLS());
  const setWeeks = (w: Weeks) => {
    setWeeksState(w);
    try { window.localStorage.setItem(LS_TRADES_WEEKS, String(w)); } catch { /* private */ }
  };
  const WEEK_COUNT = weeks;
  const today = todayIso();

  const counts = useMemo(
    () => ({
      all: rows.length,
      active: rows.filter(
        (r) =>
          (tradesByTicker.get(r.ticker)?.length ?? 0) > 0 ||
          (shareSellsByTicker.get(r.ticker)?.length ?? 0) > 0,
      ).length,
      open: rows.filter((r) => r.status === 'open').length,
      closed: rows.filter((r) => r.status === 'closed').length,
    }),
    [rows, tradesByTicker, shareSellsByTicker],
  );

  const filtered = useMemo(() => {
    if (filter === 'active')
      return rows.filter(
        (r) =>
          (tradesByTicker.get(r.ticker)?.length ?? 0) > 0 ||
          (shareSellsByTicker.get(r.ticker)?.length ?? 0) > 0,
      );
    if (filter === 'open')   return rows.filter((r) => r.status === 'open');
    if (filter === 'closed') return rows.filter((r) => r.status === 'closed');
    return rows;
  }, [rows, filter, tradesByTicker, shareSellsByTicker]);

  // A position is "effectively closed" when either:
  //   - the DB row is explicitly status='closed', OR
  //   - exposure is zero: 0 shares AND no live option positions.
  // The second case catches tickers like IT / MORN where the user sold
  // all shares and never marked the row closed in the DB — they read as
  // closed to the user even though `status` still says 'open'.
  const isEffectivelyClosed = (r: PositionComputed): boolean =>
    r.status === 'closed' ||
    (r.quantity === 0 && (r.live_options?.length ?? 0) === 0);

  // Sort: active positions first by realized P&L desc, effectively-closed
  // positions sink to the bottom (also sorted by realized inside that group).
  const sorted = useMemo(
    () =>
      [...filtered].sort((a, b) => {
        const aClosed = isEffectivelyClosed(a) ? 1 : 0;
        const bClosed = isEffectivelyClosed(b) ? 1 : 0;
        if (aClosed !== bClosed) return aClosed - bClosed;
        return (realizedByTicker.get(b.ticker) ?? 0) - (realizedByTicker.get(a.ticker) ?? 0);
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [filtered, realizedByTicker],
  );

  const isProtective = (t: OptionTrade) =>
    t.option_type === 'put' && t.direction === 'long';

  // Returns slot value for an option open: realized for closed pairs,
  // signed cash flow for live opens.
  const slotValueForOpen = useMemo(() => {
    const closesByOpen = new Map<string, OptionTrade[]>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action !== 'close' || !t.closes_trade_id) continue;
        const arr = closesByOpen.get(t.closes_trade_id) ?? [];
        arr.push(t);
        closesByOpen.set(t.closes_trade_id, arr);
      }
    }
    return (open: OptionTrade): number => {
      const closes = closesByOpen.get(open.id) ?? [];
      if (closes.length > 0) {
        return closes.reduce((s, c) => s + closeRealizedPL(c, open), 0);
      }
      const notional = open.contracts * 100 * open.premium;
      return open.direction === 'short' ? notional : -notional;
    };
  }, [tradesByTicker]);

  // Denominator for the "% of $X" footer: sum of premium PAID on options
  // that are STILL OPEN (calls + puts, long-direction only — long means
  // we wrote the cheque). Excludes:
  //   • short legs (we received premium on those, not paid)
  //   • opens that have been fully closed (the capital is no longer at risk)
  // Per-row equivalent feeds the right-column "X% of $Y" line, so users
  // can read realized P&L as a fraction of currently-outlaid premium.
  const openPaidByTicker = useMemo(() => {
    const m = new Map<string, number>();
    for (const [ticker, list] of tradesByTicker) {
      // Build a per-open closed-contracts tally so we can detect which
      // opens are still live. An open is "still open" when the contracts
      // its closes account for is less than the original contract count.
      const closedQtyByOpen = new Map<string, number>();
      for (const t of list) {
        if (t.action === 'close' && t.closes_trade_id) {
          closedQtyByOpen.set(
            t.closes_trade_id,
            (closedQtyByOpen.get(t.closes_trade_id) ?? 0) + t.contracts,
          );
        }
      }
      let paid = 0;
      for (const t of list) {
        if (t.action !== 'open' || t.direction !== 'long') continue;
        const closedQty = closedQtyByOpen.get(t.id) ?? 0;
        const stillOpenQty = t.contracts - closedQty;
        if (stillOpenQty <= 0) continue;          // fully closed — skip
        paid += stillOpenQty * 100 * t.premium;
      }
      m.set(ticker, paid);
    }
    return m;
  }, [tradesByTicker]);

  // Per-row decomposition: shares state + ordered open slots + ordered closed entries.
  // Used by both body render and footer math.
  function decomposeRow(r: PositionComputed): {
    liveOpens: OptionTrade[];
    closedEntries: ClosedEntry[];
  } {
    const trades = tradesByTicker.get(r.ticker) ?? [];
    const sells = shareSellsByTicker.get(r.ticker) ?? [];

    const closesByOpen = new Map<string, OptionTrade[]>();
    for (const t of trades) {
      if (t.action !== 'close' || !t.closes_trade_id) continue;
      const arr = closesByOpen.get(t.closes_trade_id) ?? [];
      arr.push(t);
      closesByOpen.set(t.closes_trade_id, arr);
    }
    const isFullyClosed = (open: OptionTrade): boolean => {
      const closes = closesByOpen.get(open.id) ?? [];
      return closes.reduce((s, c) => s + c.contracts, 0) >= open.contracts;
    };
    const mostRecentCloseDate = (open: OptionTrade): string => {
      const closes = closesByOpen.get(open.id) ?? [];
      if (closes.length === 0) return '';
      return closes.map((c) => c.trade_date).sort().reverse()[0];
    };

    const allOpens = trades.filter((t) => t.action === 'open');
    const liveOpens = allOpens
      .filter((t) => !isFullyClosed(t))
      .sort((a, b) => {
        const aP = isProtective(a) ? 0 : 1;
        const bP = isProtective(b) ? 0 : 1;
        if (aP !== bP) return aP - bP;
        return aP === 0
          ? a.trade_date !== b.trade_date
            ? a.trade_date.localeCompare(b.trade_date)
            : a.created_at.localeCompare(b.created_at)
          : b.trade_date !== a.trade_date
            ? b.trade_date.localeCompare(a.trade_date)
            : b.created_at.localeCompare(a.created_at);
      });
    const closedOpens = allOpens.filter((t) => isFullyClosed(t));

    // Closed-zone entries: live overflow first, then merged & sorted
    // closed-option / share-sell records by sortDate desc.
    const liveOverflow: ClosedEntry[] = liveOpens
      .slice(OPTIONS_OPEN_COLS)
      .map((open) => ({ kind: 'live-overflow' as const, open, sortDate: open.trade_date }));

    const closedOptionEntries: ClosedEntry[] = closedOpens.map((open) => ({
      kind: 'option-closed' as const,
      open,
      closes: closesByOpen.get(open.id) ?? [],
      sortDate: mostRecentCloseDate(open) || open.trade_date,
    }));

    const shareSellEntries: ClosedEntry[] = sells.map((sell) => ({
      kind: 'share-sell' as const,
      sell,
      sortDate: sell.trade_date,
    }));

    const merged = [...closedOptionEntries, ...shareSellEntries].sort((a, b) => {
      if (a.sortDate !== b.sortDate) return b.sortDate.localeCompare(a.sortDate);
      return 0;
    });

    return {
      liveOpens: liveOpens.slice(0, OPTIONS_OPEN_COLS),
      closedEntries: [...liveOverflow, ...merged],
    };
  }

  // Column-wise footer totals (cost basis, slot net, realized).
  const { columnTotals, columnSubLabels } = useMemo(() => {
    const totals = Array.from({ length: WEEK_COUNT }, () => 0);
    const subs: Array<string | null> = Array.from({ length: WEEK_COUNT }, () => null);

    sorted.forEach((r) => {
      const { liveOpens, closedEntries } = decomposeRow(r);

      // Col 0 — shares cost basis (qty × avg_cost) per ticker.
      totals[SHARES_COL] += r.quantity * r.avg_cost;

      // Cols 1..OPTIONS_OPEN_COLS — sum slot net (or put cost) for live opens.
      for (let s = 0; s < OPTIONS_OPEN_COLS; s++) {
        const col = SHARES_COL + 1 + s;
        if (col >= WEEK_COUNT) break;
        const open = liveOpens[s];
        if (!open) continue;
        if (isProtective(open)) {
          totals[col] += -(open.contracts * 100 * open.premium); // signed (cost)
        } else {
          totals[col] += slotValueForOpen(open);
        }
      }

      // Cols CLOSED_START_COL+ — sum cell values.
      for (let s = 0; s < closedEntries.length; s++) {
        const col = CLOSED_START_COL + s;
        if (col >= WEEK_COUNT) break;
        const entry = closedEntries[s];
        if (entry.kind === 'option-closed') {
          totals[col] += entry.closes.reduce(
            (acc, c) => acc + closeRealizedPL(c, entry.open),
            0,
          );
        } else if (entry.kind === 'live-overflow') {
          totals[col] += slotValueForOpen(entry.open);
        } else if (entry.kind === 'share-sell') {
          totals[col] += entry.sell.realized_pl;
        }
      }
    });

    // Sub-labels per col footer:
    //   col 0 → "cost basis"
    //   open cols → blank (or weekly burn for protective put col)
    //   closed cols → blank
    subs[SHARES_COL] = 'cost basis';
    return { columnTotals: totals, columnSubLabels: subs };
  }, [sorted, tradesByTicker, shareSellsByTicker, WEEK_COUNT, slotValueForOpen]);

  const grandOpenPaid = useMemo(
    () => Array.from(openPaidByTicker.values()).reduce((s, v) => s + v, 0),
    [openPaidByTicker],
  );
  const grandOptionRealized = useMemo(
    () => sorted.reduce((s, r) => s + (realizedByTicker.get(r.ticker) ?? 0), 0),
    [sorted, realizedByTicker],
  );
  const grandStockRealized = useMemo(
    () => sorted.reduce((s, r) => s + (r.realized_stock_pl ?? 0), 0),
    [sorted],
  );
  const grandRealized = grandOptionRealized + grandStockRealized;
  const totalTradesCount = useMemo(
    () =>
      sorted.reduce(
        (s, r) =>
          s +
          (tradesByTicker.get(r.ticker)?.length ?? 0) +
          (shareSellsByTicker.get(r.ticker)?.length ?? 0),
        0,
      ),
    [sorted, tradesByTicker, shareSellsByTicker],
  );

  // ─── Render ──────────────────────────────────────────────────────
  return (
    <div className="gl-wrap">
      <div className="gl-toolbar">
        {/* Status filter (All / Has trades / Open / Closed) removed —
            wasn't used in practice. The matrix always renders the full
            set; the `filter` state stays as 'all' so the downstream
            filterSet memo logic still works. */}
        <div className="gl-timeframe">
          {WEEK_OPTIONS.map((w) => (
            <button
              key={w}
              className={weeks === w ? 'on' : ''}
              onClick={() => setWeeks(w)}
              title={`Show ${w} columns total`}
            >
              {w}w
            </button>
          ))}
        </div>
      </div>

      <div className="gl-scroll">
        <table className="gl-table">
          <thead>
            <tr>
              <th className="gl-pos">Position</th>
              {Array.from({ length: WEEK_COUNT }, (_, i) => {
                const zone =
                  i === SHARES_COL
                    ? 'shares-zone'
                    : i < CLOSED_START_COL
                      ? 'live-zone'
                      : 'closed-zone';
                const sub =
                  i === SHARES_COL
                    ? 'shares open'
                    : i < CLOSED_START_COL
                      ? 'options open'
                      : 'closed';
                return (
                  <th key={i} className={`gl-wk ${zone}`}>
                    <div className="gl-wk-l">{i + 1}</div>
                    <div className="gl-wk-sub">{sub}</div>
                  </th>
                );
              })}
              <th className="gl-tot">Realized</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const { liveOpens, closedEntries } = decomposeRow(r);
              const optionRealized = realizedByTicker.get(r.ticker) ?? 0;
              const stockRealized = r.realized_stock_pl ?? 0;
              const realized = optionRealized + stockRealized;

              const isOptionExpired = (open: OptionTrade): boolean =>
                open.expiry < today;

              return (
                <tr key={r.ticker} className={isEffectivelyClosed(r) ? 'closed-row' : ''}>
                  <td className="gl-pos">
                    <span
                      className="ticker clickable"
                      onClick={() => onTickerClick(r.ticker)}
                    >
                      {r.ticker}
                    </span>
                    {isEffectivelyClosed(r) && (
                      <span className="status-pill closed">closed</span>
                    )}
                    <div className="gl-pos-sub">
                      {r.sector}
                      {liveOpens.length > 0 && (
                        <span className="gl-live-count"> · {liveOpens.length} open</span>
                      )}
                    </div>
                  </td>

                  {Array.from({ length: WEEK_COUNT }, (_, i) => {
                    // ─── Shares column ──────────────────────────────
                    if (i === SHARES_COL) {
                      const hasShares = r.quantity > 0;
                      return (
                        <td
                          key={i}
                          className={
                            'gl-cell shares-zone ' +
                            (hasShares ? 'filled' : 'empty')
                          }
                          onClick={() => hasShares && onSharesCellClick(r.ticker)}
                          title={
                            hasShares
                              ? `${fmtQty(r.quantity)} shares · avg ${fmtUSD2(r.avg_cost)} — click to sell shares`
                              : 'no shares'
                          }
                        >
                          {hasShares ? (
                            <div className="gl-cell-in">
                              <div className="gl-cell-amt">
                                {fmtCompact(r.quantity).replace('$', '')}
                              </div>
                              <div className="gl-cell-chips">
                                <span className="gl-cell-state open">
                                  @ {fmtUSD2(r.avg_cost)}
                                </span>
                              </div>
                            </div>
                          ) : (
                            <span className="muted">—</span>
                          )}
                        </td>
                      );
                    }

                    // ─── Options Open columns (1..OPTIONS_OPEN_COLS) ──
                    if (i < CLOSED_START_COL) {
                      const slotIdx = i - 1; // 0..3
                      const open = liveOpens[slotIdx];
                      if (!open) {
                        return (
                          <td
                            key={i}
                            className="gl-cell live-zone empty"
                            onClick={() => onOpenSlotClick(r.ticker)}
                            title="tap to open a new position"
                          >
                            <span className="gl-plus">+</span>
                          </td>
                        );
                      }
                      const expired = isOptionExpired(open);
                      // Expiring today also routes to the Resolve flow — after
                      // market close on expiry day, ITM/OTM is settled.
                      const expiringToday = open.expiry === today;
                      const needsResolve = expired || expiringToday;
                      const signed = slotValueForOpen(open);
                      const state = liveStateLabel(open, today);
                      return (
                        <td
                          key={i}
                          className={
                            'gl-cell live-zone filled ' +
                            (expired ? 'expired' : state.tone === 'urgent' ? 'urgent' : '')
                          }
                          onClick={() => {
                            if (needsResolve) onResolveCellClick(r.ticker, open);
                            else onOpenSlotClick(r.ticker);
                          }}
                          title={
                            `${open.direction} ${open.option_type} ${open.contracts}× $${open.strike} · ` +
                            `opened ${open.trade_date} · ${state.title} · ${fmtUSD(signed)}`
                          }
                        >
                          <div className="gl-cell-in">
                            <div
                              className={
                                'gl-cell-amt ' +
                                (signed < 0 ? 'down' : signed > 0 ? 'up' : '')
                              }
                            >
                              {signed >= 0
                                ? fmtCompact(signed)
                                : '−' + fmtCompact(Math.abs(signed))}
                            </div>
                            <div className="gl-cell-chips">
                              <span
                                className={
                                  'gl-dot rk-' +
                                  (open.option_type === 'put' ? 'p' : 'c') +
                                  (signed < 0 ? ' neg' : '')
                                }
                              />
                              <span className={'gl-cell-state ' + state.tone}>
                                {state.label}
                              </span>
                            </div>
                          </div>
                        </td>
                      );
                    }

                    // ─── Closed zone (CLOSED_START_COL..) ────────────
                    const entryIdx = i - CLOSED_START_COL;
                    const entry = closedEntries[entryIdx];
                    if (!entry) {
                      return (
                        <td key={i} className="gl-cell closed-zone empty">
                          <span className="muted">—</span>
                        </td>
                      );
                    }
                    if (entry.kind === 'share-sell') {
                      const v = entry.sell.realized_pl;
                      return (
                        <td
                          key={i}
                          className="gl-cell closed-zone filled share-sell"
                          title={
                            `Sold ${fmtQty(entry.sell.quantity)} sh @ ${fmtUSD2(entry.sell.price)} · ` +
                            `${entry.sell.trade_date} · ` +
                            `${entry.sell.source === 'assignment' ? 'assignment' : 'manual'} · ` +
                            `realized ${fmtUSD(v)}`
                          }
                        >
                          <div className="gl-cell-in">
                            <div
                              className={
                                'gl-cell-amt ' + (v < 0 ? 'down' : v > 0 ? 'up' : '')
                              }
                            >
                              {v >= 0 ? fmtCompact(v) : '−' + fmtCompact(Math.abs(v))}
                            </div>
                            <div className="gl-cell-chips">
                              <span className="gl-dot rk-s" />
                              <span className="gl-cell-state closed">
                                {entry.sell.source === 'assignment' ? 'assigned' : 'sold'}
                              </span>
                            </div>
                          </div>
                        </td>
                      );
                    }
                    if (entry.kind === 'live-overflow') {
                      // 5th+ live open spilled here. Render as a live cell
                      // but inside the closed zone (visually a bit odd).
                      const open = entry.open;
                      const expired = isOptionExpired(open);
                      const expiringToday = open.expiry === today;
                      const needsResolve = expired || expiringToday;
                      const signed = slotValueForOpen(open);
                      const state = liveStateLabel(open, today);
                      return (
                        <td
                          key={i}
                          className={
                            'gl-cell closed-zone filled overflow-live ' +
                            (expired ? 'expired' : state.tone === 'urgent' ? 'urgent' : '')
                          }
                          onClick={() => {
                            if (needsResolve) onResolveCellClick(r.ticker, open);
                            else onOpenSlotClick(r.ticker);
                          }}
                          title={
                            `${open.direction} ${open.option_type} ${open.contracts}× $${open.strike} · ` +
                            `opened ${open.trade_date} · ${state.title} (overflow)`
                          }
                        >
                          <div className="gl-cell-in">
                            <div
                              className={
                                'gl-cell-amt ' +
                                (signed < 0 ? 'down' : signed > 0 ? 'up' : '')
                              }
                            >
                              {signed >= 0
                                ? fmtCompact(signed)
                                : '−' + fmtCompact(Math.abs(signed))}
                            </div>
                            <div className="gl-cell-chips">
                              <span
                                className={
                                  'gl-dot rk-' +
                                  (open.option_type === 'put' ? 'p' : 'c')
                                }
                              />
                              <span className={'gl-cell-state ' + state.tone}>
                                {state.label}
                              </span>
                            </div>
                          </div>
                        </td>
                      );
                    }
                    // entry.kind === 'option-closed'
                    const open = entry.open;
                    const closes = entry.closes;
                    const closedQty = closes.reduce((s, c) => s + c.contracts, 0);
                    const isFullyClosed = closedQty >= open.contracts;
                    const isPartial = closes.length > 0 && !isFullyClosed;
                    const realizedCell = closes.reduce(
                      (s, c) => s + closeRealizedPL(c, open),
                      0,
                    );
                    const stateLabel = isFullyClosed
                      ? 'closed'
                      : isPartial
                        ? 'partial'
                        : 'open';
                    return (
                      <td
                        key={i}
                        className="gl-cell closed-zone filled"
                        title={
                          `${open.direction} ${open.option_type} ${open.contracts}× $${open.strike} · ` +
                          `opened ${open.trade_date} · ${stateLabel} · ${fmtUSD(realizedCell)}`
                        }
                      >
                        <div className="gl-cell-in">
                          <div
                            className={
                              'gl-cell-amt ' +
                              (realizedCell < 0
                                ? 'down'
                                : realizedCell > 0
                                  ? 'up'
                                  : '')
                            }
                          >
                            {realizedCell >= 0
                              ? fmtCompact(realizedCell)
                              : '−' + fmtCompact(Math.abs(realizedCell))}
                          </div>
                          <div className="gl-cell-chips">
                            <span
                              className={
                                'gl-dot rk-' +
                                (open.option_type === 'put' ? 'p' : 'c') +
                                (realizedCell < 0 ? ' neg' : '')
                              }
                            />
                            <span className={'gl-cell-state ' + stateLabel}>
                              {stateLabel}
                            </span>
                          </div>
                        </div>
                      </td>
                    );
                  })}

                  <td className="gl-tot">
                    <div
                      className={
                        'gl-tot-amt ' +
                        (realized < 0 ? 'down' : realized > 0 ? 'up' : '')
                      }
                    >
                      {realized === 0 ? (
                        <span style={{ color: 'var(--navi-fg5)' }}>—</span>
                      ) : realized >= 0 ? (
                        fmtUSD(realized)
                      ) : (
                        '−' + fmtUSD(Math.abs(realized))
                      )}
                    </div>
                    {(() => {
                      const openPaid = openPaidByTicker.get(r.ticker) ?? 0;
                      if (openPaid <= 0) return null;
                      const pct = (realized / openPaid) * 100;
                      return (
                        <div className="gl-tot-sub">
                          {pct >= 0 ? '+' : ''}
                          {pct.toFixed(0)}% of {fmtCompact(openPaid)}
                        </div>
                      );
                    })()}
                  </td>
                </tr>
              );
            })}
            {sorted.length === 0 && (
              <tr>
                <td
                  colSpan={WEEK_COUNT + 2}
                  style={{ textAlign: 'center', padding: 32, color: 'var(--navi-fg3)' }}
                >
                  No positions match this filter
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr className="gl-foot">
              <td className="gl-pos">
                <b>Total</b>
                <div className="gl-pos-sub">{totalTradesCount} trades · realized + open</div>
              </td>
              {Array.from({ length: WEEK_COUNT }, (_, i) => {
                const total = columnTotals[i];
                const sub = columnSubLabels[i];
                const zone =
                  i === SHARES_COL
                    ? 'shares-zone'
                    : i < CLOSED_START_COL
                      ? 'live-zone'
                      : 'closed-zone';
                if (total === 0 && i !== SHARES_COL) {
                  return (
                    <td key={i} className={`gl-cell sum ${zone}`}>
                      <span className="muted">—</span>
                    </td>
                  );
                }
                const isPos = total >= 0;
                return (
                  <td key={i} className={`gl-cell sum ${zone}`}>
                    <div className="gl-cell-in">
                      <div className={'gl-cell-amt ' + (isPos ? 'up' : 'down')}>
                        {isPos
                          ? fmtCompact(total)
                          : '−' + fmtCompact(Math.abs(total))}
                      </div>
                      {sub && (
                        <div className="gl-cell-chips">
                          <span className="gl-cell-state">{sub}</span>
                        </div>
                      )}
                    </div>
                  </td>
                );
              })}
              <td className="gl-tot">
                <div
                  className={
                    'gl-tot-amt ' +
                    (grandRealized < 0
                      ? 'down'
                      : grandRealized > 0
                        ? 'up'
                        : '')
                  }
                >
                  {grandRealized >= 0
                    ? fmtUSD(grandRealized)
                    : '−' + fmtUSD(Math.abs(grandRealized))}
                </div>
                {grandOpenPaid > 0 && (
                  <div className="gl-tot-sub">
                    {((grandRealized / grandOpenPaid) * 100).toFixed(0)}% of{' '}
                    {fmtCompact(grandOpenPaid)}
                  </div>
                )}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}
