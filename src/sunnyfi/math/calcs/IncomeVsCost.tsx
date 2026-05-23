/**
 * Income vs Cost — v3 layout (variants-first, bar-as-hero).
 *
 * Mental model:
 *   • Calls roll MONTHLY (one cycle per month of the horizon).
 *   • One put covers the FULL horizon.
 *   • A "variant" is just a different horizon — Monthly / Quarterly / 4mo /
 *     6mo / 12mo. All 5 are auto-generated from the user's inputs.
 *
 * Prices:
 *   • Call premium — fetched once from the call chain at the implied
 *     call strike, picking the contract nearest 30 DTE.
 *   • Put premium — varies per variant; fetched once from the put chain,
 *     then each variant picks the nearest expiry to its DTE.
 *   • Estimator fallback (Black-Scholes-ish) when the chain returns nothing
 *     near the target — so non-major tickers don't break.
 *
 * No more frequency inputs, no cut-off control. Click a variant card to
 * select it as the "current view"; the bar + tiles + recap strip below
 * reflect that variant.
 */
import { Fragment, useEffect, useMemo, useState, useRef, type ReactNode } from "react";
import {
  fmtMoney, fmtPct, fmtCount, fmtDate,
  PullFromSunnyfi,
} from "../cycle";
import {
  pullOptionChain, nearestExpiry, type OptionContractQuote,
} from "../quote";
import "./IncomeVsCost.css";

// ── Constants ────────────────────────────────────────────────────
/** Put horizons — each defines the trading window and the put DTE. */
const PUT_HORIZONS = [
  { id: "monthly",   label: "Monthly",   short: "1mo",  months: 1,  days: 30  },
  { id: "quarterly", label: "Quarterly", short: "Qtr",  months: 3,  days: 91  },
  { id: "4mo",       label: "4 months",  short: "4mo",  months: 4,  days: 122 },
  { id: "6mo",       label: "6 months",  short: "6mo",  months: 6,  days: 182 },
  { id: "12mo",      label: "12 months", short: "12mo", months: 12, days: 365 },
] as const;

/** Call cadences inside the window — DTE drives the per-roll premium.
 *  "Daily" is conditional on the call chain actually listing dailies
 *  (cheap names usually don't); the rest are always shown. */
const CALL_CADENCES = [
  { id: "daily",         label: "Daily",       short: "Dly",  perUnit: "/day", dte: 1,  perMonth: 21,    requiresShortDated: true },
  { id: "thrice-weekly", label: "3 ×/wk",      short: "3×wk", perUnit: "/run", dte: 2,  perMonth: 13,    requiresShortDated: true },
  { id: "weekly",        label: "Weekly",      short: "Wkly", perUnit: "/wk",  dte: 7,  perMonth: 4.33,  requiresShortDated: false },
  { id: "biweekly",      label: "Bi-weekly",   short: "Bi",   perUnit: "/2wk", dte: 14, perMonth: 2.17,  requiresShortDated: false },
  { id: "monthly",       label: "Monthly",     short: "Mo",   perUnit: "/mo",  dte: 30, perMonth: 1,     requiresShortDated: false },
] as const;

/** Rough IV per ticker for the estimator fallback. Real chains override. */
const IV_HINTS: Record<string, number> = {
  SPY: 0.18, QQQ: 0.22, AAPL: 0.25, NVDA: 0.45, TSLA: 0.55,
  META: 0.32, MSFT: 0.22, AMZN: 0.30, GOOGL: 0.26, AMD: 0.50, COIN: 0.70,
};
const IV_DEFAULT = 0.32;
const ivFor = (ticker: string): number => IV_HINTS[ticker?.toUpperCase()] ?? IV_DEFAULT;

// ── State ────────────────────────────────────────────────────────
export interface IVCState extends Record<string, unknown> {
  underlying: string;
  shares: string;
  price: string;
  callContracts: string;
  callDistance: string;       // % OTM (above spot, positive)
  putContracts: string;
  putDistance: string;        // % below spot (positive)
  /** Composite "{callCadenceId}_{putHorizonId}" e.g. "weekly_quarterly". */
  selectedVariantId: string;
}

export const ivcInitial: IVCState = {
  underlying: "SPY",
  shares: "500",
  price: "655.06",
  callContracts: "5",
  callDistance: "1.0",
  putContracts: "5",
  putDistance: "2.0",
  selectedVariantId: "weekly_quarterly",
};

