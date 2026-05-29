/* incomeChart.tsx
 *
 * The Income feature, ported from the Claude design handoff
 * (/Downloads/Weekly income) and wired to live Sunnyfi data.
 *
 * A Tesla-energy-style diverging premium chart: premium COLLECTED points up
 * (Calls + Puts + Shares stacked); buy-to-close debits point down. Period
 * switcher (Day/Week/Month/Quarter/Year), weighted-recent-trend projection as
 * ghost forward bars, hover tooltips.
 *
 * Data sources (all live, no placeholders):
 *   - option_trades : short call/put OPENs → calls/puts collected;
 *                     short CLOSEs → buy-to-close debit (bought back).
 *   - share_sells   : realized_pl bucketed by sale date → "Shares" income.
 *                     (Dividends are not tracked yet — gains only.)
 *
 * Exports: IncomeScreen (full /income page body), IncomeWeekly (compact
 * dashboard card), buildSeries (testable bucketing).
 */
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Section } from "./atoms";
import { BrandBar, ToolsRail } from "./blocks";
import { MoneyCount } from "./animation";

/* ============================================================
   LIVE DATA
   ============================================================ */
interface IncTrade {
  trade_date: string;
  action: "open" | "close";
  option_type: "call" | "put";
  direction: "short" | "long";
  contracts: number;
  premium: number;
}
interface IncSell {
  trade_date: string;
  realized_pl: number;
}

