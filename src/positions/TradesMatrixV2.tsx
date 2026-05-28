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
import { AnimatedNumber } from "@/sunnyfi/lib/animation";

/**
 * Trades matrix — editorial (tm-*) reskin of TradesLogMatrix.
 *
 * Renders inside the `.dash` design world (positions-v2.css). Same data
 * decomposition as the legacy gl-* matrix, but a fixed-column layout:
 *
 *   Position | shares (1) | options open (2-5) | closed (6-8) | Realized
 *
 * The timeframe pills (12w/26w/52w/104w) act as a lookback window on the
 * CLOSED zone — live opens always show, closed entries only appear if their
 * close date falls inside the window. The Realized total always reflects the
 * full per-ticker realized P&L regardless of window.
 *
 * Click routing (preserved from the legacy matrix):
 *   • shares cell        → onSharesCellClick(ticker)        — sell shares
 *   • empty options slot → onOpenSlotClick(ticker)          — log new open
 *   • live  options slot → onOpenSlotClick(ticker)          — close / edit
 *   • expired option     → onResolveCellClick(ticker, open) — resolve flow
 *   • closed cells       — info only (no-op)
 */

const OPTIONS_OPEN_COLS = 4; // live option slots (cols 2-5)
const CLOSED_COLS = 3; // closed slots (cols 6-8)

const WEEK_OPTIONS = [12, 26, 52, 104] as const;
type Weeks = (typeof WEEK_OPTIONS)[number];
const LS_TRADES_WEEKS = "np:tradesWeeks";
function readWeeksLS(): Weeks {
  if (typeof window === "undefined") return 52;
  const v = parseInt(window.localStorage.getItem(LS_TRADES_WEEKS) ?? "", 10);
  return (WEEK_OPTIONS as readonly number[]).includes(v) ? (v as Weeks) : 52;
}

const todayIso = (): string => new Date().toISOString().slice(0, 10);

function daysFromToday(iso: string, todayIsoStr: string): number {
  const a = new Date(todayIsoStr + "T00:00:00Z").getTime();
  const b = new Date(iso + "T00:00:00Z").getTime();
  return Math.round((b - a) / 86400000);
}

function liveStateLabel(
  open: OptionTrade,
  todayIsoStr: string,
): { label: string; tone: "expired" | "urgent" | "open"; title: string } {
  const d = daysFromToday(open.expiry, todayIsoStr);
  const niceDate = new Date(open.expiry + "T00:00:00Z").toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
  if (d < 0) return { label: "expired", tone: "expired", title: `expired ${niceDate} (${-d}d ago)` };
  if (d === 0) return { label: "today", tone: "urgent", title: `expires today · ${niceDate}` };
  if (d === 1) return { label: "tomorrow", tone: "urgent", title: `expires tomorrow · ${niceDate}` };
  if (d <= 7) return { label: `in ${d}d`, tone: "urgent", title: `expires in ${d} days · ${niceDate}` };
  return { label: "open", tone: "open", title: `expires ${niceDate} · ${d}d out` };
}

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  realizedByTicker: Map<string, number>;
  shareSellsByTicker: Map<string, ShareSell[]>;
  onTickerClick: (ticker: string) => void;
  onSharesCellClick: (ticker: string) => void;
  onOpenSlotClick: (ticker: string) => void;
  onResolveCellClick: (ticker: string, open: OptionTrade) => void;
}

type ClosedEntry =
  | { kind: "live-overflow"; open: OptionTrade; sortDate: string }
  | { kind: "option-closed"; open: OptionTrade; closes: OptionTrade[]; sortDate: string }
  | { kind: "share-sell"; sell: ShareSell; sortDate: string };