// ── Premium estimator (Black-Scholes-ish, used as fallback) ──────
function estPremium(opts: { spot: number; strike: number; daysToExp: number; iv: number; isCall: boolean }): number {
  const { spot, strike, daysToExp, iv, isCall } = opts;
  if (!isFinite(spot) || !isFinite(strike) || !isFinite(daysToExp) || daysToExp <= 0 || spot <= 0) return NaN;
  const T = daysToExp / 365;
  const sqrtT = Math.sqrt(T);
  const atmTV = 0.4 * spot * iv * sqrtT;
  const moneyness = (strike - spot) / spot;
  const otmAmt = isCall ? Math.max(0, moneyness) : Math.max(0, -moneyness);
  const skew = Math.exp(-(otmAmt / Math.max(0.01, iv * sqrtT)) * 1.6);
  const intrinsic = isCall ? Math.max(0, spot - strike) : Math.max(0, strike - spot);
  return Math.max(0.05, intrinsic + atmTV * skew);
}

// ── Variant compute ──────────────────────────────────────────────
export interface IVCVariant {
  id: string;                  // "{callCadenceId}_{putHorizonId}"
  callCadenceId: string;
  callCadenceLabel: string;    // short, e.g. "Wkly"
  putHorizonId: string;
  putHorizonLabel: string;     // short, e.g. "Qtr"
  months: number;              // put horizon in months
  days: number;                // put horizon in days
  horizonDate: Date;
  callPrem: number;
  putPrem: number;
  callPremSource: "real" | "estimate";
  putPremSource: "real" | "estimate";
  callExpiry: string | null;
  putExpiry: string | null;
  callCycles: number;
  putCycles: number;
  incomePerCycle: number;
  costPerCycle: number;
  totalIncome: number;
  totalCost: number;
  net: number;
  coverage: number;
  netAnnYield: number;
  notional: number;
  callStrike: number;
  putStrike: number;
  callDte: number;
  /** Per-cycle suffix for income labels, e.g. "/wk", "/mo". */
  callPerUnit: string;
  rank: number;
  isBest: boolean;
}

function plusDays(d: Date, n: number): Date {
  const r = new Date(d); r.setDate(r.getDate() + n); return r;
}

/** Decide which call cadences to surface based on actual expiry density.
 *
 *  Old logic just asked "is there ANY contract within 14 days?" — but for
 *  AAPL the weekly Friday qualifies, so Daily/3×wk lit up even though AAPL
 *  doesn't list daily expiries. We need to measure how tightly packed the
 *  near-dated expiries actually are.
 *
 *  Method: look at distinct expiries within the next ~30 calendar days, walk
 *  consecutive pairs, and use the MEDIAN spacing (resistant to one rogue
 *  EOM expiry). Then:
 *     spacing ≤ 1.5 cal days  → Daily exists  (SPY/QQQ/SPX)
 *     spacing ≤ 3.5 cal days  → 3×wk exists   (some ETFs w/ M-W-F)
 *     spacing ≤ 8 cal days    → Weekly exists (AAPL, MSFT, most liquid names)
 *     anything wider          → Monthly-only
 *
 *  Cadences whose listed `requiresShortDated` field is false (Weekly, Bi,
 *  Monthly) always pass through — they're synthesizable from a monthly chain. */
function callCadencesAvailable(callChain: OptionContractQuote[]): typeof CALL_CADENCES {
  if (callChain.length === 0) {
    // No chain data yet — show the safe-default set (Weekly+).
    return CALL_CADENCES.filter((c) => !c.requiresShortDated);
  }
  const todayMs = Date.now();
  const horizonMs = todayMs + 30 * 86400000;
  // Distinct expiries within the next 30 days, sorted.
  const expiries = Array.from(new Set(
    callChain
      .map((c) => new Date(c.expiry + "T00:00:00Z").getTime())
      .filter((t) => t >= todayMs && t <= horizonMs),
  )).sort((a, b) => a - b);

  // Median gap between consecutive expiries (calendar days).
  let medianGapDays = Infinity;
  if (expiries.length >= 2) {
    const gaps: number[] = [];
    for (let i = 1; i < expiries.length; i++) {
      gaps.push((expiries[i] - expiries[i - 1]) / 86400000);
    }
    gaps.sort((a, b) => a - b);
    medianGapDays = gaps[Math.floor(gaps.length / 2)];
  } else if (expiries.length === 1) {
    // Single near expiry: treat gap as the distance to it (rough proxy).
    medianGapDays = (expiries[0] - todayMs) / 86400000;
  }

  const hasDaily   = medianGapDays <= 1.5;
  const hasThriceW = medianGapDays <= 3.5;

  return CALL_CADENCES.filter((c) => {
    if (c.id === "daily") return hasDaily;
    if (c.id === "thrice-weekly") return hasThriceW;
    return true;  // weekly / bi / monthly always allowed
  });
}