function useIncomeTradesAll() {
  return useQuery({
    queryKey: ["income_trades_all"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("trade_date, action, option_type, direction, contracts, premium")
        .returns<IncTrade[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

function useShareSellsAll() {
  return useQuery({
    queryKey: ["income_share_sells"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("share_sells" as never)
        .select("trade_date, realized_pl")
        .returns<IncSell[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

/* ============================================================
   FORMATTING + MATH  (ported)
   ============================================================ */
const fmtUSD = (v: number) => "$" + Math.round(v).toLocaleString("en-US");
function fmtK(v: number): string {
  const a = Math.abs(v);
  if (a >= 1000) {
    const k = v / 1000;
    return "$" + (a >= 100000 ? Math.round(k) : k.toFixed(a >= 10000 ? 0 : 1)) + "k";
  }
  return "$" + Math.round(v);
}
function niceMax(v: number): number {
  if (v <= 0) return 1;
  const mag = Math.pow(10, Math.floor(Math.log10(v)));
  const n = v / mag;
  const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return step * mag;
}

// Weighted recent-trend projection: extrapolates a field forward, weighting
// recent period-over-period deltas higher, with damping so it doesn't run away.
function weightedTrend(series: number[], steps: number): number[] {
  const deltas: number[] = [];
  for (let i = 1; i < series.length; i++) deltas.push(series[i] - series[i - 1]);
  const k = Math.min(deltas.length, 6);
  const recent = deltas.slice(-k);
  let wsum = 0, dsum = 0;
  recent.forEach((d, i) => { const w = i + 1; wsum += w; dsum += d * w; });
  const avg = wsum ? dsum / wsum : 0;
  const out: number[] = [];
  let last = series[series.length - 1] ?? 0;
  for (let s = 0; s < steps; s++) { last = Math.max(0, last + avg * 0.6); out.push(Math.round(last)); }
  return out;
}

/* ============================================================
   BUCKETING  (live → {actual, proj, ...})
   ============================================================ */
export type Period = "day" | "week" | "month" | "quarter" | "year";

export interface IncomeRow {
  label: string;
  calls: number;
  puts: number;
  shares: number;
  debit: number;
  proj: boolean;
}
export interface IncomeSeries {
  actual: IncomeRow[];
  proj: IncomeRow[];
  unit: Period;
  currentLabel: string;
  steps: number;
}

const MONTH_ABBR = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const MONTH_FULL = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const WEEKDAY = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const pad2 = (n: number) => String(n).padStart(2, "0");
const md = (d: Date) => `${d.getUTCMonth() + 1}/${d.getUTCDate()}`;

function weekMondayDate(d: Date): Date {
  const x = new Date(d);
  const dow = x.getUTCDay();
  x.setUTCDate(x.getUTCDate() + (dow === 0 ? -6 : 1 - dow));
  x.setUTCHours(0, 0, 0, 0);
  return x;
}

interface PeriodCfg {
  steps: number;
  buckets(now: Date): { key: string; label: string }[]; // oldest → newest
  keyOf(iso: string): string;
  projLabels(now: Date, steps: number): string[];
  currentLabel(now: Date): string;
}

const PERIODS: Record<Period, PeriodCfg> = {
  day: {
    steps: 4,
    buckets(now) {
      const out: { key: string; label: string }[] = [];
      for (let i = 13; i >= 0; i--) {
        const d = new Date(now); d.setUTCDate(d.getUTCDate() - i);
        out.push({ key: d.toISOString().slice(0, 10), label: md(d) });
      }
      return out;
    },
    keyOf: (iso) => iso,
    projLabels(now, steps) {
      const out: string[] = [];
      for (let i = 1; i <= steps; i++) { const d = new Date(now); d.setUTCDate(d.getUTCDate() + i); out.push(md(d)); }
      return out;
    },
    currentLabel: (now) => `${WEEKDAY[now.getUTCDay()]} · ${MONTH_FULL[now.getUTCMonth()].slice(0, 3)} ${now.getUTCDate()}`,
  },
  week: {
    steps: 3,
    buckets(now) {
      const monday = weekMondayDate(now);
      const out: { key: string; label: string }[] = [];
      for (let i = 7; i >= 0; i--) {
        const d = new Date(monday); d.setUTCDate(d.getUTCDate() - i * 7);
        out.push({ key: d.toISOString().slice(0, 10), label: md(d) });
      }
      return out;
    },
    keyOf: (iso) => weekMondayDate(new Date(iso + "T00:00:00Z")).toISOString().slice(0, 10),
    projLabels(now, steps) {
      const monday = weekMondayDate(now);
      const out: string[] = [];
      for (let i = 1; i <= steps; i++) { const d = new Date(monday); d.setUTCDate(d.getUTCDate() + i * 7); out.push(md(d)); }
      return out;
    },
    currentLabel: (now) => `Week ending ${MONTH_FULL[now.getUTCMonth()].slice(0, 3)} ${now.getUTCDate()}`,
  },
  month: {
    steps: 3,
    buckets(now) {
      const out: { key: string; label: string }[] = [];
      for (let i = 9; i >= 0; i--) {
        const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
        out.push({ key: `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}`, label: MONTH_ABBR[d.getUTCMonth()] });
      }
      return out;
    },
    keyOf: (iso) => iso.slice(0, 7),
    projLabels(now, steps) {
      const out: string[] = [];
      for (let i = 1; i <= steps; i++) { const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + i, 1)); out.push(MONTH_ABBR[d.getUTCMonth()]); }
      return out;
    },
    currentLabel: (now) => `${MONTH_FULL[now.getUTCMonth()]} ${now.getUTCFullYear()}`,
  },
  quarter: {
    steps: 2,
    buckets(now) {
      let y = now.getUTCFullYear(); let q = Math.floor(now.getUTCMonth() / 3);
      const seq: { y: number; q: number }[] = [];
      for (let i = 0; i < 6; i++) { seq.push({ y, q }); q--; if (q < 0) { q = 3; y--; } }
      seq.reverse();
      return seq.map(({ y, q }) => ({ key: `${y}-Q${q + 1}`, label: `Q${q + 1}·${String(y).slice(2)}` }));
    },
    keyOf(iso) {
      const d = new Date(iso + "T00:00:00Z");
      return `${d.getUTCFullYear()}-Q${Math.floor(d.getUTCMonth() / 3) + 1}`;
    },
    projLabels(now, steps) {
      let y = now.getUTCFullYear(); let q = Math.floor(now.getUTCMonth() / 3);
      const out: string[] = [];
      for (let i = 0; i < steps; i++) { q++; if (q > 3) { q = 0; y++; } out.push(`Q${q + 1}·${String(y).slice(2)}`); }
      return out;
    },
    currentLabel: (now) => `Q${Math.floor(now.getUTCMonth() / 3) + 1} ${now.getUTCFullYear()} · in progress`,
  },
  year: {
    steps: 1,
    buckets(now) {
      const y = now.getUTCFullYear();
      const out: { key: string; label: string }[] = [];
      for (let i = 4; i >= 0; i--) { const yy = y - i; out.push({ key: String(yy), label: String(yy) }); }
      return out;
    },
    keyOf: (iso) => iso.slice(0, 4),
    projLabels(now, steps) {
      const y = now.getUTCFullYear();
      const out: string[] = [];
      for (let i = 1; i <= steps; i++) out.push(String(y + i));
      return out;
    },
    currentLabel: (now) => `${now.getUTCFullYear()} · YTD`,
  },
};

/** Bucket live trades + share sells for a period and project forward. */
export function buildSeries(period: Period, trades: IncTrade[], sells: IncSell[]): IncomeSeries {
  const cfg = PERIODS[period];
  const now = new Date();
  now.setUTCHours(0, 0, 0, 0);
  const buckets = cfg.buckets(now);
  const idx = new Map<string, IncomeRow>();
  for (const b of buckets) idx.set(b.key, { label: b.label, calls: 0, puts: 0, shares: 0, debit: 0, proj: false });

  for (const t of trades) {
    if (t.direction !== "short") continue;
    const row = idx.get(cfg.keyOf(t.trade_date));
    if (!row) continue;
    const dollars = t.contracts * 100 * t.premium;
    if (t.action === "open") {
      if (t.option_type === "call") row.calls += dollars;
      else row.puts += dollars;
    } else {
      row.debit += dollars; // short close = buy-to-close = bought back
    }
  }
  for (const s of sells) {
    const row = idx.get(cfg.keyOf(s.trade_date));
    if (!row) continue;
    row.shares += s.realized_pl;
  }

  const actual: IncomeRow[] = buckets.map((b) => {
    const r = idx.get(b.key)!;
    return { ...r, shares: Math.max(0, r.shares) }; // income lane stays ≥ 0
  });

  const callsP = weightedTrend(actual.map((d) => d.calls), cfg.steps);
  const putsP = weightedTrend(actual.map((d) => d.puts), cfg.steps);
  const sharesP = weightedTrend(actual.map((d) => d.shares), cfg.steps);
  const debitP = weightedTrend(actual.map((d) => d.debit), cfg.steps);
  const proj: IncomeRow[] = cfg.projLabels(now, cfg.steps).map((label, i) => ({
    label, calls: callsP[i], puts: putsP[i], shares: sharesP[i], debit: debitP[i], proj: true,
  }));

  return { actual, proj, unit: period, currentLabel: cfg.currentLabel(now), steps: cfg.steps };
}

/* ============================================================
   CHART  (ported)
   ============================================================ */
const UP_FRAC = 0.66;
const DOWN_FRAC = 0.34;

function IncomeChart({ series, showProj = true }: { series: IncomeSeries; showProj?: boolean }) {
  const cols = showProj ? [...series.actual, ...series.proj] : [...series.actual];
  const n = cols.length;
  const actualCount = series.actual.length;

  const scaleUp = niceMax(Math.max(...cols.map((c) => c.calls + c.puts + c.shares), 0));
  const scaleDown = niceMax(Math.max(...cols.map((c) => c.debit), 0));

  const [active, setActive] = useState<number | null>(null);

  const gridlines = [
    { top: 0, label: fmtK(scaleUp) },
    { top: UP_FRAC / 2, label: fmtK(scaleUp / 2) },
    { top: UP_FRAC, label: "$0", zero: true },
    { top: UP_FRAC + DOWN_FRAC / 2, label: fmtK(scaleDown / 2) },
    { top: 1, label: fmtK(scaleDown) },
  ];

  const a = active != null ? cols[active] : null;
  let tipTopFrac = 0, tipAbove = true;
  if (a) {
    const total = a.calls + a.puts + a.shares;
    tipTopFrac = UP_FRAC * (1 - total / scaleUp);
    tipAbove = tipTopFrac > 0.26;
  }
  const tipTx = active != null && active <= 0 ? "-8%" : active != null && active >= n - 1 ? "-92%" : "-50%";

  return (
    <div className="inc-chart">
      <div className="inc-plot">
        {gridlines.map((g, i) => (
          <div key={i} className={"inc-grid" + (g.zero ? " zero" : "")} style={{ top: `${g.top * 100}%` }}>
            <span className="inc-ylab">{g.label}</span>
          </div>
        ))}
        <div className="inc-region-tag" style={{ top: "1%" }}>Collected</div>
        <div className="inc-region-tag" style={{ top: `${UP_FRAC * 100 + 1}%` }}>Bought back</div>

        <div className="inc-cols" onMouseLeave={() => setActive(null)}>
          {cols.map((c, i) => {
            const callsH = (c.calls / scaleUp) * 100;
            const putsH = (c.puts / scaleUp) * 100;
            const sharesH = (c.shares / scaleUp) * 100;
            const debitH = (c.debit / scaleDown) * 100;
            return (
              <div
                key={i}
                className={"inc-col" + (c.proj ? " proj" : "") + (active === i ? " active" : "")}
                onMouseEnter={() => setActive(i)}
              >
                <div className="inc-up" style={{ top: 0, bottom: `${DOWN_FRAC * 100}%` }}>
                  <div className="inc-seg-bar shares" style={{ height: `${sharesH}%` }} />
                  <div className="inc-seg-bar puts" style={{ height: `${putsH}%` }} />
                  <div className="inc-seg-bar calls" style={{ height: `${callsH}%` }} />
                </div>
                <div className="inc-down" style={{ top: `${UP_FRAC * 100}%`, bottom: 0 }}>
                  <div className="inc-seg-bar debit" style={{ height: `${debitH}%` }} />
                </div>
              </div>
            );
          })}
        </div>

        {showProj && series.proj.length > 0 && (
          <div className="inc-proj-divider" style={{ left: `${(actualCount / n) * 100}%` }}>
            <span className="tag">Projected →</span>
          </div>
        )}

        {a && active != null && (
          <div
            className="inc-tip"
            style={{
              left: `${((active + 0.5) / n) * 100}%`,
              top: `${tipTopFrac * 100}%`,
              transform: tipAbove ? `translate(${tipTx}, calc(-100% - 12px))` : `translate(${tipTx}, 14px)`,
            }}
          >
            <div className="tip-period">{a.label}{a.proj && <span className="proj-flag">· projected</span>}</div>
            <div className="tip-row">
              <span className="k"><span className="dot" style={{ background: "var(--inc-calls)" }} />Calls</span>
              <span className="v">{fmtUSD(a.calls)}</span>
            </div>
            <div className="tip-row">
              <span className="k"><span className="dot" style={{ background: "var(--inc-puts)" }} />Puts</span>
              <span className="v">{fmtUSD(a.puts)}</span>
            </div>
            <div className="tip-row">
              <span className="k"><span className="dot" style={{ background: "var(--inc-shares)" }} />Shares</span>
              <span className="v">{fmtUSD(a.shares)}</span>
            </div>
            <div className="tip-row">
              <span className="k"><span className="dot" style={{ background: "var(--inc-debit)" }} />Bought back</span>
              <span className="v neg">−{fmtUSD(a.debit)}</span>
            </div>
            <div className="tip-net">
              <span className="k">Net kept</span>
              <span className="v">{fmtUSD(a.calls + a.puts + a.shares - a.debit)}</span>
            </div>
          </div>
        )}
      </div>

      <div className="inc-xlabs">
        {cols.map((c, i) => (
          <div key={i} className={"inc-xlab" + (i === actualCount - 1 ? " now" : "") + (c.proj ? " proj" : "")}>
            {c.label}
          </div>
        ))}
      </div>
    </div>
  );
}

/* ============================================================
   FULL INCOME SCREEN  (the /income page body)
   ============================================================ */
const PERIOD_BTNS: [Period, string][] = [
  ["day", "Day"], ["week", "Week"], ["month", "Month"], ["quarter", "Quarter"], ["year", "Year"],
];
const UNIT_WORD: Record<Period, string> = { day: "days", week: "weeks", month: "months", quarter: "quarters", year: "year" };

export function IncomeScreen() {
  const navigate = useNavigate();
  const { data: trades = [] } = useIncomeTradesAll();
  const { data: sells = [] } = useShareSellsAll();
  const [period, setPeriod] = useState<Period>("week");

  const series = useMemo(() => buildSeries(period, trades, sells), [period, trades, sells]);
  const cur = series.actual[series.actual.length - 1] ?? { calls: 0, puts: 0, shares: 0, debit: 0, label: "", proj: false };

  const collected = cur.calls + cur.puts + cur.shares;
  const net = collected - cur.debit;
  const callPct = collected > 0 ? Math.round((cur.calls / collected) * 100) : 0;
  const putPct = collected > 0 ? Math.round((cur.puts / collected) * 100) : 0;
  const sharePct = collected > 0 ? Math.max(0, 100 - callPct - putPct) : 0;

  const projNet = series.proj.reduce((s, p) => s + p.calls + p.puts + p.shares - p.debit, 0);
  const trailNetAvg = series.actual.slice(-series.steps).reduce((s, p) => s + p.calls + p.puts + p.shares - p.debit, 0) / series.steps;
  const projNetAvg = projNet / Math.max(1, series.proj.length);
  const paceDelta = trailNetAvg ? Math.round(((projNetAvg - trailNetAvg) / trailNetAvg) * 100) : 0;

  const unitWord = UNIT_WORD[period];
  const brkRows: [string, string, number, number, string][] = [
    ["calls", "Calls sold", callPct, cur.calls, "var(--inc-calls)"],
    ["puts", "Puts sold", putPct, cur.puts, "var(--inc-puts)"],
    ["shares", "Shares · realized gains", sharePct, cur.shares, "var(--inc-shares)"],
  ];

  return (
    <div className="dash">
      <div className="dash-inner">
        <BrandBar
          routeLabel="Income"
          onPositions={() => { window.location.href = "https://positions.sunnyfi.co"; }}
          onStrategy={() => navigate("/new-strategy")}
          onMath={() => navigate("/math")}
        />

        {/* TITLE + PERIOD SWITCHER */}
        <div className="inc-titlerow">
          <div className="inc-title">
            <h1>Income</h1>
            <span className="period-label">{series.currentLabel}</span>
          </div>
          <div className="inc-seg" role="tablist">
            {PERIOD_BTNS.map(([k, lbl]) => (
              <button key={k} className={period === k ? "on" : ""} onClick={() => setPeriod(k)}>{lbl}</button>
            ))}
          </div>
        </div>

        {/* HEADER TOTALS */}
        <div className="inc-totals">
          <div className="inc-stat collected">
            <div className="cap"><span className="arrow neon">↑</span><span className="lbl">Collected</span></div>
            <div className="big"><MoneyCount value={collected} duration={1300} /></div>
            <div className="sub">{callPct}% calls · {putPct}% puts · {sharePct}% shares</div>
          </div>
          <div className="inc-stat debit">
            <div className="cap"><span className="arrow neg">↓</span><span className="lbl">Bought back</span></div>
            <div className="big"><MoneyCount value={cur.debit} sign="-" duration={1300} delay={120} /></div>
            <div className="sub">closing debits this {series.unit}</div>
          </div>
          <div className="inc-stat net">
            <div className="cap"><span className="lbl">Net premium kept</span></div>
            <div className="big"><MoneyCount value={net} duration={1300} delay={240} /></div>
            <div className="sub">collected − bought back</div>
          </div>
          <div style={{ marginLeft: "auto", alignSelf: "flex-end" }}>
            <div className="inc-legend">
              <span className="item"><span className="sw calls" />Calls</span>
              <span className="item"><span className="sw puts" />Puts</span>
              <span className="item"><span className="sw shares" />Shares</span>
              <span className="item"><span className="sw debit" />Bought back</span>
              <span className="item"><span className="sw proj" />Projected</span>
            </div>
          </div>
        </div>

        {/* CHART */}
        <div className="inc-chartblock">
          <Section right={series.currentLabel}>Premium flow</Section>
          <IncomeChart key={period} series={series} showProj />
        </div>

        {/* NET LINE */}
        <div className="inc-netline">
          <span className="lbl">Net premium kept this {series.unit}:</span>
          <span className="val">{fmtUSD(net)}</span>
          <span className="meta">{callPct}% from calls</span>
        </div>

        {/* LOWER: breakdown + projection */}
        <div className="inc-lower">
          <div className="inc-breakdown">
            <Section right={series.currentLabel}>Collected from</Section>
            {brkRows.map(([k, name, pct, amt, color]) => (
              <div className="brk-row" key={k}>
                <span className={"ico " + k} />
                <span className="pct">{pct}%</span>
                <span className="name">{name}</span>
                <span className="amt">{fmtUSD(amt)}</span>
                <div className="brk-meter">
                  <i style={{ width: `${pct}%`, background: color }} />
                </div>
              </div>
            ))}
            <div className="brk-row" style={{ gridTemplateColumns: "22px 64px 1fr auto" }}>
              <span className="ico" style={{ background: "var(--inc-debit)" }} />
              <span className="pct neg">−</span>
              <span className="name">Bought back / rolled</span>
              <span className="amt neg">−{fmtUSD(cur.debit)}</span>
            </div>
          </div>

          <div className="inc-proj-card">
            <Section right="weighted recent trend">Projected · next {series.steps} {unitWord}</Section>
            <div className="proj-big">{fmtUSD(projNet)}</div>
            <div className="proj-note">
              Net premium forecast across the next <span className="num-mono">{series.steps}</span> {unitWord}, weighting
              your most recent {unitWord} more heavily and holding the current call/put mix.
            </div>
            <div className="proj-pace">
              <div className="cell">
                <div className="k">Projected / {series.unit}</div>
                <div className="v">{fmtUSD(projNetAvg)}</div>
              </div>
              <div className="cell">
                <div className="k">Trailing / {series.unit}</div>
                <div className="v">{fmtUSD(trailNetAvg)}</div>
              </div>
              <div className="cell">
                <div className="k">Pace</div>
                <div className={"v" + (paceDelta >= 0 ? " pos" : "")} style={paceDelta < 0 ? { color: "var(--negative)" } : undefined}>
                  {paceDelta >= 0 ? "+" : "−"}{Math.abs(paceDelta)}%
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="row" style={{ marginTop: 56 }}>
          <ToolsRail />
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   COMPACT DASHBOARD BLOCK  (opens the full screen)
   ============================================================ */
export function IncomeWeekly({ compact = false }: { compact?: boolean }) {
  const navigate = useNavigate();
  const { data: trades = [] } = useIncomeTradesAll();
  const { data: sells = [] } = useShareSellsAll();
  const series = useMemo(() => buildSeries("week", trades, sells), [trades, sells]);

  const cols = [...series.actual.slice(-6), ...series.proj.slice(0, 2)];
  const scaleUp = niceMax(Math.max(...cols.map((c) => c.calls + c.puts + c.shares), 0));
  const scaleDown = niceMax(Math.max(...cols.map((c) => c.debit), 0));
  const cur = series.actual[series.actual.length - 1] ?? { calls: 0, puts: 0, shares: 0, debit: 0, label: "", proj: false };
  const collected = cur.calls + cur.puts + cur.shares;
  const net = collected - cur.debit;

  return (
    <div>
      <Section right={series.currentLabel}>Income · this week</Section>
      <div className="inc-mini">
        <div className="mini-stats">
          <div className="mini-stat">
            <div className="k">Collected</div>
            <div className="v neon" style={{ fontSize: compact ? 24 : 30 }}><MoneyCount value={collected} delay={150} /></div>
          </div>
          <div className="mini-stat">
            <div className="k">Bought back</div>
            <div className="v neg" style={{ fontSize: compact ? 18 : 22 }}><MoneyCount value={cur.debit} sign="-" delay={250} /></div>
          </div>
          <div className="mini-stat">
            <div className="k">Net kept</div>
            <div className="v" style={{ fontSize: compact ? 18 : 22, color: "var(--fg1)" }}><MoneyCount value={net} delay={350} /></div>
          </div>
        </div>

        <div className="mini-chart">
          <div className="mini-zero" style={{ top: `${UP_FRAC * 100}%` }} />
          {cols.map((c, i) => {
            const callsH = (c.calls / scaleUp) * 100;
            const putsH = (c.puts / scaleUp) * 100;
            const sharesH = (c.shares / scaleUp) * 100;
            const debitH = (c.debit / scaleDown) * 100;
            return (
              <div key={i} className={"mini-col" + (c.proj ? " proj" : "")}>
                <div className="mini-up" style={{ top: 0, bottom: `${DOWN_FRAC * 100}%` }}>
                  <div className="mini-seg shares" style={{ height: `${sharesH}%` }} />
                  <div className="mini-seg puts" style={{ height: `${putsH}%` }} />
                  <div className="mini-seg calls" style={{ height: `${callsH}%` }} />
                </div>
                <div className="mini-down" style={{ top: `${UP_FRAC * 100}%`, bottom: 0 }}>
                  <div className="mini-seg debit" style={{ height: `${debitH}%` }} />
                </div>
              </div>
            );
          })}
        </div>

        <div className="mini-foot">
          <span className="label">6 weeks + 2 projected · weighted trend</span>
          <button className="view-link" onClick={() => navigate("/income")}>View income →</button>
        </div>
      </div>
    </div>
  );
}
