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
 * Trades matrix — Open / Closed, grouped by what you DID (sold vs bought),
 * not by instrument. "Collected" = premium you sold (calls or puts);
 * "Paid" = premium you bought (protective puts, bought calls). Each cell is
 * tagged Call / Put. This keeps income legs together and protection legs
 * together regardless of type.
 *
 *   Open   — live legs: Position | Shares | Collected | Paid | Net premium.
 *            An open leg is shown as a premium MAGNITUDE (no +/− — it's a
 *            position, not a P&L): collected = neon, paid = amber.
 *   Closed — realized history in the timeframe window: Collected | Paid |
 *            Assigned | Realized. Closed cells show realized P&L (a real
 *            gain/loss, so signed).
 *
 * Each group grows to fit the busiest ticker (cap 8); the Open view keeps one
 * trailing empty "+" slot per group as an always-present "add a leg" button.
 *
 * Click routing (open): shares → onSharesCellClick; empty "+" → onOpenSlotClick
 * (Open tab); live leg → onOpenSlotClick (close/edit); expired → onResolveCellClick;
 * ticker → onTickerClick. Closed cells are info-only.
 */

const GROUP_CAP = 8;
const ASSIGN_CAP = 2;

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
  if (d === 1) return { label: "tmrw", tone: "urgent", title: `expires tomorrow · ${niceDate}` };
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
  onOpenSlotClick: (ticker: string, mode?: "open" | "close") => void;
  onResolveCellClick: (ticker: string, open: OptionTrade) => void;
}

interface ClosedLeg {
  open: OptionTrade;
  closes: OptionTrade[];
  realized: number;
  sortDate: string;
}

interface Decomposed {
  liveSold: OptionTrade[];
  livePaid: OptionTrade[];
  closedSold: ClosedLeg[];
  closedPaid: ClosedLeg[];
  assigned: ShareSell[];
  netPremium: number;
  hasShares: boolean;
}

type View = "open" | "closed";
type Group = "sold" | "paid";

