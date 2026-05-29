import { useMemo, useState } from "react";
import {
  closeRealizedPL,
  fmtCompact,
  fmtQty,
  fmtUSD,
  fmtUSD2,
  type OptionTrade,
  type PositionComputed,
  type ShareSell,
} from "./types";

/**
 * Trades matrix v3 — redesigned per the Sunnyfi positions-ledger design.
 *
 * One row per ticker. Columns are NUMBERED slots:
 *   1        SHARES OPEN          qty @ avg cost
 *   2..5     OPTIONS OPEN         up to 4 live legs (sorted by expiry asc)
 *   6..8     CLOSED               up to 3 most-recent closed legs in window
 *                                 (closed option pairs + share sells / assignments)
 *   REALIZED                      realized P&L in window + % of cost basis
 *
 * Open + closed are inline in the same row (no Open/Closed view toggle).
 * Timeframe pills (12/26/52/104 weeks) filter Closed legs + Realized only —
 * open legs always reflect current state.
 *
 * Cell tags: OPEN, TODAY, IN Xd, EXPIRED, CLOSED, SOLD, ASSIGNED.
 * Amount sign + colour: + green = credit (sold/short or realized gain),
 * − red = debit (bought/long or realized loss).
 * Highlight border: yellow for today/expiring within 7d, red for expired.
 */

const OPEN_SLOTS = 4;
const CLOSED_SLOTS = 3;
const WEEK_OPTIONS = [12, 26, 52, 104] as const;
type Weeks = (typeof WEEK_OPTIONS)[number];
const LS_TRADES_WEEKS = "np:tradesWeeks";

function readWeeksLS(): Weeks {
  if (typeof window === "undefined") return 12;
  const v = parseInt(window.localStorage.getItem(LS_TRADES_WEEKS) ?? "", 10);
  return (WEEK_OPTIONS as readonly number[]).includes(v) ? (v as Weeks) : 12;
}

const todayIso = (): string => new Date().toISOString().slice(0, 10);
function daysUntil(iso: string, todayStr: string): number {
  const a = new Date(iso + "T00:00:00Z").getTime();
  const b = new Date(todayStr + "T00:00:00Z").getTime();
  return Math.round((a - b) / 86_400_000);
}

type StateTone = "open" | "today" | "urgent" | "expired" | "closed" | "sold" | "assigned";
interface StateTag { label: string; tone: StateTone; }

function liveState(open: OptionTrade, today: string): StateTag {
  const d = daysUntil(open.expiry, today);
  if (d < 0) return { label: "EXPIRED", tone: "expired" };
  if (d === 0) return { label: "TODAY", tone: "today" };
  if (d <= 7) return { label: `IN ${d}D`, tone: "urgent" };
  return { label: `IN ${d}D`, tone: "open" };
}

interface OpenSlot {
  open: OptionTrade;
  signedPremium: number;     // + for sold (short), − for paid (long)
  state: StateTag;
}

interface ClosedSlot {
  kind: "option" | "share";
  amount: number;            // realized P&L (signed)
  state: StateTag;
  date: string;
  detail: string;
  open?: OptionTrade;        // for option closes — for click routing
}

interface RowData {
  r: PositionComputed;
  openSlots: OpenSlot[];
  closedSlots: ClosedSlot[];
  liveCount: number;
  realizedInWindow: number;
  basis: number;             // cost-basis denominator for the % of $ label
  tradesCount: number;
  effectivelyClosed: boolean;
}

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  realizedByTicker: Map<string, number>;
  shareSellsByTicker: Map<string, ShareSell[]>;
  onTickerClick: (ticker: string) => void;
  onSharesCellClick: (ticker: string) => void;
  onOpenSlotClick: (ticker: string, mode?: "open" | "close") => void;
  onResolveCellClick: (ticker: string, open: OptionTrade) => void;
}

