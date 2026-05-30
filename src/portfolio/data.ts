/**
 * Master Positions — sample data + formatters + flag/aggregate compute.
 *
 * **PD-0 scaffold** — verbatim port of the handoff `mp-data.jsx`. The data
 * is hardcoded for now so we can land the design pixel-perfect before
 * wiring Massive.com (PD-1+2). One row per LEG (stock + each option),
 * grouped by COMPANY. Per-company aggregates are computed from the legs
 * so every number is internally consistent.
 *
 * Greeks on each leg are stored at POSITION level (already × contracts ×
 * 100), signed by side. Stock legs carry delta = shares, other greeks 0.
 */

export type LegKind = "stock" | "call" | "put";
export type LegSide = "long" | "short";
export type FlagTone = "neg" | "warn" | "pos";

export interface Leg {
  kind: LegKind;
  side?: LegSide;
  qty: number;           // shares OR signed contracts
  avg: number;
  last: number;
  day?: number;          // stock only
  unreal: number;
  real: number;
  delta: number;
  gamma: number;
  theta: number;
  vega: number;
  strike?: number;
  expiry?: string;
  dte?: number;
  iv?: number;
  ivr?: number;
  oi?: number;
  vol?: number;
  oiHist?: number[];
  volHist?: number[];
  oiChg?: number;
  volChg?: number;
}

export interface Flag {
  k: string;
  label: string;
  tone: FlagTone;
}

export interface CompanyEvent {
  kind: "earnings" | "exdiv" | "none";
  label: string;
  date: string;
  days: number;
}

export interface Aggregate {
  delta: number;
  gamma: number;
  theta: number;
  vega: number;
  unreal: number;
  real: number;
  mv: number;
  net: number;
}

export interface Company {
  t: string;
  name: string;
  sector: string;
  strat: "Income" | "Investment" | "Yield";
  spot: number;
  day: number;
  beta: number;
  event: CompanyEvent;
  legs: Leg[];
  flags200?: boolean;
  agg: Aggregate;
  flags: Flag[];
  sev: number;
  optLegs: number;
  closed?: boolean;
}

/* ---------------- formatters ---------------- */
export const fmtMoney = (v: number, sign?: boolean): string => {
  const a = Math.abs(Math.round(v));
  const s = sign ? (v > 0 ? "+" : v < 0 ? "−" : "") : (v < 0 ? "−" : "");
  return s + "$" + a.toLocaleString("en-US");
};
export const fmtK = (v: number): string => {
  const s = v < 0 ? "−" : "+";
  const a = Math.abs(v);
  if (a >= 1000) return s + "$" + (a / 1000).toFixed(a >= 10000 ? 0 : 1) + "k";
  // For sub-$1k values, show whole dollars (no decimals) — was leaking
  // float noise like "$437.99999999999995" when the source was a derived
  // P&L computation that drifted off a clean integer.
  return s + "$" + Math.round(a).toLocaleString("en-US");
};
export const fmtPct = (v: number): string =>
  (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toFixed(2) + "%";
export const fmtNum = (v: number, d = 0): string =>
  (v > 0 ? "+" : v < 0 ? "−" : "") +
  Math.abs(v).toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d });
/** Greeks display — always rounded to whole-number shares-equivalent.
 *  Polygon returns per-share Δ to 4-6 decimals; once multiplied by
 *  contracts × 100, we end up with values like 808.049 that aren't
 *  meaningfully precise — round at the display boundary. */
export const fmtGreek = (v: number): string =>
  (v > 0 ? "+" : v < 0 ? "−" : "") + Math.round(Math.abs(v)).toLocaleString("en-US");
export const signCls = (v: number): "pos" | "neg" | "fg3" =>
  v > 0 ? "pos" : v < 0 ? "neg" : "fg3";