const amtCls = (v: number) => (v < 0 ? "neg" : v > 0 ? "pos" : "neut");
const amtStr = (v: number) => (v >= 0 ? fmtCompact(v) : "−" + fmtCompact(Math.abs(v)));
const typeTag = (t: OptionTrade) => (t.option_type === "call" ? "call" : "put");

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
  const [view, setView] = useState<View>("open");
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

  // Signed cash flow for a live open (collected +, paid −) — used only for the
  // net-premium roll-up; cells themselves render magnitudes.
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

  const decompose = useMemo(() => {
    return (r: PositionComputed): Decomposed => {
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
        const cs = closesByOpen.get(open.id) ?? [];
        return cs.length ? cs.map((c) => c.trade_date).sort().reverse()[0] : open.trade_date;
      };

      const allOpens = trades.filter((t) => t.action === "open");
      const byExpiry = (a: OptionTrade, b: OptionTrade) => a.expiry.localeCompare(b.expiry);

      const live = allOpens.filter((t) => !isFullyClosed(t)).sort(byExpiry);
      const liveSold = live.filter((t) => t.direction === "short");
      const livePaid = live
        .filter((t) => t.direction === "long")
        .sort((a, b) => {
          const ap = isProtective(a) ? 0 : 1;
          const bp = isProtective(b) ? 0 : 1;
          return ap !== bp ? ap - bp : byExpiry(a, b);
        });

      const closedOpens = allOpens.filter(isFullyClosed);
      const toLeg = (open: OptionTrade): ClosedLeg => {
        const closes = closesByOpen.get(open.id) ?? [];
        return {
          open,
          closes,
          realized: closes.reduce((s, c) => s + closeRealizedPL(c, open), 0),
          sortDate: mostRecentCloseDate(open),
        };
      };
      const bySortDesc = (a: ClosedLeg, b: ClosedLeg) => b.sortDate.localeCompare(a.sortDate);
      // All-time closed history; windowing applied at render so columns stay stable.
      const closedSold = closedOpens.filter((t) => t.direction === "short").map(toLeg).sort(bySortDesc);
      const closedPaid = closedOpens.filter((t) => t.direction === "long").map(toLeg).sort(bySortDesc);
      const assigned = [...sells].sort((a, b) => b.trade_date.localeCompare(a.trade_date));

      const netPremium = live.reduce((s, t) => s + slotValueForOpen(t), 0);

      return { liveSold, livePaid, closedSold, closedPaid, assigned, netPremium, hasShares: r.quantity > 0 };
    };
  }, [tradesByTicker, shareSellsByTicker, slotValueForOpen]);

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

  const { viewRows, soldCols, paidCols, assignCols } = useMemo(() => {
    const inWindow = (date: string) => date >= windowStart;
    let maxSold = 1;
    let maxPaid = 1;
    let maxAssign = 0;
    const kept: Array<{
      r: PositionComputed;
      sold: OptionTrade[] | ClosedLeg[];
      paid: OptionTrade[] | ClosedLeg[];
      assigned: ShareSell[];
      netPremium: number;
      hasShares: boolean;
    }> = [];
    for (const r of sorted) {
      const d = decompose(r);
      if (view === "open") {
        maxSold = Math.max(maxSold, d.liveSold.length);
        maxPaid = Math.max(maxPaid, d.livePaid.length);
        if (d.liveSold.length + d.livePaid.length + (d.hasShares ? 1 : 0) > 0)
          kept.push({ r, sold: d.liveSold, paid: d.livePaid, assigned: [], netPremium: d.netPremium, hasShares: d.hasShares });
      } else {
        maxSold = Math.max(maxSold, d.closedSold.length);
        maxPaid = Math.max(maxPaid, d.closedPaid.length);
        maxAssign = Math.max(maxAssign, d.assigned.length);
        const sold = d.closedSold.filter((l) => inWindow(l.sortDate));
        const paid = d.closedPaid.filter((l) => inWindow(l.sortDate));
        const assigned = d.assigned.filter((s) => inWindow(s.trade_date));
        if (sold.length + paid.length + assigned.length > 0)
          kept.push({ r, sold, paid, assigned, netPremium: 0, hasShares: d.hasShares });
      }
    }
    // Open view reserves one trailing "+" add-leg slot per group.
    const pad = view === "open" ? 1 : 0;
    return {
      viewRows: kept,
      soldCols: Math.min(GROUP_CAP, maxSold + pad),
      paidCols: Math.min(GROUP_CAP, maxPaid + pad),
      assignCols: Math.min(ASSIGN_CAP, Math.max(view === "closed" ? 1 : 0, maxAssign)),
    };
  }, [sorted, decompose, view, windowStart]);

  const tickerCount = viewRows.length;
  const legCount = useMemo(
    () => viewRows.reduce((s, e) => s + e.sold.length + e.paid.length + e.assigned.length, 0),
    [viewRows],
  );
  const grandRealized = useMemo(
    () => sorted.reduce((s, r) => s + (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0), 0),
    [sorted, realizedByTicker],
  );
  const grandOpenPaid = useMemo(() => Array.from(openPaidByTicker.values()).reduce((s, v) => s + v, 0), [openPaidByTicker]);

  // ── Cell renderers ─────────────────────────────────────────────
  function liveCell(key: string, ticker: string, leg: OptionTrade | undefined, group: Group) {
    if (!leg) {
      return (
        <td key={key} className={`tm-cell zone-${group} empty`} onClick={() => onOpenSlotClick(ticker, "open")} title={`Add a ${group === "sold" ? "sell" : "buy"} leg`}>
          <span className="plus">+</span>
        </td>
      );
    }
    const expired = leg.expiry < today;
    const needsResolve = expired || leg.expiry === today;
    const premium = leg.contracts * 100 * leg.premium;
    const st = liveStateLabel(leg, today);
    return (
      <td
        key={key}
        className={`tm-cell zone-${group} filled` + (expired ? " expired" : st.tone === "urgent" ? " urgent" : "")}
        onClick={() => (needsResolve ? onResolveCellClick(ticker, leg) : onOpenSlotClick(ticker))}
        title={`${leg.direction} ${leg.option_type} ${leg.contracts}× $${leg.strike} · opened ${leg.trade_date} · ${st.title} · ${group === "sold" ? "collected" : "paid"} ${fmtUSD(premium)}`}
      >
        <div className={"amt " + (group === "sold" ? "tone-sold" : "tone-bgt")}>{fmtCompact(premium)}</div>
        <div className="chips">
          <span className="typechip">{typeTag(leg)}</span>
          <span className={"state " + st.tone}>{st.label}</span>
        </div>
      </td>
    );
  }

  function closedCell(key: string, leg: ClosedLeg | undefined, group: Group) {
    if (!leg) {
      return (
        <td key={key} className={`tm-cell zone-${group} empty`}>
          <span className="em-dash">—</span>
        </td>
      );
    }
    return (
      <td
        key={key}
        className={`tm-cell zone-${group} filled`}
        title={`${leg.open.direction} ${leg.open.option_type} ${leg.open.contracts}× $${leg.open.strike} · opened ${leg.open.trade_date} · closed ${leg.sortDate} · ${fmtUSD(leg.realized)}`}
      >
        <div className={"amt " + amtCls(leg.realized)}>{amtStr(leg.realized)}</div>
        <div className="chips">
          <span className="typechip">{typeTag(leg.open)}</span>
          <span className="state closed">closed</span>
        </div>
      </td>
    );
  }

  function assignedCell(key: string, sell: ShareSell | undefined) {
    if (!sell) {
      return (
        <td key={key} className="tm-cell zone-closed empty">
          <span className="em-dash">—</span>
        </td>
      );
    }
    const v = sell.realized_pl;
    return (
      <td
        key={key}
        className="tm-cell zone-closed filled share-sell"
        title={`Sold ${fmtQty(sell.quantity)} sh @ ${fmtUSD2(sell.price)} · ${sell.trade_date} · ${sell.source === "assignment" ? "assignment" : "manual"} · realized ${fmtUSD(v)}`}
      >
        <div className={"amt " + amtCls(v)}>{amtStr(v)}</div>
        <div className="chips">
          <span className="glyph-dot share" />
          <span className="state closed">{sell.source === "assignment" ? "assigned" : "sold"}</span>
        </div>
      </td>
    );
  }

  const range = (n: number) => Array.from({ length: n }, (_, i) => i);

  return (
    <div className="tm-wrap">
      <div className="tm-tools">
        <span className="label">
          {tickerCount} tickers · {legCount} {view === "open" ? "open legs" : "closed"}
          {view === "closed" ? ` · ${weeks}w` : ""}
        </span>
        <div className="tm-tools-right">
          <div className="tf tm-viewtoggle">
            <span className={"pill" + (view === "open" ? "" : " muted")} onClick={() => setView("open")} style={{ cursor: "pointer" }}>
              Open
            </span>
            <span className={"pill" + (view === "closed" ? "" : " muted")} onClick={() => setView("closed")} style={{ cursor: "pointer" }}>
              Closed
            </span>
          </div>
          {view === "closed" && (
            <div className="tf">
              {WEEK_OPTIONS.map((w) => (
                <span key={w} className={"pill" + (weeks === w ? "" : " muted")} onClick={() => setWeeks(w)} style={{ cursor: "pointer" }}>
                  {w}w
                </span>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="tm-scroll">
        <table className="tm-table grouped">
          {view === "open" ? (
            <thead>
              <tr>
                <th className="pos" rowSpan={2}>Position</th>
                <th className="col shares" rowSpan={2}>
                  <span className="idx">SH</span>
                  <span className="sub">shares open</span>
                </th>
                <th className="grp-h sold" colSpan={soldCols}>Collected · sold</th>
                <th className="grp-h paid" colSpan={paidCols}>Paid · bought</th>
                <th className="tot" rowSpan={2}>Net premium</th>
              </tr>
              <tr>
                {range(soldCols).map((i) => (
                  <th key={`hs${i}`} className="col sold sub2"><span className="sub">leg {i + 1}</span></th>
                ))}
                {range(paidCols).map((i) => (
                  <th key={`hp${i}`} className="col paid sub2"><span className="sub">leg {i + 1}</span></th>
                ))}
              </tr>
            </thead>
          ) : (
            <thead>
              <tr>
                <th className="pos" rowSpan={2}>Position</th>
                <th className="grp-h sold" colSpan={soldCols}>Collected closed</th>
                <th className="grp-h paid" colSpan={paidCols}>Paid closed</th>
                <th className="grp-h assign" colSpan={assignCols}>Assigned</th>
                <th className="tot" rowSpan={2}>Realized</th>
              </tr>
              <tr>
                {range(soldCols).map((i) => (
                  <th key={`hsc${i}`} className="col sold sub2"><span className="sub">leg {i + 1}</span></th>
                ))}
                {range(paidCols).map((i) => (
                  <th key={`hpc${i}`} className="col paid sub2"><span className="sub">leg {i + 1}</span></th>
                ))}
                {range(assignCols).map((i) => (
                  <th key={`ha${i}`} className="col closed sub2"><span className="sub">sale {i + 1}</span></th>
                ))}
              </tr>
            </thead>
          )}

          <tbody>
            {viewRows.map((e) => {
              const r = e.r;
              const realized = (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0);
              const openPaid = openPaidByTicker.get(r.ticker) ?? 0;
              const liveCount = e.sold.length + e.paid.length;
              return (
                <tr key={r.ticker} className={isEffectivelyClosed(r) ? "tm-row-closed" : ""}>
                  <td>
                    <div className="tm-pos">
                      <span className="t" onClick={() => onTickerClick(r.ticker)}>{r.ticker}</span>
                      <span className="sub">
                        {r.sector}
                        {view === "open" && liveCount > 0 ? (
                          <> · <span className="live">{liveCount} open</span></>
                        ) : null}
                      </span>
                    </div>
                  </td>

                  {view === "open" ? (
                    <>
                      {e.hasShares ? (
                        <td
                          className="tm-cell zone-shares filled"
                          onClick={() => onSharesCellClick(r.ticker)}
                          title={`${fmtQty(r.quantity)} shares · avg ${fmtUSD2(r.avg_cost)} — click to sell shares`}
                        >
                          <div className="amt neut">{fmtQty(r.quantity)}</div>
                          <div className="chips"><span className="state open">@ {fmtUSD2(r.avg_cost)}</span></div>
                        </td>
                      ) : (
                        <td className="tm-cell zone-shares empty"><span className="em-dash">—</span></td>
                      )}
                      {range(soldCols).map((i) => liveCell(`s${i}`, r.ticker, (e.sold as OptionTrade[])[i], "sold"))}
                      {range(paidCols).map((i) => liveCell(`p${i}`, r.ticker, (e.paid as OptionTrade[])[i], "paid"))}
                      <td className="tm-tot">
                        <div className="amt neut">{e.netPremium === 0 ? <span style={{ color: "var(--fg5)" }}>—</span> : fmtCompact(Math.abs(e.netPremium))}</div>
                        <div className="sub">{e.netPremium >= 0 ? "net collected" : "net paid"}</div>
                      </td>
                    </>
                  ) : (
                    <>
                      {range(soldCols).map((i) => closedCell(`sc${i}`, (e.sold as ClosedLeg[])[i], "sold"))}
                      {range(paidCols).map((i) => closedCell(`pc${i}`, (e.paid as ClosedLeg[])[i], "paid"))}
                      {range(assignCols).map((i) => assignedCell(`a${i}`, e.assigned[i]))}
                      <td className="tm-tot">
                        <div className={"amt " + (realized < 0 ? "neg" : realized > 0 ? "pos" : "")}>
                          {realized === 0 ? <span style={{ color: "var(--fg5)" }}>—</span> : amtStr(realized)}
                        </div>
                        {openPaid > 0 && (
                          <div className="sub">{realized >= 0 ? "+" : ""}{((realized / openPaid) * 100).toFixed(0)}% of {fmtCompact(openPaid)}</div>
                        )}
                      </td>
                    </>
                  )}
                </tr>
              );
            })}
            {viewRows.length === 0 && (
              <tr>
                <td colSpan={2 + soldCols + paidCols + assignCols + 1} style={{ textAlign: "center", padding: 32, color: "var(--fg3)" }}>
                  {view === "open" ? "No open legs" : "No closed trades in this window"}
                </td>
              </tr>
            )}
          </tbody>

          {view === "closed" && (
            <tfoot>
              <tr>
                <td>
                  <div className="tm-foot-l">
                    <div className="t">Total</div>
                    <div className="sub">{legCount} closed · realized</div>
                  </div>
                </td>
                <td colSpan={soldCols + paidCols + assignCols} />
                <td className="tm-tot tm-foot-tot">
                  <div className={"amt " + (grandRealized < 0 ? "neg" : "pos")}>
                    <AnimatedNumber value={grandRealized} duration={1400} format={(n) => (n >= 0 ? fmtUSD(n) : "−" + fmtUSD(Math.abs(n)))} />
                  </div>
                  {grandOpenPaid > 0 && <div className="sub">{((grandRealized / grandOpenPaid) * 100).toFixed(0)}% of {fmtCompact(grandOpenPaid)}</div>}
                </td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  );
}
