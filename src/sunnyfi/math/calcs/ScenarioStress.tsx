/**
 * Math — Scenario & Stress.
 *
 * Stress the user's LIVE book against a market move. Four factor sliders:
 *   • SPY  — broad market shock %
 *   • QQQ  — tech-heavy shock %. The tech residual = QQQ − SPY drives
 *            the "tech extra" beta on names like NVDA, AVGO, etc.
 *   • USD  — DXY shock %. Hurts multinational revenue (Apple, Broadcom).
 *   • 10Y  — rate shock in bps. Long-duration growth stocks pay; banks gain.
 *
 * One "WHEN" pill row picks how far forward the scenario fires — today, +30d,
 * +60d, +90d, +2y. That's purely for option theta: stock model is time-blind.
 *
 * Tail amplification: when |SPY| ≥ 15%, effective beta is multiplied by 1.3
 * to reflect correlation spikes in real crashes.
 *
 * Output: today→scenario book value + leg attribution (stock vs option) +
 * top movers + sector hit. Puts paying off (the hedge) is the headline.
 *
 * No live Polygon calls — options re-priced from the same estPremium()
 * estimator used elsewhere, with each ticker's 1y-baseline IV. Stocks
 * repriced via per-ticker MacroProfile (hand-curated for top names,
 * sector defaults beyond).
 */
import { useMemo, type ReactNode } from "react";
import { fmtMoney, fmtPct } from "../cycle";
import { usePositions } from "../../../positions/usePositions";
import type { LiveOption, Sector } from "../../../positions/types";
import "./ScenarioStress.css";

// ── Factor profile per ticker ────────────────────────────────────
interface MacroProfile {
  /** Beta vs SPY, 1y rolling baseline. Multiplied by SPY shock. */
  marketBeta: number;
  /** Additional beta to (QQQ − SPY). 0 for non-tech, ~0.3–0.7 for mega tech. */
  techExtra: number;
  /** Share of revenue from outside the US (0..1). Stronger USD = headwind. */
  fxExposure: number;
  /** % move per +100bps in 10Y. Negative = rate-sensitive long-duration. */
  rateBeta: number;
}

/** Hand-curated beta + factor exposures for the ~40 most-traded names.
 *  Anything outside this map falls back to a sector default. Numbers are
 *  approximate 1y rolling-regression values — meant for stress sketching,
 *  not portfolio risk-system accuracy. */