export function TradesMatrixV2({
  rows,
  tradesByTicker,
  realizedByTicker,
  shareSellsByTicker,
  onTickerClick,
  onSharesCellClick,
  onOpenSlotClick,
  onResolveCellClick,
}: Props) {
  const [weeks, setWeeksState] = useState<Weeks>(() => readWeeksLS());
  const setWeeks = (w: Weeks) => {
    setWeeksState(w);
    try {
      window.localStorage.setItem(LS_TRADES_WEEKS, String(w));
    } catch {
      /* private mode */
    }
  };
  const today = todayIso();
  const windowStart = useMemo(() => {
    const d = new Date();
    d.setDate(d.getDate() - weeks * 7);
    return d.toISOString().slice(0, 10);
  }, [weeks]);

  const isProtective = (t: OptionTrade) => t.option_type === "put" && t.direction === "long";

  // Realized for a closed pair / signed cash flow for a live open.
  const slotValueForOpen = useMemo(() => {
    const closesByOpen = new Map<string, OptionTrade[]>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action !== "close" || !t.closes_trade_id) continue;
        const arr = closesByOpen.get(t.closes_trade_id) ?? [];
        arr.push(t);
        closesByOpen.set(t.closes_trade_id, arr);
      }
    }
    return (open: OptionTrade): number => {
      const closes = closesByOpen.get(open.id) ?? [];
      if (closes.length > 0) return closes.reduce((s, c) => s + closeRealizedPL(c, open), 0);
      const notional = open.contracts * 100 * open.premium;
      return open.direction === "short" ? notional : -notional;
    };
  }, [tradesByTicker]);

  // Premium still outlaid on open long legs — denominator for "% of $X".
  const openPaidByTicker = useMemo(() => {
    const m = new Map<string, number>();
    for (const [ticker, list] of tradesByTicker) {
      const closedQtyByOpen = new Map<string, number>();
      for (const t of list) {
        if (t.action === "close" && t.closes_trade_id) {
          closedQtyByOpen.set(t.closes_trade_id, (closedQtyByOpen.get(t.closes_trade_id) ?? 0) + t.contracts);
        }
      }
      let paid = 0;
      for (const t of list) {
        if (t.action !== "open" || t.direction !== "long") continue;
        const stillOpen = t.contracts - (closedQtyByOpen.get(t.id) ?? 0);
        if (stillOpen <= 0) continue;
        paid += stillOpen * 100 * t.premium;
      }
      m.set(ticker, paid);
    }
    return m;
  }, [tradesByTicker]);

  const isEffectivelyClosed = (r: PositionComputed): boolean =>
    r.status === "closed" || (r.quantity === 0 && (r.live_options?.length ?? 0) === 0);

  function decomposeRow(r: PositionComputed): { liveOpens: OptionTrade[]; closedEntries: ClosedEntry[] } {
    const trades = tradesByTicker.get(r.ticker) ?? [];
    const sells = shareSellsByTicker.get(r.ticker) ?? [];

    const closesByOpen = new Map<string, OptionTrade[]>();
    for (const t of trades) {
      if (t.action !== "close" || !t.closes_trade_id) continue;
      const arr = closesByOpen.get(t.closes_trade_id) ?? [];
      arr.push(t);
      closesByOpen.set(t.closes_trade_id, arr);
    }
    const isFullyClosed = (open: OptionTrade): boolean =>
      (closesByOpen.get(open.id) ?? []).reduce((s, c) => s + c.contracts, 0) >= open.contracts;
    const mostRecentCloseDate = (open: OptionTrade): string => {
      const closes = closesByOpen.get(open.id) ?? [];
      if (closes.length === 0) return "";
      return closes.map((c) => c.trade_date).sort().reverse()[0];
    };

    const allOpens = trades.filter((t) => t.action === "open");
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

    const liveOverflow: ClosedEntry[] = liveOpens
      .slice(OPTIONS_OPEN_COLS)
      .map((open) => ({ kind: "live-overflow" as const, open, sortDate: open.trade_date }));
    const closedOptionEntries: ClosedEntry[] = closedOpens.map((open) => ({
      kind: "option-closed" as const,
      open,
      closes: closesByOpen.get(open.id) ?? [],
      sortDate: mostRecentCloseDate(open) || open.trade_date,
    }));
    const shareSellEntries: ClosedEntry[] = sells.map((sell) => ({
      kind: "share-sell" as const,
      sell,
      sortDate: sell.trade_date,
    }));

    const merged = [...liveOverflow, ...closedOptionEntries, ...shareSellEntries]
      .filter((e) => e.kind === "live-overflow" || e.sortDate >= windowStart)
      .sort((a, b) => b.sortDate.localeCompare(a.sortDate));

    return { liveOpens: liveOpens.slice(0, OPTIONS_OPEN_COLS), closedEntries: merged.slice(0, CLOSED_COLS) };
  }

  // Sort: active first (by realized desc), effectively-closed sink to bottom.
  const sorted = useMemo(
    () =>
      [...rows].sort((a, b) => {
        const aC = isEffectivelyClosed(a) ? 1 : 0;
        const bC = isEffectivelyClosed(b) ? 1 : 0;
        if (aC !== bC) return aC - bC;
        return (realizedByTicker.get(b.ticker) ?? 0) - (realizedByTicker.get(a.ticker) ?? 0);
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rows, realizedByTicker],
  );

  // Footer column totals.
  const { sharesBasis, liveCols, closedCols } = useMemo(() => {
    let sharesBasis = 0;
    const liveCols = Array.from({ length: OPTIONS_OPEN_COLS }, () => 0);
    const closedCols = Array.from({ length: CLOSED_COLS }, () => 0);
    for (const r of sorted) {
      sharesBasis += r.quantity * r.avg_cost;
      const { liveOpens, closedEntries } = decomposeRow(r);
      liveOpens.forEach((open, s) => {
        if (s >= OPTIONS_OPEN_COLS) return;
        liveCols[s] += isProtective(open) ? -(open.contracts * 100 * open.premium) : slotValueForOpen(open);
      });
      closedEntries.forEach((e, s) => {
        if (s >= CLOSED_COLS) return;
        if (e.kind === "option-closed") closedCols[s] += e.closes.reduce((acc, c) => acc + closeRealizedPL(c, e.open), 0);
        else if (e.kind === "live-overflow") closedCols[s] += slotValueForOpen(e.open);
        else closedCols[s] += e.sell.realized_pl;
      });
    }
    return { sharesBasis, liveCols, closedCols };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sorted, tradesByTicker, shareSellsByTicker, weeks, slotValueForOpen]);

  const grandOpenPaid = useMemo(() => Array.from(openPaidByTicker.values()).reduce((s, v) => s + v, 0), [openPaidByTicker]);
  const grandRealized = useMemo(
    () => sorted.reduce((s, r) => s + (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0), 0),
    [sorted, realizedByTicker],
  );
  const tickerCount = sorted.filter((r) => (tradesByTicker.get(r.ticker)?.length ?? 0) > 0 || (shareSellsByTicker.get(r.ticker)?.length ?? 0) > 0).length;
  const tradeCount = useMemo(
    () =>
      sorted.reduce(
        (s, r) => s + (tradesByTicker.get(r.ticker)?.length ?? 0) + (shareSellsByTicker.get(r.ticker)?.length ?? 0),
        0,
      ),
    [sorted, tradesByTicker, shareSellsByTicker],
  );

  const dotClass = (open: OptionTrade, neg: boolean): string =>
    "glyph-dot" + (open.option_type === "put" ? " put" : "") + (neg ? " neg" : "");

  const amtCls = (v: number) => (v < 0 ? "neg" : v > 0 ? "pos" : "neut");
  const amtStr = (v: number) => (v >= 0 ? fmtCompact(v) : "−" + fmtCompact(Math.abs(v)));

  return (
    <div className="tm-wrap">
      <div className="tm-tools">
        <span className="label">
          {tickerCount} tickers · {tradeCount} trades · {weeks}w
        </span>
        <div className="tf">
          {WEEK_OPTIONS.map((w) => (
            <span
              key={w}
              className={"pill" + (weeks === w ? "" : " muted")}
              onClick={() => setWeeks(w)}
              style={{ cursor: "pointer" }}
            >
              {w}w
            </span>
          ))}
        </div>
      </div>

      <div className="tm-scroll">
        <table className="tm-table">
          <thead>
            <tr>
              <th className="pos">Position</th>
              <th className="col shares">
                <span className="idx">1</span>
                <span className="sub">shares open</span>
              </th>
              {Array.from({ length: OPTIONS_OPEN_COLS }, (_, i) => (
                <th key={`l${i}`} className="col live">
                  <span className="idx">{i + 2}</span>
                  <span className="sub">options open</span>
                </th>
              ))}
              {Array.from({ length: CLOSED_COLS }, (_, i) => (
                <th key={`c${i}`} className="col closed">
                  <span className="idx">{i + 2 + OPTIONS_OPEN_COLS}</span>
                  <span className="sub">closed</span>
                </th>
              ))}
              <th className="tot">Realized</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const { liveOpens, closedEntries } = decomposeRow(r);
              const realized = (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0);
              const openPaid = openPaidByTicker.get(r.ticker) ?? 0;
              const hasShares = r.quantity > 0;
              return (
                <tr key={r.ticker} className={isEffectivelyClosed(r) ? "tm-row-closed" : ""}>
                  <td>
                    <div className="tm-pos">
                      <span className="t" onClick={() => onTickerClick(r.ticker)}>
                        {r.ticker}
                      </span>
                      <span className="sub">
                        {r.sector}
                        {liveOpens.length > 0 ? (
                          <>
                            {" · "}
                            <span className="live">{liveOpens.length} open</span>
                          </>
                        ) : null}
                      </span>
                    </div>
                  </td>

                  {/* shares */}
                  {hasShares ? (
                    <td
                      className="tm-cell zone-shares filled"
                      onClick={() => onSharesCellClick(r.ticker)}
                      title={`${fmtQty(r.quantity)} shares · avg ${fmtUSD2(r.avg_cost)} — click to sell shares`}
                    >
                      <div className="amt neut">{fmtQty(r.quantity)}</div>
                      <div className="chips">
                        <span className="state open">@ {fmtUSD2(r.avg_cost)}</span>
                      </div>
                    </td>
                  ) : (
                    <td className="tm-cell zone-shares empty">
                      <span className="em-dash">—</span>
                    </td>
                  )}

                  {/* live option slots */}
                  {Array.from({ length: OPTIONS_OPEN_COLS }, (_, s) => {
                    const open = liveOpens[s];
                    if (!open) {
                      return (
                        <td
                          key={`l${s}`}
                          className="tm-cell zone-live empty"
                          onClick={() => onOpenSlotClick(r.ticker)}
                          title="tap to open a new position"
                        >
                          <span className="plus">+</span>
                        </td>
                      );
                    }
                    const expired = open.expiry < today;
                    const needsResolve = expired || open.expiry === today;
                    const signed = slotValueForOpen(open);
                    const st = liveStateLabel(open, today);
                    return (
                      <td
                        key={`l${s}`}
                        className={"tm-cell zone-live filled" + (expired ? " expired" : st.tone === "urgent" ? " urgent" : "")}
                        onClick={() => (needsResolve ? onResolveCellClick(r.ticker, open) : onOpenSlotClick(r.ticker))}
                        title={`${open.direction} ${open.option_type} ${open.contracts}× $${open.strike} · opened ${open.trade_date} · ${st.title} · ${fmtUSD(signed)}`}
                      >
                        <div className={"amt " + amtCls(signed)}>{amtStr(signed)}</div>
                        <div className="chips">
                          <span className={dotClass(open, signed < 0)} />
                          <span className={"state " + st.tone}>{st.label}</span>
                        </div>
                      </td>
                    );
                  })}

                  {/* closed slots */}
                  {Array.from({ length: CLOSED_COLS }, (_, s) => {
                    const e = closedEntries[s];
                    if (!e) {
                      return (
                        <td key={`c${s}`} className="tm-cell zone-closed empty">
                          <span className="em-dash">—</span>
                        </td>
                      );
                    }
                    if (e.kind === "share-sell") {
                      const v = e.sell.realized_pl;
                      return (
                        <td
                          key={`c${s}`}
                          className="tm-cell zone-closed filled share-sell"
                          title={`Sold ${fmtQty(e.sell.quantity)} sh @ ${fmtUSD2(e.sell.price)} · ${e.sell.trade_date} · ${e.sell.source === "assignment" ? "assignment" : "manual"} · realized ${fmtUSD(v)}`}
                        >
                          <div className={"amt " + amtCls(v)}>{amtStr(v)}</div>
                          <div className="chips">
                            <span className="glyph-dot share" />
                            <span className="state closed">{e.sell.source === "assignment" ? "assigned" : "sold"}</span>
                          </div>
                        </td>
                      );
                    }
                    if (e.kind === "live-overflow") {
                      const open = e.open;
                      const expired = open.expiry < today;
                      const needsResolve = expired || open.expiry === today;
                      const signed = slotValueForOpen(open);
                      const st = liveStateLabel(open, today);
                      return (
                        <td
                          key={`c${s}`}
                          className={"tm-cell zone-closed filled" + (expired ? " expired" : st.tone === "urgent" ? " urgent" : "")}
                          onClick={() => (needsResolve ? onResolveCellClick(r.ticker, open) : onOpenSlotClick(r.ticker))}
                          title={`${open.direction} ${open.option_type} ${open.contracts}× $${open.strike} · opened ${open.trade_date} · ${st.title} (overflow)`}
                        >
                          <div className={"amt " + amtCls(signed)}>{amtStr(signed)}</div>
                          <div className="chips">
                            <span className={dotClass(open, false)} />
                            <span className={"state " + st.tone}>{st.label}</span>
                          </div>
                        </td>
                      );
                    }
                    // option-closed
                    const open = e.open;
                    const closedQty = e.closes.reduce((s2, c) => s2 + c.contracts, 0);
                    const fully = closedQty >= open.contracts;
                    const partial = e.closes.length > 0 && !fully;
                    const v = e.closes.reduce((s2, c) => s2 + closeRealizedPL(c, open), 0);
                    const stateLabel = fully ? "closed" : partial ? "partial" : "open";
                    return (
                      <td
                        key={`c${s}`}
                        className="tm-cell zone-closed filled"
                        title={`${open.direction} ${open.option_type} ${open.contracts}× $${open.strike} · opened ${open.trade_date} · ${stateLabel} · ${fmtUSD(v)}`}
                      >
                        <div className={"amt " + amtCls(v)}>{amtStr(v)}</div>
                        <div className="chips">
                          <span className={dotClass(open, v < 0)} />
                          <span className={"state closed"}>{stateLabel}</span>
                        </div>
                      </td>
                    );
                  })}

                  <td className="tm-tot">
                    <div className={"amt " + (realized < 0 ? "neg" : realized > 0 ? "pos" : "")}>
                      {realized === 0 ? <span style={{ color: "var(--fg5)" }}>—</span> : amtStr(realized)}
                    </div>
                    {openPaid > 0 && (
                      <div className="sub">
                        {realized >= 0 ? "+" : ""}
                        {((realized / openPaid) * 100).toFixed(0)}% of {fmtCompact(openPaid)}
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
            {sorted.length === 0 && (
              <tr>
                <td colSpan={2 + OPTIONS_OPEN_COLS + CLOSED_COLS + 1} style={{ textAlign: "center", padding: 32, color: "var(--fg3)" }}>
                  No positions yet
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr>
              <td>
                <div className="tm-foot-l">
                  <div className="t">Total</div>
                  <div className="sub">{tradeCount} trades · realized + open</div>
                </div>
              </td>
              <td className="tm-cell zone-shares filled">
                <div className="amt neut">{fmtCompact(sharesBasis)}</div>
                <div className="chips">
                  <span className="state">cost basis</span>
                </div>
              </td>
              {liveCols.map((v, i) =>
                v === 0 ? (
                  <td key={`fl${i}`} className="tm-cell zone-live empty">
                    <span className="em-dash">—</span>
                  </td>
                ) : (
                  <td key={`fl${i}`} className="tm-cell zone-live filled">
                    <div className={"amt " + amtCls(v)}>{amtStr(v)}</div>
                  </td>
                ),
              )}
              {closedCols.map((v, i) =>
                v === 0 ? (
                  <td key={`fc${i}`} className="tm-cell zone-closed empty">
                    <span className="em-dash">—</span>
                  </td>
                ) : (
                  <td key={`fc${i}`} className="tm-cell zone-closed filled">
                    <div className={"amt " + amtCls(v)}>{amtStr(v)}</div>
                  </td>
                ),
              )}
              <td className="tm-tot tm-foot-tot">
                <div className={"amt " + (grandRealized < 0 ? "neg" : "pos")}>
                  <AnimatedNumber
                    value={grandRealized}
                    duration={1400}
                    format={(n) => (n >= 0 ? fmtUSD(n) : "−" + fmtUSD(Math.abs(n)))}
                  />
                </div>
                {grandOpenPaid > 0 && (
                  <div className="sub">
                    {((grandRealized / grandOpenPaid) * 100).toFixed(0)}% of {fmtCompact(grandOpenPaid)}
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