function computeAllVariants(
  state: IVCState,
  callChain: OptionContractQuote[],
  putChain: OptionContractQuote[],
  now: Date = new Date(),
): IVCVariant[] {
  const shares = Number(state.shares);
  const price = Number(state.price);
  const callContracts = Number(state.callContracts);
  const putContracts = Number(state.putContracts);
  const callDist = Number(state.callDistance);
  const putDist = Number(state.putDistance);

  if (!isFinite(shares) || shares <= 0 || !isFinite(price) || price <= 0) return [];
  if (!isFinite(callContracts) || !isFinite(putContracts)) return [];

  const iv = ivFor(state.underlying);
  const notional = shares * price;
  const callStrike = price * (1 + (isFinite(callDist) ? callDist : 0) / 100);
  const putStrike  = price * (1 - (isFinite(putDist)  ? putDist  : 0) / 100);
  const callCadences = callCadencesAvailable(callChain);

  // Pre-compute one call premium per cadence (depends on DTE, not on horizon).
  const callPriceByCadence = new Map<string, { premium: number; source: "real" | "estimate"; expiry: string | null }>();
  for (const cad of callCadences) {
    const targetIso = plusDays(now, cad.dte).toISOString().slice(0, 10);
    const match = nearestExpiry(callChain, targetIso);
    const premium = match?.premium
      ?? estPremium({ spot: price, strike: callStrike, daysToExp: cad.dte, iv, isCall: true });
    callPriceByCadence.set(cad.id, {
      premium,
      source: match ? "real" : "estimate",
      expiry: match?.expiry ?? null,
    });
  }

  const variants: IVCVariant[] = [];
  for (const h of PUT_HORIZONS) {
    const horizonDate = plusDays(now, h.days);
    const putTargetIso = horizonDate.toISOString().slice(0, 10);
    const putMatch = nearestExpiry(putChain, putTargetIso);
    const putPrem = putMatch?.premium
      ?? estPremium({ spot: price, strike: putStrike, daysToExp: h.days, iv, isCall: false });

    for (const cad of callCadences) {
      const cp = callPriceByCadence.get(cad.id)!;
      const callCycles = Math.max(1, Math.round(cad.perMonth * h.months));
      const putCycles = 1;
      const incomePerCycle = callContracts * cp.premium * 100;
      const costPerCycle = putContracts * putPrem * 100;
      const totalIncome = incomePerCycle * callCycles;
      const totalCost = costPerCycle * putCycles;
      const net = totalIncome - totalCost;
      const coverage = totalCost > 0 ? totalIncome / totalCost
        : totalIncome > 0 ? Infinity : NaN;
      const years = h.days / 365.25;
      const annualNet = years > 0 ? net / years : NaN;
      const netAnnYield = notional > 0 && isFinite(annualNet) ? (annualNet / notional) * 100 : NaN;

      variants.push({
        id: `${cad.id}_${h.id}`,
        callCadenceId: cad.id,
        callCadenceLabel: cad.short,
        putHorizonId: h.id,
        putHorizonLabel: h.short,
        months: h.months,
        days: h.days,
        horizonDate,
        callPrem: cp.premium,
        putPrem,
        callPremSource: cp.source,
        putPremSource: putMatch ? "real" : "estimate",
        callExpiry: cp.expiry,
        putExpiry: putMatch?.expiry ?? null,
        callCycles, putCycles,
        incomePerCycle, costPerCycle,
        totalIncome, totalCost, net, coverage, netAnnYield,
        notional, callStrike, putStrike,
        callDte: cad.dte,
        callPerUnit: cad.perUnit,
        rank: 0, isBest: false,
      });
    }
  }

  // Rank by net dollars (the user's "best" definition).
  const ranked = [...variants].sort((a, b) => b.net - a.net);
  ranked.forEach((v, i) => { v.rank = i + 1; v.isBest = i === 0; });
  return ranked;  // return RANKED order so #1 lands first in the grid
}

// ── Registry helpers (used by Compare view) ──────────────────────
// "Display" / "rank" reflect the currently SELECTED horizon of a saved
// IvC snapshot — that's what the Compare card should show, since the user
// pinned a specific variant.
function selectedFrom(state: IVCState): IVCVariant | null {
  const vars = computeAllVariants(state, [], []);
  if (vars.length === 0) return null;
  return vars.find((v) => v.id === state.selectedVariantId) ?? vars[0];
}

export function ivcCopy(state: IVCState): string {
  const sel = selectedFrom(state);
  if (!sel) return `${state.underlying} · incomplete`;
  const combo = `${sel.callCadenceLabel} calls × ${sel.putHorizonLabel} puts`;
  return `${state.underlying} · ${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))} · ${combo}: +${fmtMoney(sel.totalIncome, { decimals: 0 })} calls / −${fmtMoney(sel.totalCost, { decimals: 0 })} puts = ${fmtMoney(sel.net, { signed: true, decimals: 0 })} net (${fmtPct(sel.netAnnYield)} ann.) through ${fmtDate(sel.horizonDate)}`;
}