const MACRO_HINTS: Record<string, MacroProfile> = {
  // Indexes — useful when users hold the ETF itself
  SPY:   { marketBeta: 1.00, techExtra: 0.00, fxExposure: 0.40, rateBeta: -0.3 },
  QQQ:   { marketBeta: 1.00, techExtra: 1.00, fxExposure: 0.50, rateBeta: -0.5 },
  IWM:   { marketBeta: 1.15, techExtra: -0.20, fxExposure: 0.15, rateBeta: 0.1 },
  DIA:   { marketBeta: 0.90, techExtra: -0.15, fxExposure: 0.35, rateBeta: -0.2 },

  // Mega-cap tech
  AAPL:  { marketBeta: 1.25, techExtra: 0.30, fxExposure: 0.55, rateBeta: -0.5 },
  MSFT:  { marketBeta: 0.93, techExtra: 0.40, fxExposure: 0.50, rateBeta: -0.4 },
  NVDA:  { marketBeta: 1.70, techExtra: 0.60, fxExposure: 0.55, rateBeta: -0.7 },
  GOOGL: { marketBeta: 1.05, techExtra: 0.35, fxExposure: 0.55, rateBeta: -0.4 },
  AMZN:  { marketBeta: 1.16, techExtra: 0.35, fxExposure: 0.30, rateBeta: -0.4 },
  META:  { marketBeta: 1.21, techExtra: 0.40, fxExposure: 0.55, rateBeta: -0.4 },
  AVGO:  { marketBeta: 1.40, techExtra: 0.55, fxExposure: 0.70, rateBeta: -0.5 },
  TSLA:  { marketBeta: 2.30, techExtra: 0.40, fxExposure: 0.45, rateBeta: -0.6 },
  TSM:   { marketBeta: 1.40, techExtra: 0.55, fxExposure: 0.95, rateBeta: -0.5 },
  AMD:   { marketBeta: 1.85, techExtra: 0.55, fxExposure: 0.45, rateBeta: -0.7 },
  INTC:  { marketBeta: 1.00, techExtra: 0.30, fxExposure: 0.40, rateBeta: -0.4 },
  NFLX:  { marketBeta: 1.10, techExtra: 0.30, fxExposure: 0.40, rateBeta: -0.3 },
  CRM:   { marketBeta: 1.30, techExtra: 0.40, fxExposure: 0.30, rateBeta: -0.5 },
  ORCL:  { marketBeta: 0.95, techExtra: 0.30, fxExposure: 0.45, rateBeta: -0.3 },
  ADBE:  { marketBeta: 1.25, techExtra: 0.40, fxExposure: 0.45, rateBeta: -0.5 },
  INTU:  { marketBeta: 1.15, techExtra: 0.35, fxExposure: 0.05, rateBeta: -0.4 },
  WDAY:  { marketBeta: 1.30, techExtra: 0.40, fxExposure: 0.20, rateBeta: -0.5 },
  SHOP:  { marketBeta: 2.50, techExtra: 0.60, fxExposure: 0.35, rateBeta: -0.7 },
  COIN:  { marketBeta: 3.00, techExtra: 0.60, fxExposure: 0.20, rateBeta: -0.8 },
  PLTR:  { marketBeta: 2.50, techExtra: 0.50, fxExposure: 0.15, rateBeta: -0.7 },
  PYPL:  { marketBeta: 1.40, techExtra: 0.35, fxExposure: 0.40, rateBeta: -0.5 },

  // Communication / discretionary
  HD:    { marketBeta: 1.00, techExtra: 0.00, fxExposure: 0.10, rateBeta: -0.3 },
  NKE:   { marketBeta: 1.00, techExtra: 0.00, fxExposure: 0.55, rateBeta: -0.2 },
  BBY:   { marketBeta: 1.20, techExtra: 0.00, fxExposure: 0.05, rateBeta: -0.3 },
  WMT:   { marketBeta: 0.55, techExtra: 0.00, fxExposure: 0.25, rateBeta: -0.1 },

  // Financials — positive rate beta
  JPM:   { marketBeta: 1.10, techExtra: 0.00, fxExposure: 0.20, rateBeta:  0.3 },
  BAC:   { marketBeta: 1.20, techExtra: 0.00, fxExposure: 0.10, rateBeta:  0.4 },
  WFC:   { marketBeta: 1.10, techExtra: 0.00, fxExposure: 0.05, rateBeta:  0.4 },
  GS:    { marketBeta: 1.30, techExtra: 0.00, fxExposure: 0.30, rateBeta:  0.3 },
  HOOD:  { marketBeta: 2.50, techExtra: 0.40, fxExposure: 0.00, rateBeta:  0.2 },
  MORN:  { marketBeta: 0.90, techExtra: 0.10, fxExposure: 0.30, rateBeta: -0.3 },

  // Healthcare
  JNJ:   { marketBeta: 0.55, techExtra: 0.00, fxExposure: 0.50, rateBeta: -0.2 },
  LLY:   { marketBeta: 0.50, techExtra: 0.00, fxExposure: 0.40, rateBeta: -0.2 },
  UNH:   { marketBeta: 0.65, techExtra: 0.00, fxExposure: 0.05, rateBeta: -0.1 },
  PFE:   { marketBeta: 0.60, techExtra: 0.00, fxExposure: 0.50, rateBeta: -0.1 },

  // Energy
  XOM:   { marketBeta: 0.90, techExtra: 0.00, fxExposure: 0.20, rateBeta:  0.1 },
  CVX:   { marketBeta: 1.00, techExtra: 0.00, fxExposure: 0.25, rateBeta:  0.1 },

  // Other commonly held
  IT:    { marketBeta: 1.00, techExtra: 0.20, fxExposure: 0.40, rateBeta: -0.3 },
  FIG:   { marketBeta: 1.50, techExtra: 0.30, fxExposure: 0.40, rateBeta: -0.4 },
};

/** Sector-level fallback for unknown tickers. Approximate "typical" profiles
 *  for each sector — close enough for stress sketching when a hardcoded
 *  entry is missing. */