/* relative dates — base = Fri May 29 (day 0). Matches the handoff sample. */
const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const BASE_DOW = 5; // Friday
export function relExpiry(dte: number | null | undefined): string | null {
  if (dte == null) return null;
  if (dte === 0) return "today";
  if (dte === 1) return "tom'w";
  if (dte <= 6) return DOW[(BASE_DOW + dte) % 7];
  return dte + "d";
}
export function relDays(days: number): string {
  if (days === 0) return "today";
  if (days === 1) return "tomorrow";
  if (days <= 6) return "in " + days + "d";
  const wk = Math.round(days / 7);
  return "in " + wk + " wk" + (wk > 1 ? "s" : "");
}
export const eventText = (c: Company): string =>
  c.event.kind === "none"
    ? c.event.label + " " + c.event.date
    : c.event.label + " · " + relDays(c.event.days);
export const eventFar = (c: Company): boolean =>
  c.event.kind === "none" || c.event.days > 14;

/* ---------------- raw dataset (handoff verbatim) ---------------- */
const COMPANIES_RAW: Omit<Company, "agg" | "flags" | "sev" | "optLegs">[] = [
  {
    t: "META", name: "Meta Platforms", sector: "Comm Svcs", strat: "Income",
    spot: 641.20, day: 0.81, beta: 1.21,
    event: { kind: "earnings", label: "Earnings", date: "Jun 2", days: 6 },
    legs: [
      { kind: "stock", qty: 2000, avg: 611.91, last: 641.20, day: 0.81, unreal: 58580, real: 24541, delta: 2000, gamma: 0, theta: 0, vega: 0 },
      { kind: "call", side: "short", qty: -10, avg: 3.40, last: 2.10, unreal: 1300, real: 0, delta: -320, gamma: -14, theta: 182, vega: -410, strike: 660, expiry: "Jun 20", dte: 24, iv: 27.8, ivr: 36, oi: 12400 },
      { kind: "put",  side: "long",  qty: 15,  avg: 8.10, last: 6.80, unreal: -1950, real: 0, delta: -345, gamma: 18, theta: -126, vega: 540, strike: 600, expiry: "Jul 18", dte: 52, iv: 29.6, ivr: 41, oi: 8200 },
    ],
  },
  {
    t: "INTU", name: "Intuit", sector: "Technology", strat: "Income",
    spot: 642.30, day: 0.42, beta: 1.18,
    event: { kind: "earnings", label: "Earnings", date: "Jun 3", days: 5 },
    legs: [
      { kind: "stock", qty: 400, avg: 538.20, last: 642.30, day: 0.42, unreal: 41640, real: 18900, delta: 400, gamma: 0, theta: 0, vega: 0 },
      { kind: "call", side: "short", qty: -4, avg: 6.20, last: 9.20, unreal: -1200, real: 0, delta: -312, gamma: -9, theta: 220, vega: -180, strike: 645, expiry: "Jun 6", dte: 5, iv: 44.2, ivr: 72, oi: 3100 },
    ],
  },
  {
    t: "NVDA", name: "NVIDIA", sector: "Technology", strat: "Investment",
    spot: 880.40, day: 1.24, beta: 1.62,
    event: { kind: "earnings", label: "Earnings", date: "Jun 11", days: 12 },
    legs: [
      { kind: "stock", qty: 300, avg: 612.10, last: 880.40, day: 1.24, unreal: 80490, real: 4820, delta: 300, gamma: 0, theta: 0, vega: 0 },
      { kind: "call", side: "short", qty: -3, avg: 12.80, last: 14.50, unreal: -510, real: 0, delta: -111, gamma: -6, theta: 96, vega: -240, strike: 920, expiry: "Jun 20", dte: 24, iv: 41.0, ivr: 55, oi: 9800 },
    ],
  },
  {
    t: "HOOD", name: "Robinhood", sector: "Financials", strat: "Yield",
    spot: 78.90, day: 2.91, beta: 1.44,
    event: { kind: "exdiv", label: "Ex-div", date: "Jun 27", days: 29 },
    legs: [
      { kind: "stock", qty: 1000, avg: 41.20, last: 78.90, day: 2.91, unreal: 37700, real: 620, delta: 1000, gamma: 0, theta: 0, vega: 0 },
      { kind: "put",  side: "short", qty: -10, avg: 1.85, last: 1.10, unreal: 750, real: 0, delta: 220, gamma: -8, theta: 140, vega: -160, strike: 72, expiry: "Jun 13", dte: 17, iv: 52.3, ivr: 61, oi: 5400 },
    ],
  },
  {
    t: "ADBE", name: "Adobe", sector: "Technology", strat: "Investment",
    spot: 238.24, day: -0.94, beta: 1.25,
    event: { kind: "earnings", label: "Earnings", date: "Jun 12", days: 14 },
    flags200: true,
    legs: [
      { kind: "stock", qty: 300, avg: 282.11, last: 238.24, day: -0.94, unreal: -13161, real: 0, delta: 300, gamma: 0, theta: 0, vega: 0 },
      { kind: "call", side: "short", qty: -3, avg: 4.40, last: 3.10, unreal: 390, real: 0, delta: -84, gamma: -5, theta: 72, vega: -150, strike: 250, expiry: "Jun 20", dte: 24, iv: 36.5, ivr: 48, oi: 4200 },
      { kind: "put",  side: "long",  qty: 5,  avg: 8.60, last: 7.40, unreal: -600, real: 0, delta: -160, gamma: 9, theta: -90, vega: 280, strike: 230, expiry: "Jul 18", dte: 52, iv: 38.1, ivr: 51, oi: 2600 },
    ],
  },
  {
    t: "NKE", name: "Nike", sector: "Cons Disc", strat: "Income",
    spot: 46.10, day: -0.41, beta: 0.98,
    event: { kind: "earnings", label: "Earnings", date: "Jun 26", days: 28 },
    flags200: true,
    legs: [
      { kind: "stock", qty: 1000, avg: 51.20, last: 46.10, day: -0.41, unreal: -5100, real: -4560, delta: 1000, gamma: 0, theta: 0, vega: 0 },
      { kind: "call", side: "short", qty: -10, avg: 0.95, last: 0.60, unreal: 350, real: 0, delta: -180, gamma: -11, theta: 90, vega: -130, strike: 50, expiry: "Jun 20", dte: 24, iv: 31.2, ivr: 33, oi: 6100 },
    ],
  },
];

