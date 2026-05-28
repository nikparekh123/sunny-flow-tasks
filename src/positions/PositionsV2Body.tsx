/**
 * Positions v2 — Navi editorial redesign body.
 *
 * Presentation-only: receives the portfolio + callbacks from
 * PositionsPage, which keeps the single source of truth for data
 * (usePositions) and the modal stack. This lets the new design and the
 * existing (more complete) modals coexist while we build out the
 * sections PR by PR.
 *
 * Renders inside the `.dash` shell so it reuses the dashboard's token
 * + atom layer (dashboard.css) plus the positions-specific blocks in
 * positions-v2.css. Both are scoped under `.dash` and never collide
 * with the `.np-app` styling the modals still use.
 *
 * Build status (filled in across PP-1 … PP-7):
 *   PP-1 (this commit) — brand bar, ticker, §00 hero. Rest stubbed.
 */
import { TickerStrip } from "@/sunnyfi/dashboard/blocks";
import { Section } from "@/sunnyfi/dashboard/atoms";
import { MoneyCount, PctCount } from "@/sunnyfi/lib/animation";
import { useNow, fmtBrandDate } from "@/sunnyfi/dashboard/time";
import { fmtUSD, fmtPct, type PositionComputed } from "./types";
import "@/sunnyfi/pages/dashboard.css";
import "./positions-v2.css";

type Bucket = "income" | "invest" | "yield";

export interface PortfolioLike {
  rows: PositionComputed[];
  total_market_value: number;
  total_pnl: number;
  total_pnl_pct: number;
}

export interface PositionsV2BodyProps {
  portfolio: PortfolioLike;
  liveByTicker: Map<string, import("./types").LiveOption[]>;
  overlayByTicker: Map<string, Bucket>;
  onUpload: () => void;
  onRefresh: () => void;
  refreshing: boolean;
  onTickerClick: (ticker: string) => void;
  onDashboard: () => void;
  onStrategy: () => void;
}

/** Brand bar matching the design — logo + route + top-nav inline, date
 *  + actions on the right. Uses the .top-nav / .nav-link classes added
 *  in positions-v2.css. */
function PositionsBrandBar({
  dateLabel, onDashboard, onStrategy, onRefresh, refreshing, onUpload,
}: {
  dateLabel: string;
  onDashboard: () => void;
  onStrategy: () => void;
  onRefresh: () => void;
  refreshing: boolean;
  onUpload: () => void;
}) {
  return (
    <div className="brandbar">
      <div className="mark">
        <a className="logo" onClick={onDashboard} style={{ cursor: "pointer", textDecoration: "none" }}>◆ SUNNYFI</a>
        <span className="slash">/</span>
        <span className="route">Positions<span className="cursor" /></span>
        <nav className="top-nav">
          <a className="nav-link on">Positions</a>
          <a className="nav-link" onClick={onStrategy} style={{ cursor: "pointer" }}>New Strategy</a>
        </nav>
      </div>
      <div className="actions">
        <span className="label">{dateLabel}</span>
        <span className="pill muted" onClick={onRefresh} style={{ cursor: "pointer" }}>
          ↻ {refreshing ? "Refreshing…" : "Refresh prices"}
        </span>
        <span className="pill" onClick={onUpload} style={{ cursor: "pointer" }}>↑ Upload positions</span>
      </div>
    </div>
  );
}

/** §00 — Portfolio hero. Total value (neon) + unrealized side panel
 *  with a live position/leg count. */
function PositionsHero({ portfolio, liveByTicker }: {
  portfolio: PortfolioLike;
  liveByTicker: Map<string, import("./types").LiveOption[]>;
}) {
  const open = portfolio.rows.filter((r) => r.status !== "closed" && r.quantity > 0);
  let calls = 0, puts = 0;
  for (const legs of liveByTicker.values()) {
    for (const lo of legs) {
      if (lo.open.option_type === "call") calls += 1;
      else puts += 1;
    }
  }
  const isUp = portfolio.total_pnl >= 0;
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
          <div className="label">UNREALIZED</div>
          <div className={"unr-amt " + (isUp ? "pos" : "neg")}>
            <MoneyCount value={Math.round(portfolio.total_pnl)} sign={isUp ? "+" : "-"} delay={200} />
          </div>
          <div className={"unr-pct " + (isUp ? "pos" : "neg")}>
            <PctCount value={Math.abs(portfolio.total_pnl_pct)} sign={isUp ? "+" : "-"} delay={300} />
          </div>
          <div className="live">
            <span className="live-dot" /> {open.length} positions · {calls} calls · {puts} puts
          </div>
        </div>
      </div>
    </div>
  );
}

/** Placeholder for sections still being built (PP-2 … PP-6). */
function StubSection({ n, title, label }: { n: string; title: string; label: string }) {
  return (
    <div>
      <Section n={n} right={label}>{title}</Section>
      <div style={{ padding: "40px 0", color: "var(--fg4)", fontFamily: "var(--mono)", fontSize: 12, letterSpacing: "1.4px", textTransform: "uppercase" }}>
        coming next
      </div>
    </div>
  );
}

export function PositionsV2Body(props: PositionsV2BodyProps) {
  const { portfolio, liveByTicker, onUpload, onRefresh, refreshing, onDashboard, onStrategy } = props;
  const now = useNow(60_000);
  const dateLabel = fmtBrandDate(now);

  // Empty state — no positions yet.
  if (portfolio.rows.length === 0) {
    return (
      <div className="dash">
        <div className="dash-inner">
          <PositionsBrandBar
            dateLabel={dateLabel}
            onDashboard={onDashboard}
            onStrategy={onStrategy}
            onRefresh={onRefresh}
            refreshing={refreshing}
            onUpload={onUpload}
          />
          <div className="row" style={{ marginTop: 56, textAlign: "center", padding: "80px 0" }}>
            <div className="label" style={{ marginBottom: 16 }}>NO POSITIONS YET</div>
            <span className="pill" onClick={onUpload} style={{ cursor: "pointer" }}>↑ Upload positions</span>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="dash">
      <div className="dash-inner">
        <div className="row first">
          <PositionsBrandBar
            dateLabel={dateLabel}
            onDashboard={onDashboard}
            onStrategy={onStrategy}
            onRefresh={onRefresh}
            refreshing={refreshing}
            onUpload={onUpload}
          />
        </div>

        <div className="row tight" style={{ marginTop: 28 }}>
          <TickerStrip compact />
        </div>

        <div className="row" style={{ marginTop: 56 }}>
          <PositionsHero portfolio={portfolio} liveByTicker={liveByTicker} />
        </div>

        {/* Sections filled in across PP-2 … PP-6 */}
        <div className="row" style={{ marginTop: 84 }}>
          <StubSection n="01" title="Allocation" label="PP-2" />
        </div>
        <div className="row" style={{ marginTop: 72 }}>
          <StubSection n="02" title="Put protection" label="PP-4" />
        </div>
        <div className="row" style={{ marginTop: 72 }}>
          <StubSection n="03" title="Strategy" label="PP-5" />
        </div>
        <div className="row" style={{ marginTop: 72 }}>
          <StubSection n="04" title="Positions ledger" label="PP-3" />
        </div>
        <div className="row" style={{ marginTop: 72 }}>
          <StubSection n="05" title="Stock insights · focus" label="PP-6" />
        </div>
        <div className="row" style={{ marginTop: 72 }}>
          <StubSection n="06" title="Realized · summary" label="PP-7" />
        </div>
      </div>
    </div>
  );
}

// fmt helpers re-exported for the sections built in later PRs.
export { fmtUSD, fmtPct };