export function ivcDisplay(state: IVCState): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const sel = selectedFrom(state);
  if (!sel || !isFinite(sel.net)) return { value: "—", tone: "muted" };
  return {
    value: fmtMoney(sel.net, { signed: true }),
    tone: sel.net > 0 ? "pos" : sel.net < 0 ? "neg" : "neon",
  };
}

export function ivcFields(state: IVCState): Array<{ label: string; value: string; mono?: boolean }> {
  const sel = selectedFrom(state);
  if (!sel) {
    return [
      { label: "Underlying", value: state.underlying || "—", mono: true },
      { label: "Status",     value: "incomplete inputs", mono: true },
    ];
  }
  return [
    { label: "Underlying",   value: state.underlying || "—", mono: true },
    { label: "Combo",        value: `${sel.callCadenceLabel} × ${sel.putHorizonLabel}`, mono: true },
    { label: "Horizon",      value: fmtDate(sel.horizonDate), mono: true },
    { label: "Total income", value: fmtMoney(sel.totalIncome), mono: true },
    { label: "Total cost",   value: fmtMoney(sel.totalCost),   mono: true },
    { label: "Ann. yield",   value: fmtPct(sel.netAnnYield), mono: true },
  ];
}

export function ivcUpsertKey(state: IVCState): string | null {
  return state.underlying?.trim().toUpperCase() || null;
}

export function ivcRank(state: IVCState): { score: number; label: string } | null {
  const sel = selectedFrom(state);
  if (!sel || !isFinite(sel.netAnnYield)) return null;
  return { score: sel.netAnnYield, label: "net ann. yield" };
}

export function ivcCardLine(state: IVCState): string {
  const sel = selectedFrom(state);
  if (!sel) return `${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))}`;
  const cov = !isFinite(sel.coverage) ? "—" : sel.coverage === Infinity ? "∞" : `${sel.coverage.toFixed(2)}x`;
  return `${sel.callCadenceLabel} × ${sel.putHorizonLabel} · ${cov} coverage`;
}

