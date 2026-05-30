/**
 * Master Positions — app shell.
 *
 * Greeks bar + controls (Table/Cards/Cockpit toggle, needs-attention
 * filter, show-closed, smart sort) + active view + Focus modal.
 *
 * **PD-0 scaffold**: hardcoded sample data from `./data`. PD-1+2 will
 * swap MODEL for a live hook (`useMasterPositions()`) without changing
 * any of the rendered shapes here.
 */
import { useState } from "react";
import { CLOSED, fmtMoney, fmtGreek, signCls, type Company } from "./data";
import { LiveStatus } from "./atoms";
import { TableView, CardsView, CockpitView } from "./views";
import { FocusMenu, FocusStage, FocusToast } from "./focus";
import { useMasterPositions } from "./useMasterPositions";
import type { PortfolioRollup } from "./buildCompanies";
import "./portfolio.css";

function GreeksBar({ p }: { p: PortfolioRollup }) {
  const cells = [
    { k: "Net delta · position", v: p.delta, cls: "neon", sub: "share-equivalent · " + (p.delta >= 0 ? "net long" : "net short"), lead: true, g: "◆" },
    { k: "Beta-weighted delta", v: p.betaWeightedDelta, sub: "SPY-equivalent exposure", g: "β", cls: "" },
    { k: "Net theta · per day", v: p.theta, cls: signCls(p.theta), sub: "decay collected daily", g: "Θ" },
    { k: "Net vega · per 1% IV", v: p.vega, cls: signCls(p.vega), sub: p.vega < 0 ? "short volatility" : "long volatility", g: "V" },
    { k: "Net gamma", v: p.gamma, cls: signCls(p.gamma), sub: "Δ change per $1 move", g: "Γ" },
  ];
  return (
    <div className="greeks-bar">
      {cells.map((c, i) => (
        <div key={i} className={"cell" + (c.lead ? " lead" : "")}>
          <div className="gk-lbl"><span className="glyph">{c.g}</span>{c.k}</div>
          <div className={"gk-val " + (c.cls || "")}>{fmtGreek(Math.round(c.v))}</div>
          <div className="gk-sub">{c.sub}</div>
        </div>
      ))}
      <div className="cell">
        <div className="gk-lbl"><span className="glyph">$</span>Open P&amp;L</div>
        <div className={"gk-val " + signCls(p.net)}>{fmtMoney(p.unreal, true)}</div>
        <div className="gk-sub">
          {p.companies} companies · {p.legs} legs · {p.opts} options
        </div>
      </div>
    </div>
  );
}

type ViewKey = "table" | "cards" | "cockpit";

/** Format the freshness timestamp as "HH:MM PT" (ET → PT shifted, since
 *  the brand bar elsewhere shows PT). Empty if no data yet. */
function fmtFreshness(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  // toLocaleTimeString respects the browser's tz; show just the clock.
  return d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false });
}