const SECTOR_DEFAULTS: Record<Sector, MacroProfile> = {
  "Technology":               { marketBeta: 1.20, techExtra: 0.40, fxExposure: 0.45, rateBeta: -0.5 },
  "Healthcare":               { marketBeta: 0.70, techExtra: 0.00, fxExposure: 0.35, rateBeta: -0.2 },
  "Financials":               { marketBeta: 1.15, techExtra: 0.00, fxExposure: 0.15, rateBeta:  0.3 },
  "Consumer Discretionary":   { marketBeta: 1.10, techExtra: 0.05, fxExposure: 0.25, rateBeta: -0.3 },
  "Consumer Staples":         { marketBeta: 0.60, techExtra: 0.00, fxExposure: 0.30, rateBeta: -0.1 },
  "Energy":                   { marketBeta: 1.00, techExtra: 0.00, fxExposure: 0.25, rateBeta:  0.1 },
  "Industrials":              { marketBeta: 1.05, techExtra: 0.05, fxExposure: 0.30, rateBeta: -0.2 },
  "Materials":                { marketBeta: 1.10, techExtra: 0.00, fxExposure: 0.40, rateBeta: -0.1 },
  "Utilities":                { marketBeta: 0.50, techExtra: 0.00, fxExposure: 0.05, rateBeta: -0.4 },
  "Real Estate":              { marketBeta: 0.90, techExtra: 0.00, fxExposure: 0.05, rateBeta: -0.6 },
  "Communication Services":   { marketBeta: 1.05, techExtra: 0.20, fxExposure: 0.40, rateBeta: -0.3 },
  "Other":                    { marketBeta: 1.00, techExtra: 0.00, fxExposure: 0.20, rateBeta: -0.2 },
};

/** Resolve the macro profile for a ticker. Returns the curated value when
 *  available, otherwise the sector default. The second-tuple element flags
 *  whether the result came from the table (true) or the sector fallback. */
function profileFor(ticker: string, sector: Sector): { profile: MacroProfile; curated: boolean } {
  const hit = MACRO_HINTS[ticker?.toUpperCase()];
  if (hit) return { profile: hit, curated: true };
  return { profile: SECTOR_DEFAULTS[sector] ?? SECTOR_DEFAULTS.Other, curated: false };
}

/** Baseline IV for the option-leg re-pricing. Mirrors IV_HINTS in
 *  IncomeVsCost.tsx — kept in sync because both calcs are sketches. */
const IV_HINTS: Record<string, number> = {
  SPY: 0.18, QQQ: 0.22, IWM: 0.25, AAPL: 0.25, NVDA: 0.45, TSLA: 0.55,
  META: 0.32, MSFT: 0.22, AMZN: 0.30, GOOGL: 0.26, AMD: 0.50, COIN: 0.70,
  AVGO: 0.32, TSM: 0.32, NFLX: 0.32, CRM: 0.30, ADBE: 0.28, INTU: 0.28,
  PYPL: 0.40, SHOP: 0.55, PLTR: 0.60, HOOD: 0.70, JPM: 0.22, BAC: 0.28,
  JNJ: 0.18, LLY: 0.28, UNH: 0.22, XOM: 0.25, NKE: 0.28, BBY: 0.32,
  WDAY: 0.32, INTC: 0.40, ORCL: 0.25, IT: 0.30, FIG: 0.40,
};
const IV_DEFAULT = 0.32;
const ivFor = (ticker: string): number => IV_HINTS[ticker?.toUpperCase()] ?? IV_DEFAULT;

// ── State ────────────────────────────────────────────────────────
export interface ScnState extends Record<string, unknown> {
  spyShock: number;    // percent, e.g. -10 means SPY drops 10%
  qqqShock: number;    // percent
  usdShock: number;    // percent
  rateShock: number;   // basis points, e.g. +100
  whenDays: number;    // 0 (today), 30, 60, 90, 730 (2y)
}

export const scnInitial: ScnState = {
  spyShock: 0,
  qqqShock: 0,
  usdShock: 0,
  rateShock: 0,
  whenDays: 0,
};

const TIME_OPTIONS = [
  { id: 0,   label: "today" },
  { id: 30,  label: "+30d"  },
  { id: 60,  label: "+60d"  },
  { id: 90,  label: "+90d"  },
  { id: 730, label: "+2y"   },
] as const;

const TAIL_AMP_THRESHOLD = 15;   // |SPY| ≥ 15% triggers
const TAIL_AMP_FACTOR = 1.3;     // betas multiplied by this in tail mode

// ── Estimator (mirror of estPremium in IncomeVsCost) ─────────────
/** Black-Scholes-ish ATM-time-value premium with simple skew. Handles
 *  expired options (T ≤ 0) by returning intrinsic value only. */