// ── Body ─────────────────────────────────────────────────────────
export function IncomeVsCostCalc({
  state,
  setState,
}: {
  state: IVCState;
  setState: (next: IVCState | ((prev: IVCState) => IVCState)) => void;
}) {
  const set = <K extends keyof IVCState>(k: K, v: IVCState[K]) => setState({ ...state, [k]: v });

  // Auto-fetch chains for both sides. Debounced to avoid hitting Polygon on
  // every keystroke. One fetch per side, used for all 5 variants.
  const [callChain, setCallChain] = useState<OptionContractQuote[]>([]);
  const [putChain, setPutChain]   = useState<OptionContractQuote[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [lastFetchedAt, setLastFetchedAt] = useState<number | null>(null);

  const callStrike = useMemo(() => {
    const p = Number(state.price), d = Number(state.callDistance);
    return isFinite(p) && p > 0 && isFinite(d) ? p * (1 + d / 100) : NaN;
  }, [state.price, state.callDistance]);
  const putStrike = useMemo(() => {
    const p = Number(state.price), d = Number(state.putDistance);
    return isFinite(p) && p > 0 && isFinite(d) ? p * (1 - d / 100) : NaN;
  }, [state.price, state.putDistance]);

  const lastFetchKeyRef = useRef<string>("");
  useEffect(() => {
    if (!state.underlying || !isFinite(callStrike) || !isFinite(putStrike)) return;
    const key = `${state.underlying}|${callStrike.toFixed(2)}|${putStrike.toFixed(2)}`;
    if (key === lastFetchKeyRef.current) return;
    const t = window.setTimeout(async () => {
      lastFetchKeyRef.current = key;
      setRefreshing(true);
      try {
        const [calls, puts] = await Promise.all([
          pullOptionChain(state.underlying, callStrike, "call").catch(() => [] as OptionContractQuote[]),
          pullOptionChain(state.underlying, putStrike,  "put").catch(() => [] as OptionContractQuote[]),
        ]);
        setCallChain(calls);
        setPutChain(puts);
        setLastFetchedAt(Date.now());
      } finally {
        setRefreshing(false);
      }
    }, 700);
    return () => window.clearTimeout(t);
  }, [state.underlying, callStrike, putStrike]);

  const variants = useMemo(
    () => computeAllVariants(state, callChain, putChain),
    [state, callChain, putChain],
  );
  // Variants come pre-ranked (rank=1 is #1 by net). The first one is BEST.
  const bestId = variants[0]?.id;
  const selected = variants.find((v) => v.id === state.selectedVariantId) ?? variants[0];

  const lastFetchedTxt = lastFetchedAt
    ? `${Math.max(1, Math.round((Date.now() - lastFetchedAt) / 1000))}s ago`
    : "—";

  return (
    <div className="cyc ivc3">
      <p className="cyc-desc">
        Net economics of running monthly covered calls against one protective put per window.
        Edit inputs below — variants auto-price across 5 horizons. Click any to inspect.
      </p>

      {/* ── Single-row inputs ── */}
      <div className="ivc3-inputs">
        <div className="ivc3-in ticker">
          <div className="hf-label">Underlying</div>
          <input
            className="cyc-input ticker"
            type="text"
            value={state.underlying}
            onChange={(e) => set("underlying", e.target.value.toUpperCase())}
            placeholder="SPY"
            aria-label="Underlying ticker"
          />
          <PullFromSunnyfi
            ticker={state.underlying}
            onPull={({ price, shares }) =>
              setState({
                ...state,
                price: price.toFixed(2),
                ...(shares ? { shares: String(shares) } : {}),
              })
            }
          />
        </div>

        <div className="ivc3-in">
          <div className="hf-label">Shares</div>
          <input
            className="cyc-input"
            type="text" inputMode="numeric"
            value={state.shares}
            onChange={(e) => set("shares", e.target.value)}
            placeholder="0"
            aria-label="Shares"
          />
          <div className="ivc3-in-hint mono">
            = {fmtMoney((Number(state.shares) || 0) * (Number(state.price) || 0), { decimals: 0 })}
          </div>
        </div>

        <div className="ivc3-in">
          <div className="hf-label">Price · live</div>
          <div className="cyc-field-row">
            <span className="cyc-prefix">$</span>
            <input
              className="cyc-input"
              type="text" inputMode="decimal"
              value={state.price}
              onChange={(e) => set("price", e.target.value)}
              placeholder="0.00"
              aria-label="Current price"
            />
          </div>
          <div className="ivc3-in-hint">
            <span className={`live-dot ${refreshing ? "" : "pos"}`} />
            Polygon · {lastFetchedTxt}
          </div>
        </div>

        <div className="ivc3-divider" aria-hidden />

        <div className="ivc3-side calls">
          <span className="ivc3-side-tag">CALL <span className="muted">· sell · monthly</span></span>
          <div className="ivc3-side-fields">
            <div className="ivc3-in tight">
              <div className="hf-label">Contracts</div>
              <div className="ivc3-field-input">
                <input
                  type="text" inputMode="numeric"
                  value={state.callContracts}
                  onChange={(e) => set("callContracts", e.target.value)}
                  placeholder="0" spellCheck={false}
                  aria-label="Call contracts"
                />
              </div>
              <div className="ivc3-in-hint mono">{fmtCount((Number(state.callContracts) || 0) * 100)} sh</div>
            </div>
            <div className="ivc3-in tight">
              <div className="hf-label">OTM dist</div>
              <div className="ivc3-field-input">
                <input
                  type="text" inputMode="decimal"
                  value={state.callDistance}
                  onChange={(e) => set("callDistance", e.target.value)}
                  placeholder="0.0" spellCheck={false}
                  aria-label="Call strike distance OTM"
                />
                <span className="suffix">%</span>
              </div>
              <div className="ivc3-in-hint mono">K ≈ {fmtMoney(callStrike)}</div>
            </div>
          </div>
        </div>

        <div className="ivc3-side puts">
          <span className="ivc3-side-tag">PUT <span className="muted">· buy · spans window</span></span>
          <div className="ivc3-side-fields">
            <div className="ivc3-in tight">
              <div className="hf-label">Contracts</div>
              <div className="ivc3-field-input">
                <input
                  type="text" inputMode="numeric"
                  value={state.putContracts}
                  onChange={(e) => set("putContracts", e.target.value)}
                  placeholder="0" spellCheck={false}
                  aria-label="Put contracts"
                />
              </div>
              <div className="ivc3-in-hint mono">{fmtCount((Number(state.putContracts) || 0) * 100)} sh</div>
            </div>
            <div className="ivc3-in tight">
              <div className="hf-label">Below spot</div>
              <div className="ivc3-field-input">
                <input
                  type="text" inputMode="decimal"
                  value={state.putDistance}
                  onChange={(e) => set("putDistance", e.target.value)}
                  placeholder="0.0" spellCheck={false}
                  aria-label="Put strike distance"
                />
                <span className="suffix">%</span>
              </div>
              <div className="ivc3-in-hint mono">K ≈ {fmtMoney(putStrike)}</div>
            </div>
          </div>
        </div>
      </div>

      {/* ── Variants strip ── */}
      <VariantsGrid
        variants={variants}
        ticker={state.underlying}
        selectedId={state.selectedVariantId}
        bestId={bestId}
        onSelect={(id) => set("selectedVariantId", id)}
        lastFetchedTxt={lastFetchedTxt}
      />

      {/* ── Selected variant breakdown — bar is hero ── */}
      {selected && (
        <SelectedBreakdown variant={selected} state={state} bestId={bestId} />
      )}
    </div>
  );
}

// ── Variants grid (5 cards) ──────────────────────────────────────
function VariantsGrid({
  variants, ticker, selectedId, bestId, onSelect, lastFetchedTxt,
}: {
  variants: IVCVariant[];
  ticker: string;
  selectedId: string;
  bestId: string | undefined;
  onSelect: (id: string) => void;
  lastFetchedTxt: string;
}) {
  return (
    <div className="ivc3-variants-wrap">
      <div className="ivc3-variants-head">
        <div className="left">
          <div className="ivc3-variants-eyebrow">
            Variants <span className="dot">·</span>
            <span className="ticker-tag">{ticker || "—"}</span>
            <span className="dot">·</span>
            <span className="count-tag">{variants.length}</span>
          </div>
          <div className="ivc3-variants-sub">
            auto-priced from Polygon · {lastFetchedTxt} · ranked by{" "}
            <span className="accent">net $ to horizon</span>
          </div>
        </div>
      </div>

      {variants.length > 0 ? (
        <VariantsMatrix
          variants={variants}
          selectedId={selectedId}
          bestId={bestId}
          onSelect={onSelect}
        />
      ) : (
        <div className="ivc3-card empty">
          <div className="ivc3-card-empty-msg">
            Fill in ticker · shares · contracts on both sides to auto-generate variants from live chain data.
          </div>
        </div>
      )}
    </div>
  );
}

/** Matrix view: rows = call cadence, cols = put horizon.
 *  Cell = compact metric tile with heatmap background by net $ rank.
 *  The axes carry the variant identity, so cells just show the numbers. */
function VariantsMatrix({
  variants, selectedId, bestId, onSelect,
}: {
  variants: IVCVariant[];
  selectedId: string;
  bestId: string | undefined;
  onSelect: (id: string) => void;
}) {
  // Find which call cadences and put horizons are actually present.
  const presentCallIds = new Set(variants.map((v) => v.callCadenceId));
  const presentPutIds = new Set(variants.map((v) => v.putHorizonId));
  const rows = CALL_CADENCES.filter((c) => presentCallIds.has(c.id));
  const cols = PUT_HORIZONS.filter((h) => presentPutIds.has(h.id));

  const byKey = new Map(variants.map((v) => [v.id, v]));
  const nets = variants.map((v) => v.net);
  const minNet = Math.min(...nets);
  const maxNet = Math.max(...nets);

  /** Map net → 0..1 along the min..max range. Used for heatmap intensity. */
  const norm = (n: number) =>
    maxNet === minNet ? 0.5 : (n - minNet) / (maxNet - minNet);

  return (
    <div
      className="ivc3-matrix"
      style={{ ["--cols" as string]: String(cols.length) }}
    >
      {/* Top-left corner spacer */}
      <div className="ivc3-matrix-corner" aria-hidden />
      {/* Column headers (put horizons) */}
      {cols.map((h) => (
        <div key={`ch-${h.id}`} className="ivc3-matrix-colhead">
          <span className="hd-label">{h.short}</span>
          <span className="hd-sub">put</span>
        </div>
      ))}

      {rows.map((cad) => (
        <Fragment key={`row-${cad.id}`}>
          <div className="ivc3-matrix-rowhead">
            <span className="hd-label">{cad.short}</span>
            <span className="hd-sub">call</span>
          </div>
          {cols.map((h) => {
            const id = `${cad.id}_${h.id}`;
            const v = byKey.get(id);
            if (!v) {
              return <div key={id} className="ivc3-matrix-cell ivc3-matrix-cell--missing" />;
            }
            const t = norm(v.net);
            const isSelected = id === selectedId;
            const isBestCell = id === bestId;
            const tone = v.net >= 0 ? "pos" : "neg";
            const ann = isFinite(v.netAnnYield)
              ? `${v.netAnnYield >= 0 ? "" : "−"}${Math.abs(v.netAnnYield).toFixed(1)}%`
              : "—";
            return (
              <div
                key={id}
                className={`ivc3-matrix-cell tone-${tone}${isSelected ? " selected" : ""}${isBestCell ? " best" : ""}`}
                style={{ ["--heat" as string]: t.toFixed(3) }}
                onClick={() => onSelect(id)}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelect(id); }
                }}
                aria-label={`${cad.label} calls × ${h.label} puts, net ${fmtMoney(v.net, { signed: true })}`}
                title={`${cad.label} × ${h.label} · net ${fmtMoney(v.net, { signed: true })} · ${ann}/yr · cov ${isFinite(v.coverage) ? (v.coverage === Infinity ? "∞" : v.coverage.toFixed(2) + "x") : "—"}`}
              >
                {isBestCell && <span className="ivc3-matrix-best">BEST</span>}
                <span className="ivc3-matrix-net">{fmtMoney(v.net, { signed: true, decimals: 0 })}</span>
                <span className="ivc3-matrix-yld">{ann}</span>
              </div>
            );
          })}
        </Fragment>
      ))}
    </div>
  );
}

