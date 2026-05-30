/**
 * Positions v2 — Navi editorial redesign body.
 *
 * Presentation-only: receives the portfolio + callbacks from
 * PositionsPage, which keeps the single source of truth for data
 * (usePositions) and the modal stack. Renders inside the `.dash` shell
 * so it shares the dashboard token + atom layer (dashboard.css) plus
 * the positions-specific blocks in positions-v2.css (both scoped under
 * `.dash`, no collision with the `.np-app` modal styling).
 *
 * Sections:
 *   §00 Portfolio hero        — total value + unrealized
 *   §01 Allocation            — treemap tiles + holdings rail / P&L waterfall
 *   §02 Put protection        — coverage bar vs target
 *   §03 Strategy buckets      — Income / Investment / Yield bars
 *   §04 Positions ledger      — grouped rows + signals · Trades · Calendar
 *   §05 Stock insights focus  — one focus card + up-next queue
 *   §06 Realized summary      — hairline rows + bars
 *
 * The Trades + Calendar ledger sub-views reuse the existing
 * TradesLogMatrix / ExpiryCalendar components (styled by positions.css
 * via the .np-app ancestor) so we keep their full live behaviour.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { TickerStrip, BrandBar } from "@/sunnyfi/dashboard/blocks";
import { Section, Spark, AnimatedBar } from "@/sunnyfi/dashboard/atoms";
import { MoneyCount, PctCount, useEntered } from "@/sunnyfi/lib/animation";
import { useNow, fmtBrandDate } from "@/sunnyfi/dashboard/time";
import {
  fmtUSD, fmtUSD2, fmtPct, chipsForSignals, closeRealizedPL,
  type PositionComputed, type LiveOption, type OptionTrade,
  type TickerSignals, type ShareSell, type DailyClose,
} from "./types";
import { TradesMatrixV2 } from "./TradesMatrixV2";
import { mountBand, type BandPosition, type BandOption } from "./positionBand";
import { useUnrealizedPL } from "./metrics/useUnrealizedPL";
import { useRealizedPL } from "./metrics/useRealizedPL";
import { useLiveLegs } from "./metrics/useLiveLegs";
import "@/sunnyfi/pages/dashboard.css";
import "./positions-v2.css";

type Bucket = "income" | "invest" | "yield";

export interface PortfolioLike {
  rows: PositionComputed[];
  total_market_value: number;
  // Note: Unrealized P&L is no longer read from this prop. The hero pulls
  // it from `useUnrealizedPL()` (atom layer: A1 − A2) so there's exactly
  // one definition of "unrealized" in the app.
}

export interface PositionsV2BodyProps {
  portfolio: PortfolioLike;
  liveByTicker: Map<string, LiveOption[]>;
  overlayByTicker: Map<string, Bucket>;
  signalsByTicker: Map<string, TickerSignals>;
  realizedByTicker: Map<string, number>;
  tradesByTicker: Map<string, OptionTrade[]>;
  shareSellsByTicker: Map<string, ShareSell[]>;
  dailyCloses: DailyClose[];
  onUpload: () => void;
  onRefresh: () => void;
  refreshing: boolean;
  onTickerClick: (ticker: string) => void;
  onSharesCellClick: (ticker: string) => void;
  onOpenSlotClick: (ticker: string, mode?: 'open' | 'close') => void;
  onResolveCellClick: (ticker: string, open: OptionTrade) => void;
  onDashboard: () => void;
  onStrategy: () => void;
}

const BUCKET_META: Record<Bucket, { name: string; dot: string }> = {
  income: { name: "INCOME", dot: "var(--neon)" },
  invest: { name: "INVESTMENT", dot: "var(--positive)" },
  yield:  { name: "YIELD", dot: "var(--warning)" },
};

/** Abbreviate long GICS sector names so the ledger's sector column
 *  fits on one line. Falls back to the raw value for anything we
 *  don't have a short form for. */
function shortSector(s: string | null | undefined): string {
  if (!s) return "—";
  const map: Record<string, string> = {
    "Communication Services": "Comm Svcs",
    "Consumer Discretionary": "Cons Disc",
    "Consumer Staples": "Staples",
    "Information Technology": "Tech",
    "Technology": "Tech",
    "Financials": "Financials",
    "Industrials": "Industrials",
    "Health Care": "Health Care",
    "Healthcare": "Health Care",
    "Real Estate": "Real Estate",
    "Materials": "Materials",
    "Energy": "Energy",
    "Utilities": "Utilities",
  };
  return map[s] ?? s;
}

// ─────────────────── Brand bar ───────────────────────────────────
function PositionsBrandBar({
  dateLabel, onRefresh, refreshing, onUpload,
}: {
  dateLabel: string;
  onRefresh: () => void; refreshing: boolean; onUpload: () => void;
}) {
  // Positions now lives in-app at /positions, so every nav link is a plain
  // in-app route change (same shell, no cross-domain reload).
  const navigate = useNavigate();
  return (
    <>
      <BrandBar
        routeLabel="Positions"
        active="positions"
        dateLabel={dateLabel}
        onLogo={() => navigate("/dashboard")}
        onPositions={() => navigate("/positions")}
        onIncome={() => navigate("/income")}
        onStrategy={() => navigate("/new-strategy")}
        onMath={() => navigate("/math")}
      />
      <div className="page-toolbar">
        <span style={{ marginRight: "auto" }} />
        <span className="pill muted" onClick={onRefresh} style={{ cursor: "pointer" }}>
          ↻ {refreshing ? "Refreshing…" : "Refresh prices"}
        </span>
        <span className="pill" onClick={onUpload} style={{ cursor: "pointer" }}>↑ Upload positions</span>
      </div>
    </>
  );
}