function premAt(opts: { spot: number; strike: number; daysToExp: number; iv: number; isCall: boolean }): number {
  const { spot, strike, daysToExp, iv, isCall } = opts;
  if (!isFinite(spot) || !isFinite(strike) || spot <= 0) return 0;
  const intrinsic = isCall ? Math.max(0, spot - strike) : Math.max(0, strike - spot);
  if (daysToExp <= 0) return intrinsic;
  const T = daysToExp / 365;
  const sqrtT = Math.sqrt(T);
  const atmTV = 0.4 * spot * iv * sqrtT;
  const moneyness = (strike - spot) / spot;
  const otmAmt = isCall ? Math.max(0, moneyness) : Math.max(0, -moneyness);
  const skew = Math.exp(-(otmAmt / Math.max(0.01, iv * sqrtT)) * 1.6);
  return Math.max(0.05, intrinsic + atmTV * skew);
}

function daysBetween(fromIso: string, toIso: string): number {
  const a = new Date(fromIso + "T00:00:00Z").getTime();
  const b = new Date(toIso   + "T00:00:00Z").getTime();
  return Math.round((b - a) / 86400000);
}

// ── Scenario compute ─────────────────────────────────────────────
export interface PositionDelta {
  ticker: string;
  sector: Sector;
  curated: boolean;
  effectiveBeta: number;
  todayPrice: number;
  scenarioPrice: number;
  shares: number;
  stockTodayValue: number;
  stockScenarioValue: number;
  stockDelta: number;
  optionTodayValue: number;     // net (long − short) value to the trader
  optionScenarioValue: number;
  optionDelta: number;
  // breakdown of the option delta by leg type, for the headline tile
  longPutDelta: number;
  longCallDelta: number;
  shortCallDelta: number;
  shortPutDelta: number;
  totalDelta: number;           // stockDelta + optionDelta
}

export interface ScenarioResult {
  totals: {
    bookTodayStock: number;
    bookScenarioStock: number;
    stockDelta: number;
    longPutDelta: number;
    longCallDelta: number;
    shortCallDelta: number;
    shortPutDelta: number;
    optionDelta: number;
    bookTodayTotal: number;       // stock today + net option value today
    bookScenarioTotal: number;
    netDelta: number;             // stockDelta + optionDelta
  };
  positions: PositionDelta[];
  /** Sector → sum of totalDelta. */
  sectorHits: Array<{ sector: Sector; delta: number }>;
  tailMode: boolean;
  shockedAt: number;              // days forward used
}

interface RawPosition {
  ticker: string;
  sector: Sector;
  quantity: number;
  current_price: number | null;
}