// ── Selected breakdown: bar + tiles + recap ──────────────────────
function SelectedBreakdown({
  variant: v, state, bestId,
}: {
  variant: IVCVariant;
  state: IVCState;
  bestId: string | undefined;
}) {
  const netTone = v.net > 0 ? "pos" : v.net < 0 ? "neg" : "neutral";
  const coverageTone = isFinite(v.coverage) && v.coverage >= 1 ? "pos" : "warn";
  const cov = !isFinite(v.coverage) ? "—" : v.coverage === Infinity ? "∞" : `${v.coverage.toFixed(2)}x`;
  const breakeven = useMemo(() => {
    const cc = Number(state.callContracts);
    if (!isFinite(cc) || cc <= 0 || v.callCycles <= 0) return NaN;
    return v.totalCost / (cc * v.callCycles * 100);
  }, [v, state.callContracts]);
  const monthsToFundPut = useMemo(() => {
    if (!isFinite(v.incomePerCycle) || v.incomePerCycle <= 0) return NaN;
    return v.costPerCycle / v.incomePerCycle;
  }, [v]);

  const isBest = v.id === bestId;

  return (
    <div className="ivc3-selected">
      <div className="ivc3-selected-head">
        <div className="left">
          <div className="ivc3-selected-eyebrow">
            Breakdown <span className="neon">· {isBest ? "BEST" : `#${v.rank}`}</span>
          </div>
          <div className="ivc3-selected-title">
            {state.underlying || "—"}{" "}
            <span className="muted">· {v.callCadenceLabel} calls × {v.putHorizonLabel} puts · to {fmtDate(v.horizonDate)}</span>
          </div>
        </div>
        <div className="ivc3-selected-meta">Read-only · derived from the selected variant</div>
      </div>

      {/* The hero: stacked bar */}
      <IvcBar v={v} />

      {/* Supporting tiles */}
      <div className="cyc-results ivc3-tiles">
        <Tile label="Net to horizon"     value={fmtMoney(v.net, { signed: true })}              tone={netTone} primary />
        <Tile label="Coverage ratio"     value={cov}                                            tone={coverageTone} sub="income ÷ cost" />
        <Tile label="Net ann. yield"     value={fmtPct(v.netAnnYield)}                          tone={netTone === "neg" ? "neg" : "neon"} sub="net ÷ notional" />
        <Tile label="Breakeven prem"     value={fmtMoney(breakeven)}                            mono sub="per call, to fund puts" />
        <Tile label="Months to fund put" value={isFinite(monthsToFundPut) ? `${monthsToFundPut.toFixed(1)} mo` : "—"} mono sub="income ÷ put cost" />
      </div>

      {/* Formula recap */}
      <div className="ivc3-recap-strip">
        <div className="ivc3-recap-row calls">
          <span className="ivc3-recap-pill">CALL</span>
          <span className="ivc3-recap-formula">
            <b>{fmtCount(Number(state.callContracts) || 0)}c</b> ×{" "}
            <b>{fmtMoney(v.callPrem, { decimals: 2 })}</b> →{" "}
            <b>{fmtMoney(v.incomePerCycle, { decimals: 0 })}</b>{v.callPerUnit} ×{" "}
            <b>{fmtCount(v.callCycles)}</b> ={" "}
            <b className="pos">+{fmtMoney(v.totalIncome, { decimals: 0 }).replace(/^[+−]?/, "")}</b>
          </span>
          <span className="ivc3-recap-meta">
            <span className="auto-tag">{v.callPremSource === "real" ? "real" : "est"}</span>
            {v.callExpiry ? `next exp ${v.callExpiry} · ` : ""}
            ~{v.callDte} DTE · K {fmtMoney(v.callStrike, { decimals: 2 })}
          </span>
        </div>
        <div className="ivc3-recap-row puts">
          <span className="ivc3-recap-pill">PUT</span>
          <span className="ivc3-recap-formula">
            <b>{fmtCount(Number(state.putContracts) || 0)}c</b> ×{" "}
            <b>{fmtMoney(v.putPrem, { decimals: 2 })}</b> →{" "}
            <b>{fmtMoney(v.costPerCycle, { decimals: 0 })}</b>/put ×{" "}
            <b>{fmtCount(v.putCycles)}</b> ={" "}
            <b className="neg">−{fmtMoney(v.totalCost, { decimals: 0 }).replace(/^[+−]?/, "")}</b>
          </span>
          <span className="ivc3-recap-meta">
            <span className="auto-tag">{v.putPremSource === "real" ? "real" : "est"}</span>
            {v.putExpiry ? `exp ${v.putExpiry} · ` : ""}
            {v.days} DTE · K {fmtMoney(v.putStrike, { decimals: 2 })}
          </span>
        </div>
      </div>
    </div>
  );
}