/* ---------------- leg labels / glyphs ---------------- */
export function legLabel(l: Leg): { glyph: string; tone: string; main: string; side: string } {
  if (l.kind === "stock") return { glyph: "S", tone: "stock", main: "Common stock", side: "" };
  const letter = l.kind === "call" ? "C" : "P";
  const tone = l.side === "short"
    ? (l.kind === "call" ? "c-short" : "p-short")
    : (l.kind === "call" ? "c-long" : "p-long");
  return { glyph: letter, tone, main: "$" + l.strike + " " + (l.kind === "call" ? "call" : "put"), side: l.side ?? "" };
}

/* ---------------- compute flags ---------------- */
function computeFlags(c: Omit<Company, "agg" | "flags" | "sev" | "optLegs">): Flag[] {
  const flags: Flag[] = [];
  c.legs.forEach((l) => {
    if (l.side === "short" && l.kind === "call" && l.dte != null && l.dte <= 21 && l.strike != null) {
      const moneyness = (c.spot - l.strike) / l.strike;
      const callDelta = Math.abs(l.delta / (Math.abs(l.qty) * 100));
      if (moneyness > -0.02) flags.push({ k: "assign", label: "assignment risk", tone: "neg" });
      if (callDelta >= 0.75) flags.push({ k: "delta", label: "Δ " + callDelta.toFixed(2) + " · roll", tone: "neg" });
    }
  });
  const hasShortOpt = c.legs.some((l) => l.side === "short" && (l.kind === "call" || l.kind === "put"));
  if (c.event.kind === "earnings" && c.event.days <= 7 && hasShortOpt) {
    flags.push({ k: "crush", label: "IV crush " + c.event.days + "d", tone: "warn" });
  }
  if (c.event.kind === "earnings" && c.event.days <= 14) {
    flags.push({ k: "earn", label: "earnings " + c.event.days + "d", tone: "warn" });
  }
  if (c.flags200) flags.push({ k: "below", label: "below 200d", tone: "neg" });
  if (Math.abs(c.day) >= 2.5) flags.push({ k: "move", label: "big move", tone: c.day > 0 ? "pos" : "neg" });
  const seen: Record<string, true> = {};
  return flags.filter((f) => (seen[f.k] ? false : (seen[f.k] = true)));
}