export function computeScenario(
  positions: RawPosition[],
  liveByTicker: Map<string, LiveOption[]>,
  state: ScnState,
  todayIso: string = new Date().toISOString().slice(0, 10),
): ScenarioResult {
  const tail = Math.abs(state.spyShock) >= TAIL_AMP_THRESHOLD;
  const amp = tail ? TAIL_AMP_FACTOR : 1;

  const deltas: PositionDelta[] = [];

  for (const p of positions) {
    if (!p.current_price || p.current_price <= 0) continue;
    if (!p.quantity || p.quantity === 0) continue;

    const { profile, curated } = profileFor(p.ticker, p.sector);
    const effBeta = profile.marketBeta * amp;
    const effTech = profile.techExtra * amp;

    // Return as decimal, summed across factor channels.
    const spyR = (effBeta * state.spyShock) / 100;
    const techR = (effTech * (state.qqqShock - state.spyShock)) / 100;
    const fxR = (-profile.fxExposure * state.usdShock) / 100;
    const rateR = (profile.rateBeta * state.rateShock) / 10000;  // bps → decimal
    const stockReturn = spyR + techR + fxR + rateR;

    const todayPrice = p.current_price;
    const scenarioPrice = Math.max(0.01, todayPrice * (1 + stockReturn));

    const stockTodayValue = p.quantity * todayPrice;
    const stockScenarioValue = p.quantity * scenarioPrice;
    const stockDelta = stockScenarioValue - stockTodayValue;

    // Options leg
    let optionTodayValue = 0;
    let optionScenarioValue = 0;
    let longPutDelta = 0;
    let longCallDelta = 0;
    let shortCallDelta = 0;
    let shortPutDelta = 0;

    const opts = liveByTicker.get(p.ticker) ?? [];
    const iv = ivFor(p.ticker);
    for (const lo of opts) {
      const opt = lo.open;
      const contracts = lo.remaining_contracts;
      if (contracts <= 0) continue;
      const originalDte = Math.max(0, daysBetween(todayIso, opt.expiry));
      const scenarioDte = Math.max(0, originalDte - state.whenDays);
      const isCall = opt.option_type === "call";
      const sign = opt.direction === "long" ? 1 : -1;

      const premToday = premAt({
        spot: todayPrice,
        strike: opt.strike,
        daysToExp: originalDte,
        iv,
        isCall,
      });
      const premScen = premAt({
        spot: scenarioPrice,
        strike: opt.strike,
        daysToExp: scenarioDte,
        iv,
        isCall,
      });
      const todayVal = sign * premToday * 100 * contracts;
      const scenVal  = sign * premScen  * 100 * contracts;
      const legDelta = scenVal - todayVal;
      optionTodayValue += todayVal;
      optionScenarioValue += scenVal;

      if (isCall && sign > 0) longCallDelta += legDelta;
      else if (isCall && sign < 0) shortCallDelta += legDelta;
      else if (!isCall && sign > 0) longPutDelta += legDelta;
      else shortPutDelta += legDelta;
    }

    const optionDelta = optionScenarioValue - optionTodayValue;
    const totalDelta = stockDelta + optionDelta;

    deltas.push({
      ticker: p.ticker,
      sector: p.sector,
      curated,
      effectiveBeta: effBeta,
      todayPrice,
      scenarioPrice,
      shares: p.quantity,
      stockTodayValue,
      stockScenarioValue,
      stockDelta,
      optionTodayValue,
      optionScenarioValue,
      optionDelta,
      longPutDelta,
      longCallDelta,
      shortCallDelta,
      shortPutDelta,
      totalDelta,
    });
  }

  // Totals
  const totals = {
    bookTodayStock: 0,
    bookScenarioStock: 0,
    stockDelta: 0,
    longPutDelta: 0,
    longCallDelta: 0,
    shortCallDelta: 0,
    shortPutDelta: 0,
    optionDelta: 0,
    bookTodayTotal: 0,
    bookScenarioTotal: 0,
    netDelta: 0,
  };
  for (const d of deltas) {
    totals.bookTodayStock += d.stockTodayValue;
    totals.bookScenarioStock += d.stockScenarioValue;
    totals.stockDelta += d.stockDelta;
    totals.longPutDelta += d.longPutDelta;
    totals.longCallDelta += d.longCallDelta;
    totals.shortCallDelta += d.shortCallDelta;
    totals.shortPutDelta += d.shortPutDelta;
    totals.optionDelta += d.optionDelta;
    totals.bookTodayTotal += d.stockTodayValue + d.optionTodayValue;
    totals.bookScenarioTotal += d.stockScenarioValue + d.optionScenarioValue;
    totals.netDelta += d.totalDelta;
  }

  // Sector hits
  const bySector = new Map<Sector, number>();
  for (const d of deltas) {
    bySector.set(d.sector, (bySector.get(d.sector) ?? 0) + d.totalDelta);
  }
  const sectorHits = [...bySector.entries()]
    .map(([sector, delta]) => ({ sector, delta }))
    .sort((a, b) => a.delta - b.delta);  // most-negative first

  return { totals, positions: deltas, sectorHits, tailMode: tail, shockedAt: state.whenDays };
}

// ── Snapshot registry helpers ────────────────────────────────────
export function scnDisplay(state: ScnState): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const any = state.spyShock || state.qqqShock || state.usdShock || state.rateShock;
  if (!any) return { value: "—", tone: "muted" };
  // We can't compute totals here without positions; just show the SPY shock.
  return { value: `SPY ${state.spyShock >= 0 ? "+" : ""}${state.spyShock}%`, tone: state.spyShock < 0 ? "neg" : "pos" };
}

export function scnCopy(state: ScnState): string {
  const parts: string[] = [];
  if (state.spyShock) parts.push(`SPY ${state.spyShock >= 0 ? "+" : ""}${state.spyShock}%`);
  if (state.qqqShock) parts.push(`QQQ ${state.qqqShock >= 0 ? "+" : ""}${state.qqqShock}%`);
  if (state.usdShock) parts.push(`USD ${state.usdShock >= 0 ? "+" : ""}${state.usdShock}%`);
  if (state.rateShock) parts.push(`10Y ${state.rateShock >= 0 ? "+" : ""}${state.rateShock}bp`);
  if (state.whenDays) {
    const w = TIME_OPTIONS.find((t) => t.id === state.whenDays);
    if (w) parts.push(w.label);
  }
  return parts.length > 0 ? `Scenario · ${parts.join(" · ")}` : "Scenario · (no shock)";
}