// ── The hero bar — stacked income vs cost with per-cycle dividers ─
function IvcBar({ v }: { v: IVCVariant }) {
  const { totalIncome, totalCost, net, callCycles, putCycles, months,
    incomePerCycle, costPerCycle } = v;

  const barMax = Math.max(totalIncome || 0, totalCost || 0, 1);
  const incomePct = Math.min(100, ((totalIncome || 0) / barMax) * 100);
  const costPct = Math.min(100, ((totalCost || 0) / barMax) * 100);

  const surplus = net >= 0;
  const markerPct = Math.min(incomePct, costPct);
  const markerLabel = surplus
    ? `surplus +${fmtMoney(Math.abs(net), { decimals: 0 }).replace(/^[+−]?/, "")}`
    : `shortfall −${fmtMoney(Math.abs(net), { decimals: 0 }).replace(/^[+−]?/, "")}`;

  // Cycle dividers inside each fill (call cycles in income, put cycles in cost)
  const incomeCycleEdges: number[] = [];
  for (let i = 1; i < callCycles; i++) incomeCycleEdges.push((i / callCycles) * 100);
  const costCycleEdges: number[] = [];
  for (let i = 1; i < putCycles; i++) costCycleEdges.push((i / putCycles) * 100);

  // Month ticks on the scale beneath
  const monthTicks: Array<{ i: number; pct: number }> = [];
  for (let i = 1; i <= months; i++) monthTicks.push({ i, pct: (i / months) * 100 });

  return (
    <div className="ivc3-bar">
      <div className="ivc3-bar-stack">
        <div className="ivc3-bar-row income">
          <div className="ivc3-bar-rail">
            <div className="ivc3-bar-fill income" style={{ width: `${incomePct}%` }}>
              {incomeCycleEdges.map((p, i) => (
                <span key={i} className="ivc3-cycle-divider" style={{ left: `${p}%` }} />
              ))}
              <span className="ivc3-bar-perchunk">{fmtMoney(incomePerCycle, { decimals: 0 })}{v.callPerUnit}</span>
            </div>
          </div>
        </div>
        <div className="ivc3-bar-row cost">
          <div className="ivc3-bar-rail">
            <div className="ivc3-bar-fill cost" style={{ width: `${costPct}%` }}>
              {costCycleEdges.map((p, i) => (
                <span key={i} className="ivc3-cycle-divider" style={{ left: `${p}%` }} />
              ))}
              <span className="ivc3-bar-perchunk">{fmtMoney(costPerCycle, { decimals: 0 })}/put</span>
            </div>
          </div>
        </div>
        {isFinite(net) && net !== 0 && incomePct > 0 && costPct > 0 && (
          <div className={`ivc3-bar-marker ${surplus ? "pos" : "neg"}`} style={{ left: `${markerPct}%` }}>
            <span className="ivc3-bar-marker-flag">{markerLabel}</span>
          </div>
        )}
      </div>

      <div className="ivc3-bar-scale">
        <div className="ivc3-bar-scale-rail">
          {monthTicks.map(({ i, pct }) => (
            <span key={i} className={`ivc3-month-tick ${i === months ? "last" : ""}`} style={{ left: `${pct}%` }}>
              <span className="lbl">M{i}</span>
            </span>
          ))}
          <span className="ivc3-month-tick first">
            <span className="lbl">now</span>
          </span>
        </div>
      </div>
    </div>
  );
}

// ── Local Tile copy (avoids a circular dep with cycle.tsx) ───────
function Tile({
  label, value, sub, tone, primary, mono,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: "pos" | "neg" | "neon" | "warn" | "neutral";
  primary?: boolean;
  mono?: boolean;
}) {
  const toneCls = tone && tone !== "neutral" ? ` ${tone}` : "";
  return (
    <div className={`cyc-tile ${primary ? "primary" : ""}`}>
      <div className="cyc-tile-label">{label}</div>
      {sub && <div className="cyc-tile-sub">{sub}</div>}
      <div className={`cyc-tile-val${mono ? " mono" : ""}${toneCls}`}>{value}</div>
    </div>
  );
}
