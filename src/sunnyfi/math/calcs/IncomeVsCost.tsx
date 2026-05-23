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
import { useEffect, useMemo, useState, useRef, type ReactNode } from "react";
import {
  fmtMoney, fmtPct, fmtCount, fmtDate,
  PullFromSunnyfi,
} from "../cycle";
import {
  pullOptionChain, nearestExpiry, type OptionContractQuote,
} from "../quote";
import "./IncomeVsCost.css";

// ── Constants ────────────────────────────────────────────────────
/** Horizons drive cycle counts directly: callCycles = months, putCycles = 1. */
const VARIANT_HORIZONS = [
  { id: "monthly",   label: "Monthly",   months: 1,  days: 30  },
  { id: "quarterly", label: "Quarterly", months: 3,  days: 91  },
  { id: "4mo",       label: "4 months",  months: 4,  days: 122 },
  { id: "6mo",       label: "6 months",  months: 6,  days: 182 },
  { id: "12mo",      label: "12 months", months: 12, days: 365 },
] as const;

const CALL_CYCLE_DTE = 30; // monthly call cadence (fixed)

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
  selectedHorizonId: string;  // "monthly" | "quarterly" | "4mo" | "6mo" | "12mo"
}

export const ivcInitial: IVCState = {
  underlying: "SPY",
  shares: "500",
  price: "655.06",
  callContracts: "5",
  callDistance: "1.0",
  putContracts: "5",
  putDistance: "2.0",
  selectedHorizonId: "quarterly",
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
  id: string;
  label: string;
  months: number;
  days: number;
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
  rank: number;
  isBest: boolean;
}

function plusDays(d: Date, n: number): Date {
  const r = new Date(d); r.setDate(r.getDate() + n); return r;
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

  // Single call premium — monthly cadence, ~30 DTE.
  const callTargetIso = plusDays(now, CALL_CYCLE_DTE).toISOString().slice(0, 10);
  const callMatch = nearestExpiry(callChain, callTargetIso);
  const callPrem = callMatch?.premium
    ?? estPremium({ spot: price, strike: callStrike, daysToExp: CALL_CYCLE_DTE, iv, isCall: true });

  const variants: IVCVariant[] = VARIANT_HORIZONS.map((h) => {
    const horizonDate = plusDays(now, h.days);
    const targetIso = horizonDate.toISOString().slice(0, 10);
    const putMatch = nearestExpiry(putChain, targetIso);
    const putPrem = putMatch?.premium
      ?? estPremium({ spot: price, strike: putStrike, daysToExp: h.days, iv, isCall: false });

    const callCycles = h.months;
    const putCycles = 1;
    const incomePerCycle = callContracts * callPrem * 100;
    const costPerCycle = putContracts * putPrem * 100;
    const totalIncome = incomePerCycle * callCycles;
    const totalCost = costPerCycle * putCycles;
    const net = totalIncome - totalCost;
    const coverage = totalCost > 0 ? totalIncome / totalCost
      : totalIncome > 0 ? Infinity : NaN;
    const years = h.days / 365.25;
    const annualNet = years > 0 ? net / years : NaN;
    const netAnnYield = notional > 0 && isFinite(annualNet) ? (annualNet / notional) * 100 : NaN;

    return {
      id: h.id, label: h.label, months: h.months, days: h.days,
      horizonDate,
      callPrem, putPrem,
      callPremSource: callMatch ? "real" : "estimate",
      putPremSource: putMatch ? "real" : "estimate",
      callExpiry: callMatch?.expiry ?? null,
      putExpiry: putMatch?.expiry ?? null,
      callCycles, putCycles,
      incomePerCycle, costPerCycle,
      totalIncome, totalCost, net, coverage, netAnnYield,
      notional, callStrike, putStrike,
      rank: 0, isBest: false,  // filled in next step
    };
  });

  // Rank by net dollars.
  const ranked = [...variants].sort((a, b) => b.net - a.net);
  ranked.forEach((v, i) => { v.rank = i + 1; v.isBest = i === 0; });
  return variants;  // return in horizon order, callers can re-rank
}

// ── Registry helpers (used by Compare view) ──────────────────────
// "Display" / "rank" reflect the currently SELECTED horizon of a saved
// IvC snapshot — that's what the Compare card should show, since the user
// pinned a specific variant.
function selectedFrom(state: IVCState): IVCVariant | null {
  const vars = computeAllVariants(state, [], []);
  if (vars.length === 0) return null;
  return vars.find((v) => v.id === state.selectedHorizonId) ?? vars[0];
}