// ─────────────────── §00 Hero ────────────────────────────────────
function PositionsHero({ portfolio }: { portfolio: PortfolioLike }) {
  const open = portfolio.rows.filter((r) => r.status !== "closed" && r.quantity > 0);
  // SOT: A11 split by option_type via useLiveLegs (was inline loop over
  // liveByTicker counting legs by hand). Same numbers, one definition.
  const live = useLiveLegs();
  const calls = live.calls;
  const puts = live.puts;
  // SOT: A1 − A2 via the atom hook. Don't read total_pnl from props.
  const unr = useUnrealizedPL();
  const unrealized = unr.total;
  // SOT: A3 + A8 via the atom hook. Replaces the row-sum that used to
  // happen here (Σ row.realized_pl + Σ row.realized_stock_pl).
  const realized = useRealizedPL().total;
  const totalGain = unrealized + realized;
  const sign = (v: number) => (v >= 0 ? "+" : "-");
  const tone = (v: number) => (v >= 0 ? "pos" : "neg");
  return (
    <div>
      <Section right="updated now · live">Portfolio</Section>
      <div className="pos-hero">
        <div>
          <div className="label" style={{ marginBottom: 14 }}>TOTAL VALUE</div>
          <div className="total" style={{ fontSize: 156 }}>
            <MoneyCount value={Math.round(portfolio.total_market_value)} duration={1500} />
          </div>
        </div>
        <div className="side">
          <div className="label">TOTAL P&amp;L · REALIZED + UNREALIZED</div>
          <div className={"unr-amt " + tone(totalGain)}>
            <MoneyCount value={Math.round(totalGain)} sign={sign(totalGain)} delay={150} />
          </div>
          <div className="hero-sub">
            <div>
              <div className="label">UNREALIZED</div>
              <div className={"hero-sub-amt " + tone(unrealized)}>
                <MoneyCount value={Math.round(unrealized)} sign={sign(unrealized)} delay={250} />
              </div>
              <div className={"hero-sub-pct " + tone(unrealized)}>
                <PctCount value={Math.abs(unr.totalPct)} sign={sign(unrealized)} delay={300} />
              </div>
            </div>
            <div>
              <div className="label">REALIZED</div>
              <div className={"hero-sub-amt " + tone(realized)}>
                <MoneyCount value={Math.round(realized)} sign={sign(realized)} delay={350} />
              </div>
              <div className="hero-sub-pct" style={{ color: "var(--fg3)" }}>booked</div>
            </div>
          </div>
          <div className="live">
            <span className="live-dot" /> {open.length} positions · {calls} calls · {puts} puts
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── §01 Allocation ──────────────────────────────
type AllocView = "stock" | "sector" | "strategy" | "pnl";

function AllocationBlock({ rows, overlayByTicker, onTickerClick }: {
  rows: PositionComputed[];
  overlayByTicker: Map<string, Bucket>;
  onTickerClick: (t: string) => void;
}) {
  const [view, setView] = useState<AllocView>("sector");
  const tabs: Array<[AllocView, string]> = [
    ["stock", "By stock"], ["sector", "By sector"], ["strategy", "By strategy"], ["pnl", "P&L by position"],
  ];
  const total = rows.reduce((s, r) => s + r.market_value, 0) || 1;

  // Build treemap tiles for the active view.
  const tiles = useMemo(() => {
    if (view === "pnl") return [];
    const buckets = new Map<string, number>();
    if (view === "sector") {
      for (const r of rows) buckets.set(r.sector, (buckets.get(r.sector) ?? 0) + r.market_value);
    } else if (view === "strategy") {
      for (const r of rows) {
        const b = overlayByTicker.get(r.ticker) ?? "unassigned";
        const name = b === "unassigned" ? "Unassigned" : BUCKET_META[b as Bucket].name;
        buckets.set(name, (buckets.get(name) ?? 0) + r.market_value);
      }
    } else {
      for (const r of rows) buckets.set(r.ticker, (buckets.get(r.ticker) ?? 0) + r.market_value);
    }
    const sorted = [...buckets.entries()].sort((a, b) => b[1] - a[1]);
    const top = sorted.slice(0, 5);
    const restSum = sorted.slice(5).reduce((s, [, v]) => s + v, 0);
    if (restSum > 0) top.push([`Other · ${sorted.length - 5}`, restSum]);
    return top.map(([name, mv], i) => ({
      name, mv,
      pct: (mv / total) * 100,
      cls: i === 0 ? "lead" : i === 1 ? "pos" : i === 3 ? "warn" : "",
      glyph: `#${i + 1}`,
    }));
  }, [view, rows, overlayByTicker, total]);

  // P&L waterfall data — bars now read from the atom layer
  // (useUnrealizedPL.byTicker, i.e. A1 − A2 per ticker). The full
  // PositionComputed row stays around so the rich hover tooltip
  // (sector, MV, avg cost, etc.) keeps working — only the headline
  // `pnl_dollar` is overridden by the canonical per-ticker value.
  const unrealized = useUnrealizedPL();
  const pnlData = useMemo(
    () => rows
      .map((r) => ({ ...r, pnl_dollar: unrealized.byTicker.get(r.ticker) ?? 0 }))
      .filter((r) => Math.abs(r.pnl_dollar) > 1)
      .sort((a, b) => b.pnl_dollar - a.pnl_dollar),
    [rows, unrealized.byTicker],
  );

  return (
    <div>
      <Section n="01" right={
        <span style={{ display: "inline-flex", gap: 6 }}>
          {tabs.map(([k, l]) => (
            <span key={k} className={"pill" + (view === k ? "" : " muted")} onClick={() => setView(k)} style={{ cursor: "pointer" }}>{l}</span>
          ))}
        </span>
      }>Allocation</Section>

      <div style={{ display: "grid", gridTemplateColumns: "2.4fr 1fr", gap: 40 }}>
        {view === "pnl"
          ? <PnLWaterfall data={pnlData} onTickerClick={onTickerClick} />
          : (
            <div className="treemap">
              {tiles.map((t, i) => (
                <div key={i} className={"tile " + t.cls} onClick={() => view === "stock" && onTickerClick(t.name)}>
                  <span className="glyph">{t.glyph}</span>
                  <div className="sector">{view === "sector" ? "SECTOR" : view === "strategy" ? "STRATEGY" : "TICKER"}</div>
                  <div className="name">{t.name}</div>
                  <div className="meta">{fmtUSD(t.mv)} · {t.pct.toFixed(1)}%</div>
                </div>
              ))}
            </div>
          )}
        <HoldingsRail rows={rows} total={total} onTickerClick={onTickerClick} />
      </div>
    </div>
  );
}

function HoldingsRail({ rows, total, onTickerClick }: {
  rows: PositionComputed[]; total: number; onTickerClick: (t: string) => void;
}) {
  const entered = useEntered(400);
  const sorted = [...rows].sort((a, b) => b.market_value - a.market_value);
  const top = sorted.slice(0, 6).map((r) => ({ t: r.ticker, pct: (r.market_value / total) * 100 }));
  const restPct = sorted.slice(6).reduce((s, r) => s + (r.market_value / total) * 100, 0);
  if (restPct > 0) top.push({ t: "OTHER", pct: restPct });
  const max = Math.max(...top.map((x) => x.pct), 1);
  return (
    <div className="holdings-rail">
      <div className="label" style={{ marginBottom: 14 }}>TOP HOLDINGS · {rows.length}</div>
      {top.map((r, i) => (
        <div key={r.t} className={"holdings-row" + (i === 0 ? " lead" : "")} onClick={() => r.t !== "OTHER" && onTickerClick(r.t)} style={{ cursor: r.t !== "OTHER" ? "pointer" : "default" }}>
          <span className="t">{r.t}</span>
          <div className="bar-wrap">
            <div className="bar-fill" style={{ width: entered ? `${(r.pct / max) * 100}%` : "0%", transition: `width 1s cubic-bezier(.16,1,.3,1) ${i * 60}ms` }} />
          </div>
          <span className="pct">{r.pct.toFixed(1)}%</span>
        </div>
      ))}
    </div>
  );
}

/** P&L-by-position waterfall — signed bars, sorted, with a hover tip. */
function PnLWaterfall({ data, onTickerClick }: {
  data: PositionComputed[]; onTickerClick: (t: string) => void;
}) {
  const entered = useEntered(300);
  const [hover, setHover] = useState<number | null>(null);
  const W = 760, H = 360, padL = 8, padR = 56, padT = 14, padB = 36;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const max = Math.max(1, ...data.map((d) => d.pnl_dollar));
  const min = Math.min(-1, ...data.map((d) => d.pnl_dollar));
  const range = (max - min) || 1;
  const zeroY = padT + (max / range) * innerH;
  const n = Math.max(1, data.length);
  const colW = innerW / n;
  const barW = colW * 0.62;
  const hovered = hover != null ? data[hover] : null;
  const hoverX = hover != null ? padL + colW * hover + colW / 2 : 0;
  const leftPct = (hoverX / W) * 100;
  const placeRight = leftPct < 50;
  const fmtSigned = (v: number) => (v < 0 ? "−$" : v > 0 ? "+$" : "$") + Math.abs(Math.round(v)).toLocaleString("en-US");

  return (
    <div style={{ position: "relative" }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: "block", overflow: "visible" }} onMouseLeave={() => setHover(null)}>
        {[max, max / 2, 0, min / 2, min].map((t, i) => {
          const y = padT + ((max - t) / range) * innerH;
          const isZero = Math.abs(t) < 1;
          return (
            <g key={i}>
              <line x1={padL} y1={y} x2={padL + innerW} y2={y} stroke={isZero ? "var(--fg3)" : "rgba(50,110,100,.18)"} strokeWidth={1} strokeDasharray={isZero ? "4 4" : ""} />
              <text x={W - padR + 12} y={y + 4} fontFamily="var(--mono)" fontSize="10" fill="var(--fg3)">
                {Math.abs(t) < 1 ? "0" : (t > 0 ? "+" : "−") + "$" + Math.abs(Math.round(t / 1000)) + "k"}
              </text>
            </g>
          );
        })}
        {data.map((d, i) => {
          const x = padL + colW * i + (colW - barW) / 2;
          const pos = d.pnl_dollar >= 0;
          const h = (Math.abs(d.pnl_dollar) / range) * innerH;
          const isHover = hover === i;
          const dim = hover != null && !isHover;
          return (
            <g key={d.ticker} onMouseEnter={() => setHover(i)} onClick={() => onTickerClick(d.ticker)} style={{ cursor: "pointer" }}>
              <rect x={padL + colW * i} y={padT} width={colW} height={innerH} fill="transparent" />
              <rect x={x} y={pos ? zeroY - h : zeroY} width={barW} height={Math.max(2, h)} rx="1"
                fill={pos ? "var(--neon)" : "var(--negative)"}
                opacity={entered ? (dim ? 0.25 : pos ? 1 : 0.88) : 0}
                style={{ transition: `opacity .25s var(--ease)`, pointerEvents: "none" }} />
              <text x={x + barW / 2} y={H - 14} textAnchor="middle" fontFamily="var(--mono)" fontSize="10"
                fill={isHover ? "var(--neon)" : pos ? "var(--fg2)" : "var(--fg3)"} opacity={dim ? 0.4 : 1}
                style={{ letterSpacing: "1px", textTransform: "uppercase", fontWeight: 600, pointerEvents: "none" }}>
                {d.ticker}
              </text>
            </g>
          );
        })}
      </svg>
      {hovered && (
        <div className="pnl-tip" style={{ left: placeRight ? `calc(${leftPct}% + 18px)` : "auto", right: placeRight ? "auto" : `calc(${100 - leftPct}% + 18px)`, top: "4%" }}>
          <div className="tip-head">
            <span className="tip-t">{hovered.ticker}</span>
            <span className="tip-sec">{hovered.sector}</span>
          </div>
          <div className="tip-hero">
            <span className={"tip-pnl " + (hovered.pnl_dollar >= 0 ? "pos" : "neg")}>{fmtSigned(hovered.pnl_dollar)}</span>
            <span className="tip-sub">unrealized p&amp;l</span>
          </div>
          <div className="tip-rows">
            <div className="tip-row"><span>P&amp;L %</span><span className={hovered.pnl_pct >= 0 ? "pos" : "neg"}>{fmtPct(hovered.pnl_pct)}</span></div>
            <div className="tip-row"><span>Overall P&amp;L</span><span className={hovered.overall_pl >= 0 ? "pos" : "neg"}>{fmtSigned(hovered.overall_pl)}</span></div>
          </div>
          <div className="tip-rows muted">
            <div className="tip-row"><span>Market value</span><span>{fmtUSD(hovered.market_value)}</span></div>
            <div className="tip-row"><span>% of book</span><span>{hovered.pct_portfolio.toFixed(1)}%</span></div>
            <div className="tip-row"><span>Avg cost</span><span>{fmtUSD(hovered.avg_cost)}</span></div>
            <div className="tip-row"><span>Net cost</span><span>{fmtUSD(hovered.effective_cost)}</span></div>
          </div>
        </div>
      )}
    </div>
  );
}

// ─────────────────── §02 Put protection ──────────────────────────
// "How much of the put bill have the calls paid for?"
//   • Put cost   = total premium PAID on long puts (gross, all-time)
//   • Call income= realized P&L from CLOSED call pairs
//   • Net cost   = put cost − call income (what's still out of pocket)
//   • Coverage % = call income ÷ put cost (how far the calls have
//                  covered the protection)
function ProtectionBlock({ tradesByTicker }: {
  rows: PositionComputed[]; tradesByTicker: Map<string, OptionTrade[]>;
}) {
  const entered = useEntered(300);
  const { coveredPct, putCost, callIncome, netCost } = useMemo(() => {
    let putCost = 0;
    let callIncome = 0;
    for (const [, list] of tradesByTicker) {
      // Index opens by id and tally closed contracts per open, so we count
      // only premium that's STILL outlaid — a put that's been bought back is
      // no longer a protection cost. This matches the Trades view's
      // "premium on still-open long legs" denominator.
      const byId = new Map<string, OptionTrade>();
      const closedQtyByOpen = new Map<string, number>();
      for (const t of list) {
        byId.set(t.id, t);
        if (t.action === "close" && t.closes_trade_id) {
          closedQtyByOpen.set(t.closes_trade_id, (closedQtyByOpen.get(t.closes_trade_id) ?? 0) + t.contracts);
        }
      }
      for (const t of list) {
        // Put cost — premium paid on the still-open portion of long puts.
        if (t.action === "open" && t.option_type === "put" && t.direction === "long") {
          const stillOpen = t.contracts - (closedQtyByOpen.get(t.id) ?? 0);
          if (stillOpen > 0) putCost += stillOpen * 100 * t.premium;
        }
        // Call income — realized P&L on closed CALL pairs.
        if (t.action === "close" && t.closes_trade_id) {
          const open = byId.get(t.closes_trade_id);
          if (open && open.option_type === "call") {
            callIncome += closeRealizedPL(t, open);
          }
        }
      }
    }
    const netCost = putCost - callIncome;
    const coveredPct = putCost > 0 ? Math.max(0, Math.min(100, (callIncome / putCost) * 100)) : 0;
    return { coveredPct, putCost, callIncome, netCost };
  }, [tradesByTicker]);

  const covered = netCost <= 0;     // calls have fully paid for the puts

  return (
    <div>
      <Section n="02" right="call income vs put cost">Put protection</Section>
      <div className="protection">
        <div>
          <div className="prot-bar-wrap">
            <div className="prot-bar-fill" style={{ width: entered ? `${coveredPct}%` : "0%" }} />
            <div className="prot-line" style={{ left: "100%" }}><div className="prot-line-label">break-even · 100%</div></div>
          </div>
          <div className="prot-meta">
            <span className="label">0%</span>
            <span className="label">{coveredPct.toFixed(0)}% of put cost covered by calls</span>
            <span className="label">100%</span>
          </div>
        </div>
        <div className="prot-right">
          <div className="label">{covered ? "SURPLUS" : "NET COST"}</div>
          <div className="hero num-mono" style={{ fontSize: 36, fontWeight: 700, marginTop: 4, color: covered ? "var(--positive)" : "var(--negative)" }}>
            <MoneyCount value={Math.round(Math.abs(netCost))} sign={covered ? "+" : "-"} delay={250} />
          </div>
          <div className="label" style={{ marginTop: 6 }}>
            {fmtUSD(callIncome)} calls · {fmtUSD(putCost)} puts
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── §03 Strategy buckets ────────────────────────
function StrategyBuckets({ rows, overlayByTicker, realizedByTicker }: {
  rows: PositionComputed[];
  overlayByTicker: Map<string, Bucket>;
  realizedByTicker: Map<string, number>;
}) {
  const entered = useEntered(300);
  // SOT: live-leg counts per ticker via useLiveLegs (A11). Replaces the
  // inline `liveByTicker.get(r.ticker)?.length ?? 0` count.
  const { byTicker: liveByTickerCount } = useLiveLegs();
  const buckets = useMemo(() => {
    const order: Bucket[] = ["income", "invest", "yield"];
    const acc: Record<Bucket, { mv: number; pnl: number; cost: number; count: number; live: number }> = {
      income: { mv: 0, pnl: 0, cost: 0, count: 0, live: 0 },
      invest: { mv: 0, pnl: 0, cost: 0, count: 0, live: 0 },
      yield:  { mv: 0, pnl: 0, cost: 0, count: 0, live: 0 },
    };
    for (const r of rows) {
      const b = overlayByTicker.get(r.ticker);
      if (!b || !(b in acc)) continue;
      acc[b].mv += r.market_value;
      acc[b].pnl += (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0);
      acc[b].cost += r.cost_basis;
      acc[b].count += 1;
      acc[b].live += liveByTickerCount.get(r.ticker) ?? 0;
    }
    const max = Math.max(1, ...order.map((b) => acc[b].mv));
    return order.map((b) => ({ key: b, ...acc[b], max }));
  }, [rows, overlayByTicker, realizedByTicker, liveByTickerCount]);

  return (
    <div>
      <Section n="03" right="3 buckets">Strategy</Section>
      {buckets.map((b, i) => {
        const meta = BUCKET_META[b.key];
        const pct = b.cost > 0 ? (b.pnl / b.cost) * 100 : 0;
        return (
          <div key={b.key} className="bucket-row">
            <div className="b-name">
              <div>
                <div style={{ display: "flex", alignItems: "center" }}>
                  <span className="b-dot" style={{ background: meta.dot, marginRight: 10 }} />
                  <span className="b-label">{meta.name}</span>
                </div>
                <div className="b-meta">{b.count} position{b.count === 1 ? "" : "s"} · live {b.live}</div>
              </div>
            </div>
            <div className="b-bar-wrap">
              <div className="b-bar-fill" style={{ width: entered ? `${(b.mv / b.max) * 100}%` : "0%", background: meta.dot, opacity: 0.35, transitionDelay: `${i * 120}ms` }} />
              <div className="b-bar-mv">{fmtUSD(b.mv)} MV</div>
            </div>
            <div className="b-right">
              <div className={"b-pnl " + (b.pnl >= 0 ? "pos" : "neg")}>
                <MoneyCount value={Math.round(Math.abs(b.pnl))} sign={b.pnl >= 0 ? "+" : "-"} delay={400 + i * 120} />
              </div>
              <div className="b-pct">realized · {pct >= 0 ? "+" : "−"}{Math.abs(pct).toFixed(1)}%</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ─────────────────── §04 Positions ledger ────────────────────────
type LedgerView = "positions" | "trades";

function PositionsLedger(props: PositionsV2BodyProps) {
  const { portfolio, overlayByTicker, signalsByTicker, realizedByTicker, liveByTicker, onTickerClick } = props;
  const [view, setView] = useState<LedgerView>("positions");
  // Outstanding short premium per ticker — A9 split by useLiveLegs.
  // Shown in the OUT column so each row reads "you've collected $X you
  // still owe the option holder on this name".
  const { shortPremByTicker } = useLiveLegs();
  const views: Array<[LedgerView, string]> = [["positions", "Positions"], ["trades", "Trades"]];

  const groups = useMemo(() => {
    const order: Bucket[] = ["income", "invest", "yield"];
    const map: Record<string, PositionComputed[]> = { income: [], invest: [], yield: [], unassigned: [] };
    for (const r of portfolio.rows) {
      if (r.status === "closed") continue;
      const b = overlayByTicker.get(r.ticker) ?? "unassigned";
      map[b].push(r);
    }
    const keys = [...order, "unassigned" as const];
    return keys.filter((k) => map[k].length > 0).map((k) => ({ key: k, rows: map[k].sort((a, b) => b.market_value - a.market_value) }));
  }, [portfolio.rows, overlayByTicker]);

  return (
    <div>
      <Section n="04" right={
        <span className="view-toggle">
          {views.map(([k, l]) => (
            <button key={k} className={"vt" + (view === k ? " on" : "")} onClick={() => setView(k)}>{l}</button>
          ))}
        </span>
      }>Positions ledger</Section>

      {view === "trades" && (
        <TradesMatrixV2
          rows={portfolio.rows}
          tradesByTicker={props.tradesByTicker}
          realizedByTicker={props.realizedByTicker}
          shareSellsByTicker={props.shareSellsByTicker}
          onTickerClick={onTickerClick}
          onSharesCellClick={props.onSharesCellClick}
          onOpenSlotClick={props.onOpenSlotClick}
          onResolveCellClick={props.onResolveCellClick}
        />
      )}
      {view === "positions" && (
        <>
          <div className="ledger-head">
            {["POSITION", "SECTOR", "PRICE · 1D", "QTY · AVG", "NET COST", "UNREALIZED", "REALIZED", "PREM OUT", "SIGNALS"].map((h) => (
              <span key={h} className="label" style={{ fontSize: 9 }}>{h}</span>
            ))}
          </div>
          {groups.map((g, gi) => {
            const meta = g.key === "unassigned" ? { name: "UNASSIGNED", dot: "var(--fg3)" } : BUCKET_META[g.key as Bucket];
            const mv = g.rows.reduce((s, r) => s + r.market_value, 0);
            const real = g.rows.reduce((s, r) => s + (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0), 0);
            return (
              <div key={g.key}>
                <div className="ledger-group">
                  <div><span className="g-dot" style={{ background: meta.dot }} /><span className="g-name">{meta.name}</span></div>
                  <span className="g-meta">{g.rows.length} position{g.rows.length === 1 ? "" : "s"}</span>
                  <span className="g-right">{fmtUSD(mv)} MV · <b>{real >= 0 ? "+" : "−"}{fmtUSD(Math.abs(real))}</b> realized</span>
                </div>
                {g.rows.map((r) => {
                  const sig = signalsByTicker.get(r.ticker);
                  const chips = sig ? chipsForSignals(sig).slice(0, 2) : [];
                  const ch1d = sig?.chg_5d_pct ?? null; // closest available daily proxy
                  // Realized = closed options + realized stock (full per-ticker realized).
                  const real1 = (realizedByTicker.get(r.ticker) ?? 0) + (r.realized_stock_pl ?? 0);
                  // Net cost = avg cost − realized P&L per share. Below avg = realized
                  // gains have paid the basis down; above = realized losses raised it.
                  const netCost = r.quantity > 0 ? r.avg_cost - real1 / r.quantity : r.avg_cost;
                  const netTone = netCost < r.avg_cost ? "pos" : netCost > r.avg_cost ? "neg" : "";
                  // Effectively closed: no shares left and no live options. Dim it
                  // so it reads as inactive without dropping out of the ledger.
                  const dim = r.quantity === 0 && (r.live_options?.length ?? 0) === 0;
                  return (
                    <div key={r.ticker} className={"ledger-row" + (dim ? " dim" : "")} onClick={() => onTickerClick(r.ticker)} style={{ cursor: "pointer" }}>
                      <span className="t">{r.ticker}</span>
                      <span className="sec" title={r.sector}>{shortSector(r.sector)}</span>
                      <span className="price">{r.current_price != null ? fmtUSD(r.current_price) : "—"}
                        {ch1d != null && <span className={"ch " + (ch1d >= 0 ? "pos" : "neg")}>{ch1d >= 0 ? "+" : ""}{ch1d.toFixed(1)}%</span>}
                      </span>
                      <span className="size">{r.quantity.toLocaleString()} sh<span className="sub2"> @ {fmtUSD2(r.avg_cost)}</span></span>
                      <span className={"netcost " + netTone}>{fmtUSD2(netCost)}</span>
                      <span className={"unr " + (r.pnl_dollar >= 0 ? "pos" : "neg")}>{r.pnl_dollar >= 0 ? "+" : "−"}{fmtUSD(Math.abs(r.pnl_dollar))}</span>
                      <span className="real">{real1 === 0 ? "—" : (real1 >= 0 ? "+" : "−") + fmtUSD(Math.abs(real1))}</span>
                      <span className="premout" title="Outstanding short-side premium — what you've collected and still owe (A9)">{
                        (shortPremByTicker.get(r.ticker) ?? 0) > 0
                          ? fmtUSD(shortPremByTicker.get(r.ticker) ?? 0)
                          : <span className="em">—</span>
                      }</span>
                      <span className="sigs">
                        {chips.map((c) => <span key={c.label} className={"chip " + (c.tone === "warn" ? "warn" : c.tone === "down" ? "neg" : c.tone === "up" ? "pos" : "")}>{c.label}</span>)}
                      </span>
                    </div>
                  );
                })}
              </div>
            );
          })}
        </>
      )}
    </div>
  );
}

// Map a live position + its option legs + daily closes into the Position
// Lens band data. Lots are empty until PL-B (share-lot recording); the
// expected-move band + real OI arrive in PL-C.
function positionToBand(r: PositionComputed, trades: OptionTrade[], dailyCloses: DailyClose[]): BandPosition {
  const current = r.current_price ?? r.avg_cost;
  const series = dailyCloses
    .filter((c) => c.ticker === r.ticker)
    .sort((a, b) => a.date.localeCompare(b.date));
  const prices = series.map((c) => c.close_price);
  let lo: number, hi: number;
  if (prices.length >= 2) {
    lo = Math.min(...prices, current); hi = Math.max(...prices, current);
    const pad = (hi - lo) * 0.06 || current * 0.05;
    lo = Math.max(0, lo - pad); hi = hi + pad;
  } else {
    lo = current * 0.75; hi = current * 1.25;
  }
  const at = (back: number) => (series.length > back ? series[series.length - 1 - back].close_price : current);
  const weekly: { price: number; date: string }[] = [];
  for (let i = series.length - 1; i >= 0; i -= 5) weekly.unshift({ price: series[i].close_price, date: series[i].date });

  const closesByOpen = new Map<string, OptionTrade[]>();
  for (const t of trades) {
    if (t.action === "close" && t.closes_trade_id) {
      const arr = closesByOpen.get(t.closes_trade_id) ?? []; arr.push(t); closesByOpen.set(t.closes_trade_id, arr);
    }
  }
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const dte = (expiry: string) => Math.round((new Date(expiry + "T00:00:00Z").getTime() - today.getTime()) / 86400000);
  const calls: BandOption[] = []; const puts: BandOption[] = [];
  for (const t of trades) {
    if (t.action !== "open") continue;
    const cls = closesByOpen.get(t.id) ?? [];
    const remaining = t.contracts - cls.reduce((s, c) => s + c.contracts, 0);
    const active = remaining > 0;
    const side: "sold" | "bought" = t.direction === "short" ? "sold" : "bought";
    const lastClose = cls.length ? cls.map((c) => c.trade_date).sort().reverse()[0] : undefined;
    const o: BandOption = {
      strike: t.strike, qty: active ? remaining : t.contracts, prem: t.premium, side,
      status: active ? "active" : "expired",
      ...(side === "sold" ? { sold: t.trade_date } : { bought: t.trade_date }),
      ...(active ? { expires: t.expiry, dte: dte(t.expiry) } : { closed: lastClose }),
    };
    (t.option_type === "call" ? calls : puts).push(o);
  }

  return {
    t: r.ticker, name: r.ticker, sector: r.sector ?? "",
    range: [Math.round(lo), Math.round(hi)], current,
    dayAgo: r.prev_close ?? at(1), weekAgo: at(5), monthAgo: at(21),
    avgCost: r.avg_cost, totalShares: r.quantity, breakeven: r.effective_cost ?? r.avg_cost,
    earningsDate: r.earnings_date ?? null, expectedMovePct: null,
    lots: [], calls, puts, closes: weekly,
    unrealizedPct: r.pnl_pct,
  };
}

// ─────────────────── §05 Focus insight ───────────────────────────
function FocusInsight({ rows, signalsByTicker, tradesByTicker, dailyCloses, onTickerClick }: {
  rows: PositionComputed[];
  signalsByTicker: Map<string, TickerSignals>;
  tradesByTicker: Map<string, OptionTrade[]>;
  dailyCloses: DailyClose[];
  onTickerClick: (t: string) => void;
}) {
  // SOT: live-leg count per ticker via useLiveLegs (A11).
  const { byTicker: liveCountByTicker } = useLiveLegs();
  const [xray, setXray] = useState(false);
  const bandRef = useRef<HTMLDivElement>(null);
  // Rank by "severity": biggest absolute unrealized loss first, then
  // anything with signal chips. Focus = the most pressing name.
  const ranked = useMemo(() => {
    return [...rows]
      .filter((r) => r.status !== "closed" && r.quantity > 0)
      .map((r) => {
        const sig = signalsByTicker.get(r.ticker);
        const chips = sig ? chipsForSignals(sig) : [];
        const severity = (r.pnl_dollar < 0 ? Math.abs(r.pnl_dollar) : 0) + chips.length * 5000;
        return { r, chips, severity };
      })
      .sort((a, b) => b.severity - a.severity);
  }, [rows, signalsByTicker]);

  const [idx, setIdx] = useState(0);
  // Focus row (null when the list is empty) — computed before the early
  // return so the X-ray mount effect obeys the rules of hooks.
  const focusRow = ranked.length ? ranked[Math.min(idx, ranked.length - 1)].r : null;
  const focusTicker = focusRow?.ticker ?? null;
  // Mount / remount the Position Lens band when X-ray is on or the focus
  // ticker changes; cleanup() removes the tooltip + clears the node.
  useEffect(() => {
    if (!xray || !bandRef.current || !focusRow) return;
    const data = positionToBand(focusRow, tradesByTicker.get(focusRow.ticker) ?? [], dailyCloses);
    return mountBand(bandRef.current, data);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [xray, focusTicker]);
  if (ranked.length === 0) return null;
  // Clamp the focus index in case the ranked list shrank (a position
  // closed) since the last render.
  const focusIdx = Math.min(idx, ranked.length - 1);
  const focus = ranked[focusIdx];
  // Queue = the next four names after the current focus, wrapping so
  // you can always keep stepping forward.
  const queue = Array.from({ length: Math.min(4, ranked.length - 1) }, (_, i) =>
    ranked[(focusIdx + 1 + i) % ranked.length],
  );
  const fr = focus.r;
  const sig = signalsByTicker.get(fr.ticker);
  const live = liveCountByTicker.get(fr.ticker) ?? 0;

  const step = (d: number) => setIdx(((focusIdx + d) % ranked.length + ranked.length) % ranked.length);

  return (
    <div>
      <Section n="05" right={`focus · ${focusIdx + 1} of ${ranked.length}`}>Stock insights · focus</Section>
      <div className={"focus" + (xray ? " xray-open" : "")}>
        <div className="card">
          <div className="header">
            <div>
              <div className="name" onClick={() => onTickerClick(fr.ticker)} style={{ cursor: "pointer" }} title="Open position">{fr.ticker}</div>
              <div className="sector">{fr.sector}</div>
            </div>
            {fr.earnings_date && <div className="earn">EARNINGS<br />{fr.earnings_date}</div>}
          </div>
          <div className="price">{fr.current_price != null ? fmtUSD(fr.current_price) : "—"}</div>
          <div className="price-meta">
            {sig?.chg_5d_pct != null ? `${sig.chg_5d_pct >= 0 ? "+" : ""}${sig.chg_5d_pct.toFixed(1)}% over 5d` : "—"}
            {live > 0 && ` · ${live} live leg${live === 1 ? "" : "s"}`}
          </div>
          <div className="spark-wrap">
            <Spark w={620} h={48} kind={fr.pnl_dollar >= 0 ? "pos" : "neg"} delay={400} />
          </div>
          <div className="pos-block">
            <div>
              <div className="label">YOUR POSITION</div>
              <div className="v">{fr.quantity.toLocaleString()} sh · cost {fmtUSD(fr.avg_cost)}</div>
            </div>
            <div>
              <div className="label">UNREALIZED</div>
              <div className={"v " + (fr.pnl_dollar < 0 ? "neg" : "pos")}>
                <MoneyCount value={Math.round(Math.abs(fr.pnl_dollar))} sign={fr.pnl_dollar < 0 ? "-" : "+"} delay={500} />
                <span style={{ marginLeft: 8, color: "var(--fg3)" }}>{fmtPct(fr.pnl_pct)}</span>
              </div>
            </div>
          </div>
          {focus.chips.length > 0 && (
            <div className="signals">
              {focus.chips.map((c) => <span key={c.label} className={"chip " + (c.tone === "warn" ? "warn" : c.tone === "down" ? "neg" : c.tone === "up" ? "pos" : "")}>{c.label}</span>)}
            </div>
          )}
          {/* Position Lens — inline X-ray of this position's price band */}
          <button className={"xray-btn" + (xray ? " on" : "")} onClick={() => setXray((v) => !v)}>
            ⊹ {xray ? "Hide X-ray" : "X-ray position"}
          </button>
          {xray && <div className="xray-band" ref={bandRef} />}
        </div>
        <div className="queue">
          <div className="label" style={{ marginBottom: 12 }}>UP NEXT · by severity</div>
          {queue.map((q) => {
            const qIdx = ranked.indexOf(q);
            return (
              <div key={q.r.ticker} className="q-row" onClick={() => setIdx(qIdx)} title="Click to focus">
                <span className="t">{q.r.ticker}</span>
                <span className="meta">{q.r.pnl_dollar >= 0 ? "+" : "−"}{fmtUSD(Math.abs(q.r.pnl_dollar))}</span>
                {q.chips[0] && <span className={"chip " + (q.chips[0].tone === "warn" ? "warn" : "neg")}>{q.chips[0].label}</span>}
              </div>
            );
          })}
          <div className="nav">
            <span onClick={() => step(-1)}>← prev</span>
            <span style={{ color: "var(--neon)" }}>{focusIdx + 1} / {ranked.length}</span>
            <span onClick={() => step(1)}>next →</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── §06 Realized summary ────────────────────────
function RealizedBlock({ rows, realizedByTicker, tradesByTicker }: {
  rows: PositionComputed[];
  realizedByTicker: Map<string, number>;
  tradesByTicker: Map<string, OptionTrade[]>;
}) {
  const entered = useEntered(300);
  const { premium, gains, putCost } = useMemo(() => {
    let premium = 0, gains = 0, putCost = 0;
    for (const r of rows) {
      premium += realizedByTicker.get(r.ticker) ?? 0;
      gains += r.realized_stock_pl ?? 0;
    }
    for (const [, list] of tradesByTicker) {
      const closedQty = new Map<string, number>();
      for (const t of list) if (t.action === "close" && t.closes_trade_id) closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
      for (const t of list) {
        if (t.action === "open" && t.option_type === "put" && t.direction === "long") {
          const rem = t.contracts - (closedQty.get(t.id) ?? 0);
          if (rem > 0) putCost += rem * 100 * t.premium;
        }
      }
    }
    return { premium, gains, putCost };
  }, [rows, realizedByTicker, tradesByTicker]);

  const max = Math.max(Math.abs(premium), Math.abs(gains), Math.abs(putCost), 1);
  const data = [
    { label: "INCOME · PREMIUM", amt: premium, sign: premium >= 0 ? "+" : "-" as const, meta: "closed option pairs", kind: premium >= 0 ? "pos" : "neg", pct: Math.abs(premium) / max, color: "var(--neon)" },
    { label: "INVESTMENT · GAINS", amt: gains, sign: gains >= 0 ? "+" : "-" as const, meta: "share sales + assignments", kind: gains >= 0 ? "pos" : "neg", pct: Math.abs(gains) / max, color: "var(--positive)" },
    { label: "PROTECTIVE PUTS · COST", amt: putCost, sign: "-" as const, meta: "open long-put premium", kind: "neg", pct: Math.abs(putCost) / max, color: "var(--negative)" },
  ];

  return (
    <div>
      <Section n="06" right="all-time">Realized · summary</Section>
      {data.map((r, i) => (
        <div key={r.label} className="realized-row">
          <div>
            <div className="r-label">{r.label}</div>
            <div className="r-meta">{r.meta}</div>
          </div>
          <div className="r-bar-wrap">
            <div className="r-bar-fill" style={{ width: entered ? `${r.pct * 100}%` : "0%", background: r.color, opacity: 0.6, transitionDelay: `${i * 120}ms` }} />
          </div>
          <div className={"r-amt " + r.kind}>
            <MoneyCount value={Math.round(Math.abs(r.amt))} sign={r.sign as "+" | "-"} delay={400 + i * 120} />
          </div>
        </div>
      ))}
    </div>
  );
}

// ─────────────────── Page assembly ───────────────────────────────
export function PositionsV2Body(props: PositionsV2BodyProps) {
  const { portfolio, liveByTicker, overlayByTicker, signalsByTicker, realizedByTicker, tradesByTicker, onUpload, onRefresh, refreshing, onTickerClick } = props;
  const now = useNow(60_000);
  const dateLabel = fmtBrandDate(now);

  const brand = (
    <PositionsBrandBar dateLabel={dateLabel} onRefresh={onRefresh} refreshing={refreshing} onUpload={onUpload} />
  );

  if (portfolio.rows.length === 0) {
    return (
      <div className="dash"><div className="dash-inner">
        {brand}
        <div className="row" style={{ marginTop: 56, textAlign: "center", padding: "80px 0" }}>
          <div className="label" style={{ marginBottom: 16 }}>NO POSITIONS YET</div>
          <span className="pill" onClick={onUpload} style={{ cursor: "pointer" }}>↑ Upload positions</span>
        </div>
      </div></div>
    );
  }

  return (
    <div className="dash">
      <div className="dash-inner">
        <div className="row first">{brand}</div>
        <div className="row tight" style={{ marginTop: 28 }}><TickerStrip compact /></div>
        <div className="row" style={{ marginTop: 56 }}><PositionsHero portfolio={portfolio} /></div>
        <div className="row" style={{ marginTop: 84 }}><AllocationBlock rows={portfolio.rows} overlayByTicker={overlayByTicker} onTickerClick={onTickerClick} /></div>
        <div className="row" style={{ marginTop: 72 }}><ProtectionBlock rows={portfolio.rows} tradesByTicker={tradesByTicker} /></div>
        <div className="row" style={{ marginTop: 72 }}><StrategyBuckets rows={portfolio.rows} overlayByTicker={overlayByTicker} realizedByTicker={realizedByTicker} /></div>
        <div className="row" style={{ marginTop: 72 }}><PositionsLedger {...props} /></div>
        <div className="row" style={{ marginTop: 72 }}><FocusInsight rows={portfolio.rows} signalsByTicker={signalsByTicker} tradesByTicker={props.tradesByTicker} dailyCloses={props.dailyCloses} onTickerClick={onTickerClick} /></div>
        <div className="row" style={{ marginTop: 72 }}><RealizedBlock rows={portfolio.rows} realizedByTicker={realizedByTicker} tradesByTicker={tradesByTicker} /></div>
        <div className="row" style={{ marginTop: 64 }}>
          <div className="tools-rail"><span className="build">Sunnyfi · positions</span></div>
        </div>
      </div>
    </div>
  );
}

export { fmtUSD, fmtPct };