export function TradesMatrixV2({
  rows,
  tradesByTicker,
  realizedByTicker: _realizedByTicker,
  shareSellsByTicker,
  onTickerClick,
  onSharesCellClick,
  onOpenSlotClick,
  onResolveCellClick,
}: Props) {
  void _realizedByTicker;
  const [weeks, setWeeksState] = useState<Weeks>(() => readWeeksLS());
  const setWeeks = (w: Weeks) => {
    setWeeksState(w);
    try { window.localStorage.setItem(LS_TRADES_WEEKS, String(w)); } catch { /* private */ }
  };
  const today = todayIso();
  const windowStart = useMemo(() => {
    const d = new Date(); d.setDate(d.getDate() - weeks * 7);
    return d.toISOString().slice(0, 10);
  }, [weeks]);

  const enriched: RowData[] = useMemo(() => {
    return rows.map((r) => {
      const trades = tradesByTicker.get(r.ticker) ?? [];
      const sells = shareSellsByTicker.get(r.ticker) ?? [];

      const closesByOpen = new Map<string, OptionTrade[]>();
      for (const t of trades) {
        if (t.action !== "close" || !t.closes_trade_id) continue;
        const arr = closesByOpen.get(t.closes_trade_id) ?? [];
        arr.push(t);
        closesByOpen.set(t.closes_trade_id, arr);
      }
      const isFullyClosed = (o: OptionTrade) =>
        (closesByOpen.get(o.id) ?? []).reduce((s, c) => s + c.contracts, 0) >= o.contracts;
      const mostRecentClose = (o: OptionTrade) => {
        const cs = closesByOpen.get(o.id) ?? [];
        return cs.length ? cs.map((c) => c.trade_date).sort().slice(-1)[0]! : o.trade_date;
      };

      const allOpens = trades.filter((t) => t.action === "open");

      // Open slots — live legs, by expiry asc.
      const live = allOpens.filter((t) => !isFullyClosed(t))
        .sort((a, b) => a.expiry.localeCompare(b.expiry));
      const openSlots: OpenSlot[] = live.slice(0, OPEN_SLOTS).map((t) => {
        const notional = t.contracts * 100 * t.premium;
        const signed = t.direction === "short" ? notional : -notional;
        return { open: t, signedPremium: signed, state: liveState(t, today) };
      });

      // Closed slots — option closes + share sells, in the window, by date desc.
      const closedOptions: ClosedSlot[] = allOpens.filter(isFullyClosed).map((o) => {
        const cs = closesByOpen.get(o.id) ?? [];
        const realized = cs.reduce((s, c) => s + closeRealizedPL(c, o), 0);
        const date = mostRecentClose(o);
        const lastVia = cs[cs.length - 1]?.closed_via;
        let state: StateTag = { label: "CLOSED", tone: "closed" };
        if (lastVia === "assigned") state = { label: "ASSIGNED", tone: "assigned" };
        else if (lastVia === "expired_worthless") state = { label: "EXPIRED", tone: "expired" };
        return {
          kind: "option" as const,
          amount: realized,
          state,
          date,
          detail: `${o.direction} ${o.option_type} ${o.contracts}× $${o.strike} · closed ${date} · ${fmtUSD(realized)}`,
          open: o,
        };
      });
      const closedSells: ClosedSlot[] = sells.map((s) => ({
        kind: "share" as const,
        amount: s.realized_pl,
        state: { label: s.source === "assignment" ? "ASSIGNED" : "SOLD", tone: s.source === "assignment" ? "assigned" : "sold" },
        date: s.trade_date,
        detail: `Sold ${fmtQty(s.quantity)} sh @ ${fmtUSD2(s.price)} · ${s.trade_date} · ${fmtUSD(s.realized_pl)}`,
      }));
      const allClosed = [...closedOptions, ...closedSells]
        .filter((c) => c.date >= windowStart)
        .sort((a, b) => b.date.localeCompare(a.date));
      const closedSlots = allClosed.slice(0, CLOSED_SLOTS);

      const realizedInWindow = allClosed.reduce((s, c) => s + c.amount, 0);
      // Cost basis for the % label: total premium $ on the closed-option opens in
      // the window (the capital deployed on what's been realized).
      const basis = allClosed.reduce((s, c) => {
        if (c.kind === "option" && c.open) return s + c.open.contracts * 100 * c.open.premium;
        return s;
      }, 0);

      const effectivelyClosed = r.status === "closed" || (r.quantity === 0 && live.length === 0);

      return {
        r, openSlots, closedSlots,
        liveCount: live.length,
        realizedInWindow, basis,
        tradesCount: trades.length,
        effectivelyClosed,
      };
    });
  }, [rows, tradesByTicker, shareSellsByTicker, windowStart, today]);

  const visibleRows = useMemo(() => {
    const kept = enriched.filter((e) =>
      e.r.quantity > 0 || e.openSlots.length > 0 || e.closedSlots.length > 0,
    );
    // Active rows first, then by abs(realized) desc.
    kept.sort((a, b) => {
      if (a.effectivelyClosed !== b.effectivelyClosed) return a.effectivelyClosed ? 1 : -1;
      return Math.abs(b.realizedInWindow) - Math.abs(a.realizedInWindow);
    });
    return kept;
  }, [enriched]);

  const tickerCount = visibleRows.length;
  const tradesCount = useMemo(() => visibleRows.reduce((s, e) => s + e.tradesCount, 0), [visibleRows]);

  const fmtSignedUSD = (v: number) => (v >= 0 ? "+" : "−") + "$" + Math.abs(Math.round(v)).toLocaleString();
  const signedCompact = (v: number) => (v >= 0 ? "+" : "−") + fmtCompact(Math.abs(v));

  return (
    <div className="tm2-wrap">
      <div className="tm2-header">
        <span className="tm2-sub">
          {tickerCount} TICKERS · {tradesCount} TRADES · {weeks}W
        </span>
        <div className="tm2-weeks">
          {WEEK_OPTIONS.map((w) => (
            <button
              key={w}
              type="button"
              className={"tm2-week" + (weeks === w ? " on" : "")}
              onClick={() => setWeeks(w)}
            >
              {w}W
            </button>
          ))}
        </div>
      </div>

      <div className="tm2-scroll">
        <table className="tm2-table">
          <thead>
            <tr>
              <th className="tm2-pos-h">POSITION</th>
              <th className="tm2-col-h shares">
                <span className="idx">1</span>
                <span className="lbl">SHARES OPEN</span>
              </th>
              {Array.from({ length: OPEN_SLOTS }, (_, i) => (
                <th key={`oh${i}`} className="tm2-col-h open">
                  <span className="idx">{i + 2}</span>
                  <span className="lbl">OPTIONS OPEN</span>
                </th>
              ))}
              {Array.from({ length: CLOSED_SLOTS }, (_, i) => (
                <th key={`ch${i}`} className="tm2-col-h closed">
                  <span className="idx">{i + 2 + OPEN_SLOTS}</span>
                  <span className="lbl">CLOSED</span>
                </th>
              ))}
              <th className="tm2-realized-h">REALIZED</th>
            </tr>
          </thead>

          <tbody>
            {visibleRows.map((e) => {
              const r = e.r;
              const realized = e.realizedInWindow;
              const pct = e.basis > 0 ? (realized / e.basis) * 100 : 0;
              return (
                <tr key={r.ticker} className={"tm2-row" + (e.effectivelyClosed ? " dim" : "")}>
                  <td className="tm2-pos">
                    <button type="button" className="t" onClick={() => onTickerClick(r.ticker)}>{r.ticker}</button>
                    <div className="sub">
                      {r.sector}{e.liveCount > 0 ? <> · <span className="open-count">{e.liveCount} OPEN</span></> : null}
                    </div>
                  </td>

                  {/* Shares */}
                  {r.quantity > 0 ? (
                    <td className="tm2-cell shares filled" onClick={() => onSharesCellClick(r.ticker)}
                        title={`${fmtQty(r.quantity)} shares · avg ${fmtUSD2(r.avg_cost)} — click to sell`}>
                      <div className="qty">{fmtQty(r.quantity)}</div>
                      <div className="sub">@ {fmtUSD2(r.avg_cost)}</div>
                    </td>
                  ) : <td className="tm2-cell shares empty" aria-hidden />}

                  {/* Options-open slots */}
                  {Array.from({ length: OPEN_SLOTS }, (_, i) => {
                    const slot = e.openSlots[i];
                    if (!slot) return <td key={`o${i}`} className="tm2-cell open empty" aria-hidden />;
                    const pos = slot.signedPremium >= 0;
                    const cls = `tm2-cell open filled tone-${slot.state.tone} ${pos ? "pos" : "neg"}`;
                    const needsResolve = slot.state.tone === "expired" || slot.state.tone === "today";
                    return (
                      <td key={`o${i}`} className={cls}
                          onClick={() => needsResolve ? onResolveCellClick(r.ticker, slot.open) : onOpenSlotClick(r.ticker)}
                          title={`${slot.open.direction} ${slot.open.option_type} ${slot.open.contracts}× $${slot.open.strike} · expires ${slot.open.expiry} · ${slot.state.label}`}>
                        <div className="amt">{signedCompact(slot.signedPremium)}</div>
                        <div className="tag"><span className="dot" /> {slot.state.label}</div>
                      </td>
                    );
                  })}

                  {/* Closed slots */}
                  {Array.from({ length: CLOSED_SLOTS }, (_, i) => {
                    const slot = e.closedSlots[i];
                    if (!slot) return <td key={`c${i}`} className="tm2-cell closed empty" aria-hidden />;
                    const pos = slot.amount >= 0;
                    const cls = `tm2-cell closed filled tone-${slot.state.tone} ${pos ? "pos" : "neg"}`;
                    return (
                      <td key={`c${i}`} className={cls} title={slot.detail}>
                        <div className="amt">{signedCompact(slot.amount)}</div>
                        <div className="tag"><span className="dot" /> {slot.state.label}</div>
                      </td>
                    );
                  })}

                  {/* Realized */}
                  <td className={"tm2-realized " + (realized > 0 ? "pos" : realized < 0 ? "neg" : "neut")}>
                    <div className="amt">
                      {realized === 0 ? <span style={{ color: "var(--fg5)" }}>—</span> : fmtSignedUSD(realized)}
                    </div>
                    {e.basis > 0 && (
                      <div className="sub">
                        {pct >= 0 ? "+" : "−"}{Math.round(Math.abs(pct))}% OF {fmtCompact(e.basis)}
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
            {visibleRows.length === 0 && (
              <tr>
                <td colSpan={3 + OPEN_SLOTS + CLOSED_SLOTS} style={{ textAlign: "center", padding: 32, color: "var(--fg3)" }}>
                  No trades in this window.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