export function ivcCopy(state: IVCState): string {
  const sel = selectedFrom(state);
  if (!sel) return `${state.underlying} · incomplete`;
  return `${state.underlying} · ${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))} · ${sel.label}: +${fmtMoney(sel.totalIncome, { decimals: 0 })} calls / −${fmtMoney(sel.totalCost, { decimals: 0 })} puts = ${fmtMoney(sel.net, { signed: true, decimals: 0 })} net (${fmtPct(sel.netAnnYield)} ann.) through ${fmtDate(sel.horizonDate)}`;
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
    { label: "Horizon",      value: `${sel.label} · ${fmtDate(sel.horizonDate)}`, mono: true },
    { label: "Total income", value: fmtMoney(sel.totalIncome), mono: true },
    { label: "Total cost",   value: fmtMoney(sel.totalCost),   mono: true },
    { label: "Coverage",     value: !isFinite(sel.coverage) ? "—" : sel.coverage === Infinity ? "∞" : `${sel.coverage.toFixed(2)}x`, mono: true },
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
  return `${sel.label} · ${cov} coverage`;
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
  // Re-rank for display purposes (cards sorted in horizon order but we still
  // mark the BEST one regardless of position).
  const bestId = useMemo(() => {
    const sorted = [...variants].sort((a, b) => b.net - a.net);
    return sorted[0]?.id;
  }, [variants]);

  const selected = variants.find((v) => v.id === state.selectedHorizonId) ?? variants[0];

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
        selectedId={state.selectedHorizonId}
        bestId={bestId}
        onSelect={(id) => set("selectedHorizonId", id)}
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

      <div className="ivc3-variants-grid">
        {variants.length > 0 ? variants.map((v) => (
          <VariantCard
            key={v.id}
            v={v}
            ticker={ticker}
            selected={v.id === selectedId}
            isBest={v.id === bestId}
            onClick={() => onSelect(v.id)}
          />
        )) : (
          <div className="ivc3-card empty" style={{ gridColumn: "1 / -1" }}>
            <div className="ivc3-card-empty-msg">
              Fill in ticker · shares · contracts on both sides to auto-generate variants from live chain data.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function VariantCard({
  v, ticker, selected, isBest, onClick,
}: {
  v: IVCVariant;
  ticker: string;
  selected: boolean;
  isBest: boolean;
  onClick: () => void;
}) {
  const tone = v.net >= 0 ? "pos" : "neg";
  const ann = isFinite(v.netAnnYield)
    ? `${v.netAnnYield >= 0 ? "" : "−"}${Math.abs(v.netAnnYield).toFixed(2)}%`
    : "—";
  const cov = !isFinite(v.coverage) ? "—" : v.coverage === Infinity ? "∞" : `${v.coverage.toFixed(2)}x`;
  // Compute rank within the ranked list (1 = best by net)
  return (
    <div
      className={`ivc3-card ${selected ? "selected" : ""} ${isBest ? "best" : ""}`}
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onClick(); } }}
      aria-label={`Variant ${v.label}, net ${fmtMoney(v.net, { signed: true })}`}
    >
      <div className="ivc3-card-head">
        <span className="ivc3-card-rank">{isBest ? "BEST" : v.label.toUpperCase()}</span>
        <span className="ivc3-card-horizon">{v.label}</span>
      </div>
      <div className="ivc3-card-sub">
        <span className="ticker">{ticker || "—"}</span>
        <span className="sep">·</span>
        to {fmtDate(v.horizonDate).replace(/, \d{4}$/, "")}
      </div>
      <div className={`ivc3-card-net ${tone}`}>{fmtMoney(v.net, { signed: true, decimals: 0 })}</div>
      <div className={`ivc3-card-yield ${v.net < 0 ? "neg" : ""}`}>
        {ann} <span className="muted">ann.</span>
      </div>
      <div className="ivc3-card-meta">
        <span className="row">
          <span className="lbl">cover</span>
          <span className="val">{cov}</span>
        </span>
        <span className="row">
          <span className="lbl">cycles</span>
          <span className="val">{v.callCycles}c · {v.putCycles}p</span>
        </span>
      </div>
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
            Breakdown <span className="neon">· {isBest ? "BEST" : v.label.toUpperCase()}</span>
          </div>
          <div className="ivc3-selected-title">
            {state.underlying || "—"}{" "}
            <span className="muted">· {v.label} · to {fmtDate(v.horizonDate)}</span>
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
            <b>{fmtMoney(v.incomePerCycle, { decimals: 0 })}</b>/mo ×{" "}
            <b>{fmtCount(v.callCycles)} mo</b> ={" "}
            <b className="pos">+{fmtMoney(v.totalIncome, { decimals: 0 }).replace(/^[+−]?/, "")}</b>
          </span>
          <span className="ivc3-recap-meta">
            <span className="auto-tag">{v.callPremSource === "real" ? "real" : "est"}</span>
            {v.callExpiry ? `next exp ${v.callExpiry} · ` : ""}
            ~{CALL_CYCLE_DTE} DTE · K {fmtMoney(v.callStrike, { decimals: 2 })}
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
      <div className="ivc3-bar-totals">
        <div className="side income">
          <span className="dot" />
          <span className="lbl">INCOME</span>
          <span className="cycles">{callCycles} call cycle{callCycles === 1 ? "" : "s"}</span>
          <span className="val">+{fmtMoney(totalIncome, { decimals: 0 }).replace(/^[+−]?/, "")}</span>
        </div>
        <div className="side cost">
          <span className="dot" />
          <span className="lbl">COST</span>
          <span className="cycles">{putCycles} put cycle{putCycles === 1 ? "" : "s"}</span>
          <span className="val">−{fmtMoney(totalCost, { decimals: 0 }).replace(/^[+−]?/, "")}</span>
        </div>
      </div>

      <div className="ivc3-bar-stack">
        <div className="ivc3-bar-row income">
          <div className="ivc3-bar-rail">
            <div className="ivc3-bar-fill income" style={{ width: `${incomePct}%` }}>
              {incomeCycleEdges.map((p, i) => (
                <span key={i} className="ivc3-cycle-divider" style={{ left: `${p}%` }} />
              ))}
              <span className="ivc3-bar-perchunk">{fmtMoney(incomePerCycle, { decimals: 0 })}/mo</span>
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