export function scnFields(state: ScnState): Array<{ label: string; value: string; mono?: boolean }> {
  return [
    { label: "SPY",  value: `${state.spyShock >= 0 ? "+" : ""}${state.spyShock}%`,  mono: true },
    { label: "QQQ",  value: `${state.qqqShock >= 0 ? "+" : ""}${state.qqqShock}%`,  mono: true },
    { label: "USD",  value: `${state.usdShock >= 0 ? "+" : ""}${state.usdShock}%`,  mono: true },
    { label: "10Y",  value: `${state.rateShock >= 0 ? "+" : ""}${state.rateShock}bp`, mono: true },
    { label: "When", value: TIME_OPTIONS.find((t) => t.id === state.whenDays)?.label ?? "today", mono: true },
  ];
}

// ── Main component ───────────────────────────────────────────────
export function ScenarioStressCalc({
  state,
  setState,
}: {
  state: ScnState;
  setState: (next: ScnState | ((prev: ScnState) => ScnState)) => void;
}) {
  const { portfolio, isLoading } = usePositions();

  // Map portfolio rows to the lightweight shape computeScenario expects,
  // plus a quick lookup for per-position live options.
  const raw: RawPosition[] = useMemo(
    () =>
      (portfolio ?? [])
        .filter((p) => p.status === "open")
        .map((p) => ({
          ticker: p.ticker,
          sector: p.sector,
          quantity: p.quantity,
          current_price: p.current_price,
        })),
    [portfolio],
  );
  const liveByTicker = useMemo(() => {
    const m = new Map<string, LiveOption[]>();
    for (const p of portfolio ?? []) m.set(p.ticker, p.live_options);
    return m;
  }, [portfolio]);

  const result = useMemo(() => computeScenario(raw, liveByTicker, state), [raw, liveByTicker, state]);

  const set = <K extends keyof ScnState>(k: K, v: ScnState[K]) => setState({ ...state, [k]: v });
  const reset = () => setState(scnInitial);
  const anyShock = state.spyShock || state.qqqShock || state.usdShock || state.rateShock;

  return (
    <div className="cyc scn">
      <p className="cyc-desc">
        Stress your live book against a market move. Stocks repriced via beta
        + tech/USD/rate factors; options legs revalued from the new spot and
        remaining time value. Hardcoded 1y-baseline betas for the top names;
        sector defaults beyond. Tail amp auto-engages at |SPY| ≥ 15%.
      </p>

      {/* ── Factor sliders ── */}
      <FactorBand state={state} set={set} onReset={reset} hasShock={!!anyShock} tail={result.tailMode} />

      {isLoading ? (
        <div className="scn-empty">Loading positions…</div>
      ) : raw.length === 0 ? (
        <div className="scn-empty">No open positions yet — add some on the Positions page.</div>
      ) : (
        <>
          <HeadlineTiles result={result} />
          <LegAttribution result={result} />
          <TopMovers result={result} />
          <SectorBars result={result} />
        </>
      )}
    </div>
  );
}