export function MasterPositions({
  defaultView = "table",
}: {
  defaultView?: ViewKey;
}) {
  const [view, setView] = useState<ViewKey>(defaultView);
  const [smart, setSmart] = useState(false);
  const [risk, setRisk] = useState(false);
  const [closed, setClosed] = useState(false);
  const [menu, setMenu] = useState<{ c: Company; x: number; y: number } | null>(null);
  const [focusT, setFocusT] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  // SOT: live data from option_greeks + ticker_quotes + the existing
  // positions/trades/share_sells tables, joined into the Company shape
  // the views consume.
  const { companies, portfolio, isLoading, freshness, refresh, refreshing } =
    useMasterPositions();

  let data: Company[] = closed ? [...companies, ...CLOSED] : [...companies];
  if (risk) data = data.filter((c) => !c.closed && c.flags.some((f) => f.tone === "neg" || f.tone === "warn"));
  if (smart) {
    data = [...data].sort((a, b) =>
      (Number(!!a.closed) - Number(!!b.closed)) ||
      (b.sev - a.sev) ||
      (Math.abs(b.agg.unreal) - Math.abs(a.agg.unreal))
    );
  }

  const openMenu = (c: Company, x: number, y: number) => setMenu({ c, x, y });
  const stepFocus = (dir: number) => {
    const i = data.findIndex((c) => c.t === focusT);
    if (i < 0) return;
    setFocusT(data[(i + dir + data.length) % data.length].t);
  };
  const copyVal = (text: string, label: string) => {
    try { navigator.clipboard?.writeText(text); } catch { /* sandbox */ }
    setToast(label);
    setTimeout(() => setToast(null), 1700);
  };

  const riskCount = companies.filter((c) =>
    c.flags.some((f) => f.tone === "neg" || f.tone === "warn")
  ).length;
  const time = fmtFreshness(freshness);

  const views: Array<[ViewKey, string]> = [
    ["table", "Table"], ["cards", "Cards"], ["cockpit", "Δ Cockpit"],
  ];

  return (
    <div className="portfolio-page">
      <div className="mp-head">
        <div className="title-wrap">
          <div className="mp-eyebrow">
            <span className="n">SOURCE OF TRUTH</span> · everything in the portfolio, by company
          </div>
          <div className="mp-title">Portfolio<span className="sub"> / positions &amp; greeks</span></div>
        </div>
        <div className="right">
          <LiveStatus time={time} />
          <div style={{ fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "1px", color: "var(--fg4)", textTransform: "uppercase" }}>
            Fri · May 29 · open positions only
          </div>
        </div>
      </div>

      <GreeksBar p={portfolio} />

      <div className="mp-controls">
        <span className="view-toggle">
          {views.map(([k, l]) => (
            <button key={k} className={"vt" + (view === k ? " on" : "")} onClick={() => setView(k)}>{l}</button>
          ))}
        </span>
        <span style={{ width: 14 }} />
        <span className="label">Filter</span>
        <button className={"fchip risk" + (risk ? " on" : "")} onClick={() => setRisk(!risk)}>
          ⚠ Needs attention <span className="c">{riskCount}</span>
        </button>
        <button className={"fchip closed" + (closed ? " on" : "")} onClick={() => setClosed(!closed)}>
          {closed ? "✓ " : ""}Show closed <span className="c">{CLOSED.length}</span>
        </button>
        <span className="spacer" />
        <button
          className="fchip"
          onClick={refresh}
          disabled={refreshing}
          title="Re-pull live Greeks + quotes from Polygon (massive.com). Runs automatically every 15 min during market hours; this is the manual trigger."
        >
          ↻ {refreshing ? "Refreshing…" : "Refresh"}
        </button>
        <span className={"sort-toggle" + (smart ? " on" : "")} onClick={() => setSmart(!smart)}>
          <span className="sw" /> Smart sort · attention first
        </span>
      </div>

      {isLoading && companies.length === 0 && (
        <div style={{ padding: "60px 0", textAlign: "center", color: "var(--fg3)", fontFamily: "var(--mono)", fontSize: 12, letterSpacing: "1.2px", textTransform: "uppercase" }}>
          Loading positions…
        </div>
      )}
      {!isLoading && companies.length === 0 && (
        <div style={{ padding: "60px 0", textAlign: "center", color: "var(--fg3)", fontFamily: "var(--mono)", fontSize: 12, letterSpacing: "1.2px", textTransform: "uppercase" }}>
          No open positions
        </div>
      )}

      {view === "table" && <TableView data={data} onFocusMenu={openMenu} />}
      {view === "cards" && <CardsView data={data} />}
      {view === "cockpit" && <CockpitView data={data} />}

      <FocusMenu menu={menu} onShow={setFocusT} onCopy={copyVal} onClose={() => setMenu(null)} />
      {focusT && (
        <FocusStage data={data} t={focusT} onClose={() => setFocusT(null)} onStep={stepFocus} />
      )}
      <FocusToast toast={toast} />

      <div className="mp-foot">
        <span>Sunnyfi desk · portfolio · source of truth · v0</span>
        <span>Greeks at position level · 15-min delayed marks · last sync {time} PT</span>
      </div>
    </div>
  );
}