/* ---------------- model build ---------------- */
function buildModel(): Company[] {
  return COMPANIES_RAW.map((c) => {
    c.legs.forEach((l) => {
      if (l.oi) {
        const seed = (l.strike ?? 7) % 5;
        l.vol = Math.round(l.oi * (0.20 + (seed + 1) * 0.05));
        l.oiHist = [Math.round(l.oi * 0.92), Math.round(l.oi * 0.965), Math.round(l.oi * (0.97 + seed * 0.006)), l.oi];
        l.volHist = [Math.round(l.vol * 1.12), Math.round(l.vol * 0.82), Math.round(l.vol * (1.05 + seed * 0.03)), l.vol];
        l.oiChg = (l.oi - l.oiHist[2]) / l.oiHist[2];
        l.volChg = (l.vol - l.volHist[2]) / l.volHist[2];
      }
    });
    const agg: Aggregate = c.legs.reduce<Aggregate>((a, l) => ({
      delta: a.delta + l.delta, gamma: a.gamma + l.gamma,
      theta: a.theta + l.theta, vega: a.vega + l.vega,
      unreal: a.unreal + l.unreal, real: a.real + l.real,
      mv: a.mv + (l.kind === "stock" ? l.qty * l.last : 0),
      net: 0,
    }), { delta: 0, gamma: 0, theta: 0, vega: 0, unreal: 0, real: 0, mv: 0, net: 0 });
    agg.net = agg.unreal + agg.real;
    const flags = computeFlags(c);
    const sev = flags.reduce((s, f) => s + (f.tone === "neg" ? 3 : f.tone === "warn" ? 2 : 1), 0);
    return { ...c, agg, flags, sev, optLegs: c.legs.filter((l) => l.kind !== "stock").length };
  });
}

export const MODEL: Company[] = buildModel();

/* ---------------- closed (hidden by default) ---------------- */
export const CLOSED: Company[] = [
  {
    t: "PYPL", name: "PayPal", sector: "Financials", strat: "Yield", closed: true,
    spot: 71.40, day: 0, beta: 1.0,
    event: { kind: "none", label: "Closed", date: "May 16", days: 999 },
    legs: [], flags: [], optLegs: 0, sev: 0,
    agg: { delta: 0, gamma: 0, theta: 0, vega: 0, unreal: 0, real: 8420, net: 8420, mv: 0 },
  },
  {
    t: "SHOP", name: "Shopify", sector: "Technology", strat: "Income", closed: true,
    spot: 112.80, day: 0, beta: 1.0,
    event: { kind: "none", label: "Called away", date: "May 9", days: 999 },
    legs: [], flags: [], optLegs: 0, sev: 0,
    agg: { delta: 0, gamma: 0, theta: 0, vega: 0, unreal: 0, real: 3160, net: 3160, mv: 0 },
  },
];

/* ---------------- portfolio rollup ---------------- */
export interface Portfolio {
  delta: number; gamma: number; theta: number; vega: number;
  unreal: number; real: number; net: number; mv: number;
  legs: number; opts: number; companies: number;
  maxAbsDelta: number;
}
export const PORTFOLIO: Portfolio = (() => {
  const p = MODEL.reduce((a, c) => ({
    delta: a.delta + c.agg.delta, gamma: a.gamma + c.agg.gamma,
    theta: a.theta + c.agg.theta, vega: a.vega + c.agg.vega,
    unreal: a.unreal + c.agg.unreal, real: a.real + c.agg.real, mv: a.mv + c.agg.mv,
    legs: a.legs + c.legs.length, opts: a.opts + c.optLegs,
  }), { delta: 0, gamma: 0, theta: 0, vega: 0, unreal: 0, real: 0, mv: 0, legs: 0, opts: 0 });
  return {
    ...p,
    net: p.unreal + p.real,
    companies: MODEL.length,
    maxAbsDelta: Math.max(...MODEL.map((c) => Math.abs(c.agg.delta))),
  };
})();

export const BETA_DELTA = Math.round(MODEL.reduce((s, c) => s + c.agg.delta * (c.beta || 0), 0));

/* scale for delta bars — widest leg across the book */
export const LEG_MAX = Math.max(...MODEL.flatMap((c) => c.legs.map((l) => Math.abs(l.delta))), 1);