// ── Factor band — 4 sliders + WHEN pills ─────────────────────────
function FactorBand({
  state, set, onReset, hasShock, tail,
}: {
  state: ScnState;
  set: <K extends keyof ScnState>(k: K, v: ScnState[K]) => void;
  onReset: () => void;
  hasShock: boolean;
  tail: boolean;
}) {
  return (
    <div className="scn-factors">
      <div className="scn-factors-head">
        <span className="scn-factors-eyebrow">FACTORS</span>
        {tail && <span className="scn-tail-chip">⚠ tail mode · betas × 1.3</span>}
        {hasShock && (
          <button type="button" className="scn-reset-btn" onClick={onReset}>
            ↻ reset all
          </button>
        )}
      </div>

      <FactorSlider
        label="SPY"
        value={state.spyShock}
        onChange={(v) => set("spyShock", v)}
        min={-50}
        max={50}
        step={1}
        unit="%"
        snaps={[-25, -10, -5, 0, 5, 10, 25]}
        accent="market"
      />
      <FactorSlider
        label="QQQ"
        value={state.qqqShock}
        onChange={(v) => set("qqqShock", v)}
        min={-50}
        max={50}
        step={1}
        unit="%"
        snaps={[-25, -10, -5, 0, 5, 10, 25]}
        accent="tech"
      />
      <FactorSlider
        label="USD"
        value={state.usdShock}
        onChange={(v) => set("usdShock", v)}
        min={-10}
        max={10}
        step={1}
        unit="%"
        snaps={[-5, 0, 5]}
        accent="usd"
      />
      <FactorSlider
        label="10Y"
        value={state.rateShock}
        onChange={(v) => set("rateShock", v)}
        min={-200}
        max={200}
        step={10}
        unit="bp"
        snaps={[-100, -50, 0, 50, 100]}
        accent="rates"
      />

      <div className="scn-when">
        <span className="scn-when-lbl">WHEN</span>
        {TIME_OPTIONS.map((t) => (
          <button
            key={t.id}
            type="button"
            className={`scn-when-pill${state.whenDays === t.id ? " on" : ""}`}
            onClick={() => set("whenDays", t.id)}
          >
            {t.label}
          </button>
        ))}
        <span className="scn-when-hint">when the shock lands · affects option theta only</span>
      </div>
    </div>
  );
}

function FactorSlider({
  label, value, onChange, min, max, step, unit, snaps, accent,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  min: number;
  max: number;
  step: number;
  unit: string;
  snaps: number[];
  accent: "market" | "tech" | "usd" | "rates";
}) {
  const display = `${value >= 0 ? "+" : ""}${value}${unit}`;
  const tone = value === 0 ? "neutral" : value > 0 ? "pos" : "neg";
  return (
    <div className={`scn-slider accent-${accent}`}>
      <div className="scn-slider-lbl">{label}</div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        aria-label={`${label} shock`}
        className="scn-slider-input"
      />
      <div className={`scn-slider-val tone-${tone}`}>{display}</div>
      <div className="scn-slider-snaps">
        {snaps.map((s) => (
          <button
            key={s}
            type="button"
            className={`scn-snap${value === s ? " on" : ""}`}
            onClick={() => onChange(s)}
          >
            {s >= 0 ? "+" : ""}{s}{unit}
          </button>
        ))}
      </div>
    </div>
  );
}

// ── Headline tile — today → scenario ─────────────────────────────
function HeadlineTiles({ result }: { result: ScenarioResult }) {
  const t = result.totals;
  const tone = t.netDelta >= 0 ? "pos" : "neg";
  const pct = t.bookTodayTotal !== 0 ? (t.netDelta / t.bookTodayTotal) * 100 : 0;
  return (
    <div className="scn-headline">
      <div className="scn-headline-tile">
        <div className="scn-headline-lbl">Book today</div>
        <div className="scn-headline-val">{fmtMoney(t.bookTodayTotal, { decimals: 0 })}</div>
      </div>
      <div className="scn-headline-arrow">→</div>
      <div className="scn-headline-tile">
        <div className="scn-headline-lbl">In scenario</div>
        <div className={`scn-headline-val ${tone}`}>{fmtMoney(t.bookScenarioTotal, { decimals: 0 })}</div>
      </div>
      <div className="scn-headline-tile delta">
        <div className="scn-headline-lbl">Change</div>
        <div className={`scn-headline-val ${tone}`}>
          {fmtMoney(t.netDelta, { signed: true, decimals: 0 })}
          <span className="scn-headline-pct"> · {pct >= 0 ? "+" : ""}{pct.toFixed(2)}%</span>
        </div>
      </div>
    </div>
  );
}

// ── Leg attribution + put-coverage insight ───────────────────────
function LegAttribution({ result }: { result: ScenarioResult }) {
  const t = result.totals;
  // Coverage = how much of a STOCK LOSS the option legs offset. Only
  // meaningful when stock is in the red.
  const coverage =
    t.stockDelta < 0
      ? (t.optionDelta / Math.abs(t.stockDelta)) * 100
      : null;
  return (
    <div className="scn-legs">
      <LegTile label="Stock leg"      value={t.stockDelta} />
      <LegTile label="Long puts"      value={t.longPutDelta}   note="protective hedge" />
      <LegTile label="Long calls"     value={t.longCallDelta} />
      <LegTile label="Short calls"    value={t.shortCallDelta} note="covered-call P&L" />
      <LegTile label="Short puts"     value={t.shortPutDelta} />
      <LegTile label="Net option leg" value={t.optionDelta} bold />
      {coverage !== null && (
        <div className="scn-coverage">
          Options offset <b>{coverage.toFixed(1)}%</b> of the stock loss
          {coverage >= 100 && <span className="scn-coverage-flag pos"> · fully hedged</span>}
          {coverage > 0 && coverage < 100 && <span className="scn-coverage-flag warn"> · partial hedge</span>}
          {coverage <= 0 && <span className="scn-coverage-flag neg"> · no offset</span>}
        </div>
      )}
    </div>
  );
}

function LegTile({ label, value, note, bold }: { label: string; value: number; note?: string; bold?: boolean }) {
  const tone = value > 0 ? "pos" : value < 0 ? "neg" : "neutral";
  return (
    <div className={`scn-leg-tile${bold ? " bold" : ""}`}>
      <div className="scn-leg-lbl">{label}</div>
      <div className={`scn-leg-val tone-${tone}`}>{fmtMoney(value, { signed: true, decimals: 0 })}</div>
      {note && <div className="scn-leg-note">{note}</div>}
    </div>
  );
}

// ── Top movers table ─────────────────────────────────────────────
function TopMovers({ result }: { result: ScenarioResult }) {
  // Top 10 by absolute total delta. Negative deltas first within each "side"
  // so the user sees the biggest losses up top.
  const sorted = [...result.positions]
    .filter((p) => isFinite(p.totalDelta))
    .sort((a, b) => Math.abs(b.totalDelta) - Math.abs(a.totalDelta))
    .slice(0, 10);
  const bookTotal = result.totals.bookTodayTotal || 1;
  return (
    <div className="scn-movers">
      <div className="scn-section-head">TOP MOVERS · top 10 by impact</div>
      <table className="scn-movers-table">
        <thead>
          <tr>
            <th className="ticker">Ticker</th>
            <th className="beta">β eff</th>
            <th className="num">Today</th>
            <th className="num">Scenario</th>
            <th className="num">Δ stock</th>
            <th className="num">Δ options</th>
            <th className="num total">Δ total</th>
            <th className="num">hit on book</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((p) => {
            const tone = p.totalDelta >= 0 ? "pos" : "neg";
            const hitPct = (p.totalDelta / bookTotal) * 100;
            return (
              <tr key={p.ticker} className={`tone-${tone}`}>
                <td className="ticker">
                  {p.ticker}
                  {!p.curated && <span className="scn-est"> (est)</span>}
                </td>
                <td className="beta mono">{p.effectiveBeta.toFixed(2)}</td>
                <td className="num mono">{fmtMoney(p.todayPrice, { decimals: 2 })}</td>
                <td className="num mono">{fmtMoney(p.scenarioPrice, { decimals: 2 })}</td>
                <td className="num mono">{fmtMoney(p.stockDelta, { signed: true, decimals: 0 })}</td>
                <td className="num mono">{p.optionDelta !== 0 ? fmtMoney(p.optionDelta, { signed: true, decimals: 0 }) : "—"}</td>
                <td className={`num mono total ${tone}`}>{fmtMoney(p.totalDelta, { signed: true, decimals: 0 })}</td>
                <td className={`num mono ${tone}`}>{hitPct >= 0 ? "+" : ""}{hitPct.toFixed(2)}%</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ── Sector attribution bars ──────────────────────────────────────
function SectorBars({ result }: { result: ScenarioResult }) {
  const rows = result.sectorHits.filter((s) => Math.abs(s.delta) > 1);
  if (rows.length === 0) return null;
  const maxAbs = Math.max(...rows.map((r) => Math.abs(r.delta)));
  return (
    <div className="scn-sectors">
      <div className="scn-section-head">SECTOR HIT</div>
      <div className="scn-sector-rows">
        {rows.map((r) => {
          const pct = (Math.abs(r.delta) / maxAbs) * 100;
          const tone = r.delta >= 0 ? "pos" : "neg";
          return (
            <div key={r.sector} className={`scn-sector-row tone-${tone}`}>
              <div className="scn-sector-lbl">{r.sector}</div>
              <div className="scn-sector-bar">
                <div className={`scn-sector-fill ${tone}`} style={{ width: `${pct}%` }} />
              </div>
              <div className="scn-sector-val mono">
                {fmtMoney(r.delta, { signed: true, decimals: 0 })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Keep tree-shake-fooled imports referenced.
void fmtPct;
void ((null as unknown) as ReactNode);
