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

// ── Basket model ────────────────────────────────────────────────
/** One ticker within a basket. Strike distances live on the basket so all
 *  entries share the same "calls 5% OTM, puts 10% OTM" policy. */
export interface IVCEntry {
  id: string;                 // stable across renames (used as tab key)
  label: string;              // user-editable display name ("AVGO-tight")
  /** When true, the label auto-syncs to whatever ticker the user types
   *  (so "Entry 1" becomes "NVDA" the moment they enter NVDA). Flipped to
   *  false the first time the user manually renames via the tab double-
   *  click — at that point their custom label sticks regardless of ticker. */
  labelIsAuto: boolean;
  underlying: string;
  shares: string;
  price: string;
  callContracts: string;
  putContracts: string;
  /** Composite "{callCadenceId}_{putHorizonId}" e.g. "weekly_quarterly". */
  selectedVariantId: string;
}

/** Top-level payload shape persisted in snapshots. */
export interface IVCBasketState extends Record<string, unknown> {
  basketName: string;
  /** % OTM above spot (positive). Applied across all entries. */
  callDistance: string;
  /** % below spot (positive). Applied across all entries. */
  putDistance: string;
  entries: IVCEntry[];
  /** ID of the active tab. */
  activeEntryId: string;
  /** Leaderboard sort metric. */
  sortKey: "net" | "yield" | "cov";
  /** Leaderboard "perspective" — the variant we rank tickers AT. When the
   *  pair is null/undefined we auto-pick the variant with the highest
   *  summed net across all entries (the basket-best lens). */
  perspectiveCallId?: string;
  perspectivePutId?: string;
}

const BASKET_MAX_ENTRIES = 5;

/** Generate a short random id for new entries — collision odds are fine for
 *  basket-scale (≤5 entries). */
function newEntryId(): string {
  return `e_${Math.random().toString(36).slice(2, 9)}`;
}

function makeEntry(label: string, init: Partial<IVCEntry> = {}): IVCEntry {
  return {
    id: newEntryId(),
    label,
    labelIsAuto: true,
    underlying: "",
    shares: "0",
    price: "0",
    callContracts: "0",
    putContracts: "0",
    selectedVariantId: "weekly_quarterly",
    ...init,
  };
}

/** What to show in tabs, leaderboard cards, snapshot helpers, etc. When
 *  the entry is in auto mode the displayed label always prefers the live
 *  ticker — so typing NVDA into "Entry 1" makes the tab read NVDA on the
 *  very next render, no on-change state-sync required. Only entries the
 *  user has explicitly renamed (labelIsAuto === false with a non-empty
 *  label) keep their custom string regardless of ticker. */
function displayLabel(entry: IVCEntry): string {
  if (entry.labelIsAuto === false && entry.label) return entry.label;
  return entry.underlying || entry.label || "—";
}

/** Synthesize a legacy IVCState from one entry + the basket's strike policy.
 *  All inner helpers (computeAllVariants, etc.) still consume IVCState. */
function asIVCState(entry: IVCEntry, basket: IVCBasketState): IVCState {
  return {
    underlying: entry.underlying,
    shares: entry.shares,
    price: entry.price,
    callContracts: entry.callContracts,
    callDistance: basket.callDistance,
    putContracts: entry.putContracts,
    putDistance: basket.putDistance,
    selectedVariantId: entry.selectedVariantId,
  };
}

/** Detect a legacy single-ticker payload and wrap it as a 1-entry basket.
 *  Existing snapshots in the DB pre-date the basket model, so on load any
 *  payload without an `entries` array gets transparently upgraded. */
function toBasket(payload: unknown): IVCBasketState {
  const p = (payload ?? {}) as Partial<IVCBasketState> & Partial<IVCState>;
  if (Array.isArray(p.entries) && typeof p.basketName === "string") {
    // already basket-shaped; ensure activeEntryId points at a live entry,
    // and backfill labelIsAuto for entries persisted before the field existed.
    const activeOk = p.entries.some((e) => e.id === p.activeEntryId);
    const entries = p.entries.map((e) => ({
      ...e,
      labelIsAuto:
        typeof e.labelIsAuto === "boolean"
          ? e.labelIsAuto
          // Heuristic for pre-field entries: a label that equals the
          // ticker or matches the auto-default counts as still auto.
          : (e.label === e.underlying || /^Entry \d+$/.test(e.label)),
    }));
    return {
      basketName: p.basketName,
      callDistance: p.callDistance ?? "1.0",
      putDistance: p.putDistance ?? "2.0",
      entries,
      activeEntryId: activeOk ? (p.activeEntryId as string) : (entries[0]?.id ?? ""),
      sortKey: (p.sortKey as IVCBasketState["sortKey"]) ?? "net",
      perspectiveCallId: p.perspectiveCallId,
      perspectivePutId: p.perspectivePutId,
    };
  }
  // legacy single-ticker payload → wrap
  const ticker = (p.underlying ?? "").trim().toUpperCase();
  const entry = makeEntry(ticker || "Entry 1", {
    underlying: ticker,
    shares: p.shares ?? "0",
    price: p.price ?? "0",
    callContracts: p.callContracts ?? "0",
    putContracts: p.putContracts ?? "0",
    selectedVariantId: p.selectedVariantId ?? "weekly_quarterly",
  });
  return {
    basketName: ticker ? `${ticker} basket` : "Untitled basket",
    callDistance: p.callDistance ?? "1.0",
    putDistance: p.putDistance ?? "2.0",
    entries: [entry],
    activeEntryId: entry.id,
    sortKey: "net",
  };
}

const _seedEntry = makeEntry("SPY", {
  underlying: "SPY",
  shares: "500",
  price: "655.06",
  callContracts: "5",
  putContracts: "5",
});

export const ivcInitial: IVCBasketState = {
  basketName: "Untitled basket",
  callDistance: "1.0",
  putDistance: "2.0",
  entries: [_seedEntry],
  activeEntryId: _seedEntry.id,
  sortKey: "net",
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
  /** Call cycles per month (4.33 for weekly, 21 for daily, 1 for monthly, …). */
  callPerMonth: number;
  rank: number;
  isBest: boolean;
}

function plusDays(d: Date, n: number): Date {
  const r = new Date(d); r.setDate(r.getDate() + n); return r;
}

/** Crude back-solve of implied vol from a near-ATM call premium, using the
 *  inverse of our estPremium() formula so the math is internally
 *  consistent. Picks the listed contract nearest 30 DTE within a 10–60 day
 *  window (anything shorter is too gamma-warped, anything longer not
 *  representative of "current" IV). Returns null when the chain doesn't
 *  have anything in that window. Used purely for the elevation chip on
 *  leaderboard cards — when live IV is well above the 1y baseline we
 *  flag earnings-style distortions. */
function backsolveLiveIV(
  callChain: OptionContractQuote[],
  spot: number,
  strike: number,
  now: Date = new Date(),
): number | null {
  if (!callChain.length || !isFinite(spot) || spot <= 0) return null;
  const today = now.getTime();
  let best: { c: OptionContractQuote; daysOff: number } | null = null;
  for (const c of callChain) {
    const t = new Date(c.expiry + "T00:00:00Z").getTime();
    const days = (t - today) / 86400000;
    if (days < 10 || days > 60) continue;
    const daysOff = Math.abs(days - 30);
    if (!best || daysOff < best.daysOff) best = { c, daysOff };
  }
  if (!best) return null;
  const days = (new Date(best.c.expiry + "T00:00:00Z").getTime() - today) / 86400000;
  if (days <= 0) return null;
  const T = days / 365;
  const sqrtT = Math.sqrt(T);
  const intrinsic = Math.max(0, spot - strike);
  const timeValue = Math.max(0.01, best.c.premium - intrinsic);
  const iv = timeValue / (0.4 * spot * sqrtT);
  return isFinite(iv) && iv > 0 ? iv : null;
}

/** Decide which call cadences to surface based on actual expiry density
 *  in the next 14 days. Density is more robust than gap-spacing: a single
 *  far-out Friday in the window doesn't poison the signal, and one extra
 *  near-term Mon/Wed still bumps a name into 3×wk territory.
 *
 *  Counts unique expiries in the 14-day window:
 *     ≥ 9 expiries  → Daily exists   (SPY/QQQ/SPX — Mon-Fri × 2 weeks ≈ 10)
 *     ≥ 5 expiries  → 3×wk exists    (AVGO/NVDA/TSLA — M-W-F × 2 weeks ≈ 6)
 *     anything less → Weekly only    (AAPL/MSFT — 2 Fridays in 14 days)
 *
 *  Weekly / Bi / Monthly are always allowed — they can be synthesized from
 *  any chain that has a future Friday. */
function callCadencesAvailable(callChain: OptionContractQuote[]): typeof CALL_CADENCES {
  if (callChain.length === 0) {
    return CALL_CADENCES.filter((c) => !c.requiresShortDated);
  }
  const todayMs = Date.now();
  const windowMs = todayMs + 14 * 86400000;
  const expiriesInWindow = new Set(
    callChain
      .map((c) => c.expiry)
      .filter((iso) => {
        const t = new Date(iso + "T00:00:00Z").getTime();
        return t >= todayMs && t <= windowMs;
      }),
  ).size;

  const hasDaily   = expiriesInWindow >= 9;
  const hasThriceW = expiriesInWindow >= 5;

  return CALL_CADENCES.filter((c) => {
    if (c.id === "daily") return hasDaily;
    if (c.id === "thrice-weekly") return hasThriceW;
    return true;
  });
}

function computeAllVariants(
  state: IVCState,
  callChain: OptionContractQuote[],
  putChain: OptionContractQuote[],
  now: Date = new Date(),
  opts: { pricingMode?: "live" | "estimator" } = {},
): IVCVariant[] {
  // "estimator" forces all premiums through the Black-Scholes estimator
  // with our 1y-baseline IV_HINTS — used by the leaderboard so earnings-
  // elevated chains don't artificially win.
  const forceEstimator = opts.pricingMode === "estimator";
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
    const match = forceEstimator ? null : nearestExpiry(callChain, targetIso);
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
    const putMatch = forceEstimator ? null : nearestExpiry(putChain, putTargetIso);
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
        callPerMonth: cad.perMonth,
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
// "Display" / "rank" reflect the currently SELECTED horizon for each entry
// in the basket. Snapshots persist the whole basket, so registry helpers
// roll up per-entry numbers into basket-level totals.
function selectedFrom(state: IVCState): IVCVariant | null {
  const vars = computeAllVariants(state, [], []);
  if (vars.length === 0) return null;
  return vars.find((v) => v.id === state.selectedVariantId) ?? vars[0];
}

/** Compute the currently-selected variant for every entry in the basket,
 *  using estimator-only pricing (chain-less). For snapshot helpers we don't
 *  have access to live chains; the estimator is good enough for the headline
 *  numbers and matches what the user saw at save time within a small fudge. */
interface BasketRollup {
  entryCount: number;
  totals: { net: number; income: number; cost: number; notional: number };
  weightedAnnYield: number;       // notional-weighted across entries
  best: { entry: IVCEntry; variant: IVCVariant } | null;
}
function rollup(basket: IVCBasketState): BasketRollup {
  const rows: Array<{ entry: IVCEntry; variant: IVCVariant }> = [];
  for (const entry of basket.entries) {
    const v = selectedFrom(asIVCState(entry, basket));
    if (v) rows.push({ entry, variant: v });
  }
  const totals = { net: 0, income: 0, cost: 0, notional: 0 };
  let weightedNumer = 0;
  for (const { variant } of rows) {
    if (isFinite(variant.net)) totals.net += variant.net;
    if (isFinite(variant.totalIncome)) totals.income += variant.totalIncome;
    if (isFinite(variant.totalCost)) totals.cost += variant.totalCost;
    if (isFinite(variant.notional)) totals.notional += variant.notional;
    if (isFinite(variant.netAnnYield) && isFinite(variant.notional)) {
      weightedNumer += variant.netAnnYield * variant.notional;
    }
  }
  const weightedAnnYield = totals.notional > 0 ? weightedNumer / totals.notional : NaN;
  const best = rows.reduce<{ entry: IVCEntry; variant: IVCVariant } | null>((acc, r) => {
    if (!isFinite(r.variant.net)) return acc;
    if (!acc || r.variant.net > acc.variant.net) return r;
    return acc;
  }, null);
  return { entryCount: rows.length, totals, weightedAnnYield, best };
}

export function ivcCopy(payload: unknown): string {
  const basket = toBasket(payload);
  const r = rollup(basket);
  if (r.entryCount === 0) return `${basket.basketName} · empty basket`;
  const head = `${basket.basketName} · ${r.entryCount} ticker${r.entryCount === 1 ? "" : "s"} · ${fmtMoney(r.totals.net, { signed: true, decimals: 0 })} net`;
  const lines = basket.entries
    .map((e) => {
      const v = selectedFrom(asIVCState(e, basket));
      const lbl = displayLabel(e);
      if (!v) return `  · ${lbl} (${e.underlying || "—"}) · incomplete`;
      return `  · ${lbl} (${e.underlying}) ${v.callCadenceLabel}×${v.putHorizonLabel}: ${fmtMoney(v.net, { signed: true, decimals: 0 })} (${fmtPct(v.netAnnYield)} ann)`;
    })
    .join("\n");
  return `${head}\n${lines}`;
}

export function ivcDisplay(payload: unknown): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const r = rollup(toBasket(payload));
  if (r.entryCount === 0 || !isFinite(r.totals.net)) return { value: "—", tone: "muted" };
  return {
    value: fmtMoney(r.totals.net, { signed: true }),
    tone: r.totals.net > 0 ? "pos" : r.totals.net < 0 ? "neg" : "neon",
  };
}

export function ivcFields(payload: unknown): Array<{ label: string; value: string; mono?: boolean }> {
  const basket = toBasket(payload);
  const r = rollup(basket);
  if (r.entryCount === 0) {
    return [
      { label: "Basket",  value: basket.basketName || "—", mono: true },
      { label: "Status",  value: "no entries", mono: true },
    ];
  }
  const bestLine = r.best
    ? `${displayLabel(r.best.entry)} · ${r.best.variant.callCadenceLabel}×${r.best.variant.putHorizonLabel}`
    : "—";
  return [
    { label: "Basket",       value: basket.basketName, mono: true },
    { label: "Tickers",      value: String(r.entryCount), mono: true },
    { label: "Total net",    value: fmtMoney(r.totals.net, { signed: true }), mono: true },
    { label: "Total income", value: fmtMoney(r.totals.income), mono: true },
    { label: "Total cost",   value: fmtMoney(r.totals.cost), mono: true },
    { label: "Ann. yield",   value: fmtPct(r.weightedAnnYield), mono: true },
    { label: "Best",         value: bestLine, mono: true },
  ];
}

export function ivcUpsertKey(payload: unknown): string | null {
  const name = toBasket(payload).basketName?.trim();
  return name || null;
}

export function ivcRank(payload: unknown): { score: number; label: string } | null {
  const r = rollup(toBasket(payload));
  if (!isFinite(r.totals.net)) return null;
  return { score: r.totals.net, label: "basket net $" };
}

export function ivcCardLine(payload: unknown): string {
  const basket = toBasket(payload);
  const r = rollup(basket);
  if (r.entryCount === 0) return "empty basket";
  if (!r.best) return `${r.entryCount} tickers · pending`;
  return `${r.entryCount} tickers · best ${displayLabel(r.best.entry)} ${r.best.variant.callCadenceLabel}×${r.best.variant.putHorizonLabel}`;
}

// ── Body — basket shell ──────────────────────────────────────────
/** Top-level basket page: header + policy strikes + leaderboard + tabs +
 *  active EntryView. Each entry computes its own variants using a chain
 *  fetched once by the hoisted `useBasketChains` hook (one parallel fetch
 *  per entry). */
export function IncomeVsCostCalc({
  state,
  setState,
}: {
  // Accept either basket or legacy single-ticker payload — we self-heal.
  state: IVCBasketState;
  setState: (next: IVCBasketState | ((prev: IVCBasketState) => IVCBasketState)) => void;
}) {
  // Self-heal legacy single-ticker payloads. The store's useLiveState was
  // populated from the same default we export (ivcInitial = basket), but
  // snapshots saved before the refactor still come back in single-ticker
  // shape — wrap them into a 1-entry basket transparently.
  const basket = useMemo(() => toBasket(state), [state]);
  const isLegacy = !("entries" in (state ?? {}));
  // Persist the migrated shape so future renders / saves see the basket
  // directly. We render with `basket` either way, so there's no flicker —
  // and crucially, no early return (which would skip later hooks and
  // trigger React's hook-count mismatch).
  useEffect(() => {
    if (isLegacy) setState(basket);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isLegacy]);

  const update = (next: Partial<IVCBasketState>) => setState({ ...basket, ...next });
  const updateEntry = (entryId: string, updater: (e: IVCEntry) => IVCEntry) =>
    setState({
      ...basket,
      entries: basket.entries.map((e) => (e.id === entryId ? updater(e) : e)),
    });
  const addEntry = () => {
    if (basket.entries.length >= BASKET_MAX_ENTRIES) return;
    const e = makeEntry(`Entry ${basket.entries.length + 1}`);
    setState({ ...basket, entries: [...basket.entries, e], activeEntryId: e.id });
  };
  const removeEntry = (entryId: string) => {
    const rest = basket.entries.filter((e) => e.id !== entryId);
    if (rest.length === 0) return;  // never zero — basket must hold ≥1
    const activeId = basket.activeEntryId === entryId ? rest[0].id : basket.activeEntryId;
    setState({ ...basket, entries: rest, activeEntryId: activeId });
  };
  const renameEntry = (entryId: string, label: string) =>
    updateEntry(entryId, (e) => {
      const trimmed = label.trim();
      // Empty rename = "go back to auto" — restore ticker-tracking.
      if (!trimmed) {
        return { ...e, label: e.underlying || "Entry", labelIsAuto: true };
      }
      // Any non-empty manual label freezes the auto-sync.
      return { ...e, label: trimmed, labelIsAuto: false };
    });
  const setActive = (entryId: string) => setState({ ...basket, activeEntryId: entryId });

  // Hoisted chain fetching — one debounced fetch per entry, in parallel.
  const chains = useBasketChains(basket);

  // Per-entry computed variants (estimator fallback when chain absent).
  const variantsByEntry = useMemo(() => {
    const map = new Map<string, IVCVariant[]>();
    for (const e of basket.entries) {
      const s = asIVCState(e, basket);
      const c = chains[e.id];
      map.set(e.id, computeAllVariants(s, c?.calls ?? [], c?.puts ?? []));
    }
    return map;
  }, [basket, chains]);

  // ── "Fair-value" variants for the leaderboard ranking ──
  // The leaderboard MUST rank apples-to-apples or earnings-elevated names
  // (AVGO into earnings, etc.) artificially win on inflated chain premiums.
  // We re-price every premium from the estimator at the ticker's 1y-baseline
  // IV (IV_HINTS), ignoring live chain prices entirely. The cadence-
  // availability filter still uses the live call chain so Daily/3×wk
  // correctly drop out for tickers that don't list them. Per-ticker
  // breakdown below still uses live prices.
  const variantsByEntryFair = useMemo(() => {
    const map = new Map<string, IVCVariant[]>();
    for (const e of basket.entries) {
      const s = asIVCState(e, basket);
      const c = chains[e.id];
      map.set(e.id, computeAllVariants(s, c?.calls ?? [], c?.puts ?? [], new Date(), { pricingMode: "estimator" }));
    }
    return map;
  }, [basket, chains]);

  const activeEntry =
    basket.entries.find((e) => e.id === basket.activeEntryId) ?? basket.entries[0];
  const activeVariants = activeEntry ? variantsByEntry.get(activeEntry.id) ?? [] : [];
  const activeBestId = activeVariants[0]?.id;
  const activeSelected =
    activeVariants.find((v) => v.id === activeEntry?.selectedVariantId) ?? activeVariants[0];
  const activeChains = activeEntry ? chains[activeEntry.id] : undefined;
  const lastFetchedTxt = activeChains?.fetchedAt
    ? `${Math.max(1, Math.round((Date.now() - activeChains.fetchedAt) / 1000))}s ago`
    : "—";

  return (
    <div className="cyc ivc3 ivc3-basket">
      <p className="cyc-desc">
        Run covered calls + protective puts across up to {BASKET_MAX_ENTRIES} tickers at once.
        Strike policy is basket-wide; cadence × horizon is picked per ticker. Leaderboard ranks
        the basket — click any card to jump.
      </p>

      <BasketHeader
        basket={basket}
        onRename={(name) => update({ basketName: name })}
      />

      <PolicyStrikes
        basket={basket}
        onSetCall={(v) => update({ callDistance: v })}
        onSetPut={(v) => update({ putDistance: v })}
      />

      <Leaderboard
        basket={basket}
        variantsByEntry={variantsByEntryFair}
        chains={chains}
        onSetPerspective={(callId, putId) =>
          update({ perspectiveCallId: callId, perspectivePutId: putId })
        }
        onJump={(entryId, variantId) =>
          setState({
            ...basket,
            activeEntryId: entryId,
            entries: basket.entries.map((e) =>
              e.id === entryId ? { ...e, selectedVariantId: variantId } : e,
            ),
          })
        }
        onAddSlot={addEntry}
      />

      <EntryTabs
        basket={basket}
        onActivate={setActive}
        onAdd={addEntry}
        onRemove={removeEntry}
        onRename={renameEntry}
      />

      {activeEntry && (
        <EntryView
          key={activeEntry.id}
          entry={activeEntry}
          basket={basket}
          chains={activeChains}
          variants={activeVariants}
          bestId={activeBestId}
          selected={activeSelected}
          lastFetchedTxt={lastFetchedTxt}
          onUpdate={(updater) => updateEntry(activeEntry.id, updater)}
        />
      )}
    </div>
  );
}

// ── Hoisted chain fetching ───────────────────────────────────────
interface EntryChains {
  calls: OptionContractQuote[];
  puts: OptionContractQuote[];
  fetchedAt: number;
}
type ChainsState = Record<string, EntryChains | undefined>;

/** Maintain one chain-pair per basket entry. Debounced 700ms; refetches only
 *  when an entry's (ticker, callStrike, putStrike) tuple changes. Fetches
 *  for all entries run in parallel. */
function useBasketChains(basket: IVCBasketState): ChainsState {
  const [chains, setChains] = useState<ChainsState>({});
  const lastKeysRef = useRef<Record<string, string>>({});
  const timersRef = useRef<Record<string, number>>({});

  useEffect(() => {
    for (const entry of basket.entries) {
      const price = Number(entry.price);
      const cd = Number(basket.callDistance);
      const pd = Number(basket.putDistance);
      if (!entry.underlying || !isFinite(price) || price <= 0 || !isFinite(cd) || !isFinite(pd)) continue;
      const callStrike = price * (1 + cd / 100);
      const putStrike = price * (1 - pd / 100);
      const key = `${entry.underlying}|${callStrike.toFixed(2)}|${putStrike.toFixed(2)}`;
      if (lastKeysRef.current[entry.id] === key) continue;
      if (timersRef.current[entry.id]) window.clearTimeout(timersRef.current[entry.id]);
      const entryId = entry.id;
      const underlying = entry.underlying;
      timersRef.current[entryId] = window.setTimeout(async () => {
        lastKeysRef.current[entryId] = key;
        try {
          const [calls, puts] = await Promise.all([
            pullOptionChain(underlying, callStrike, "call").catch(() => [] as OptionContractQuote[]),
            pullOptionChain(underlying, putStrike, "put").catch(() => [] as OptionContractQuote[]),
          ]);
          setChains((prev) => ({ ...prev, [entryId]: { calls, puts, fetchedAt: Date.now() } }));
        } catch { /* swallow */ }
      }, 700);
    }
  }, [basket]);

  // Drop stale chains when entries are removed (keeps the map bounded).
  const liveKey = basket.entries.map((e) => e.id).join(",");
  useEffect(() => {
    setChains((prev) => {
      const live = new Set(basket.entries.map((e) => e.id));
      let changed = false;
      const next: ChainsState = {};
      for (const k of Object.keys(prev)) {
        if (live.has(k)) next[k] = prev[k];
        else changed = true;
      }
      return changed ? next : prev;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveKey]);

  return chains;
}

// ── Basket header (name + count) ─────────────────────────────────
function BasketHeader({
  basket, onRename,
}: { basket: IVCBasketState; onRename: (name: string) => void }) {
  return (
    <div className="ivc3-basket-head">
      <div className="ivc3-basket-name-wrap">
        <span className="ivc3-basket-eyebrow">BASKET</span>
        <input
          className="ivc3-basket-name"
          value={basket.basketName}
          onChange={(e) => onRename(e.target.value)}
          placeholder="Untitled basket"
          aria-label="Basket name"
        />
      </div>
      <div className="ivc3-basket-meta">
        {basket.entries.length}/{BASKET_MAX_ENTRIES} tickers
      </div>
    </div>
  );
}

// ── Policy strikes (basket-wide) ─────────────────────────────────
function PolicyStrikes({
  basket, onSetCall, onSetPut,
}: {
  basket: IVCBasketState;
  onSetCall: (v: string) => void;
  onSetPut: (v: string) => void;
}) {
  return (
    <div className="ivc3-policy">
      <span className="ivc3-policy-eyebrow">POLICY</span>
      <label className="ivc3-policy-field">
        <span className="lbl">Calls</span>
        <input
          type="text" inputMode="decimal"
          value={basket.callDistance}
          onChange={(e) => onSetCall(e.target.value)}
          aria-label="Call OTM distance"
        />
        <span className="suffix">% OTM</span>
      </label>
      <label className="ivc3-policy-field">
        <span className="lbl">Puts</span>
        <input
          type="text" inputMode="decimal"
          value={basket.putDistance}
          onChange={(e) => onSetPut(e.target.value)}
          aria-label="Put distance below spot"
        />
        <span className="suffix">% below</span>
      </label>
      <span className="ivc3-policy-meta">applies to all tickers</span>
    </div>
  );
}

// ── Leaderboard strip — variant-pivoted, fair-IV ranking ────────
/** Rank tickers AT A SPECIFIC variant (the "perspective"). The perspective
 *  is picked via two pill rows (Calls cadence + Puts horizon). Only
 *  cadences at least one ticker in the basket can actually run are
 *  surfaced — no point offering "Daily" when nobody has daily options.
 *
 *  Premium values come from the estimator with our 1y-baseline IV map, so
 *  earnings-elevated names (e.g. AVGO into earnings) don't artificially
 *  win on inflated live premiums. The per-ticker breakdown below still
 *  uses live chain prices — only the cross-basket ranking is normalised. */
function Leaderboard({
  basket, variantsByEntry, chains, onSetPerspective, onJump, onAddSlot,
}: {
  basket: IVCBasketState;
  variantsByEntry: Map<string, IVCVariant[]>;
  chains: ChainsState;
  onSetPerspective: (callId: string, putId: string) => void;
  onJump: (entryId: string, variantId: string) => void;
  onAddSlot: () => void;
}) {
  // ── Which cadences does ANY basket entry actually offer? ──
  // If nobody has daily expiries, don't even surface the Daily pill.
  // Weekly / Bi / Monthly are always allowed (synthesizable from any chain).
  const availableCallCadences = useMemo(() => {
    const present = new Set<string>();
    for (const entry of basket.entries) {
      const c = chains[entry.id];
      if (!c) continue;
      for (const cad of callCadencesAvailable(c.calls)) present.add(cad.id);
    }
    // Always allow non-short-dated cadences even before chains arrive.
    for (const cad of CALL_CADENCES) {
      if (!cad.requiresShortDated) present.add(cad.id);
    }
    return CALL_CADENCES.filter((c) => present.has(c.id));
  }, [basket.entries, chains]);

  // Auto-pick the variant that maximises summed net across entries — the
  // "basket-best" lens. Only considers cadences the basket can run.
  const autoPivot = useMemo(() => {
    let best = { call: "weekly", put: "quarterly", score: -Infinity };
    for (const cad of availableCallCadences) {
      for (const h of PUT_HORIZONS) {
        const id = `${cad.id}_${h.id}`;
        let sum = 0;
        let any = false;
        for (const entry of basket.entries) {
          const v = variantsByEntry.get(entry.id)?.find((x) => x.id === id);
          if (v && isFinite(v.net)) { sum += v.net; any = true; }
        }
        if (any && sum > best.score) best = { call: cad.id, put: h.id, score: sum };
      }
    }
    return best;
  }, [basket.entries, variantsByEntry, availableCallCadences]);

  // Use user-set pivot, fall back to auto — but force it onto an available
  // cadence if the stored one (e.g. "daily" from an earlier session) is no
  // longer offered by any ticker in the current basket.
  let pivotCall = basket.perspectiveCallId ?? autoPivot.call;
  if (!availableCallCadences.some((c) => c.id === pivotCall)) pivotCall = autoPivot.call;
  const pivotPut = basket.perspectivePutId ?? autoPivot.put;
  const pivotId = `${pivotCall}_${pivotPut}`;
  const pivotCallShort = CALL_CADENCES.find((c) => c.id === pivotCall)?.short ?? pivotCall;
  const pivotPutShort = PUT_HORIZONS.find((h) => h.id === pivotPut)?.short ?? pivotPut;
  const pivotPutDays = PUT_HORIZONS.find((h) => h.id === pivotPut)?.days ?? 91;

  // For each entry, pull the variant at the pivot. If it's missing, figure
  // out WHY (cadence unavailable for this ticker?) so the n/a card can
  // explain itself rather than silently disappearing.
  type Row = {
    entry: IVCEntry;
    variant: IVCVariant | null;
    excludeReason: string | null;
  };
  const rows: Row[] = basket.entries.map((entry) => {
    const variants = variantsByEntry.get(entry.id) ?? [];
    const variant = variants.find((v) => v.id === pivotId) ?? null;
    let excludeReason: string | null = null;
    if (!variant) {
      const c = chains[entry.id];
      if (!entry.underlying || Number(entry.price) <= 0) {
        excludeReason = "needs ticker + price";
      } else if (c) {
        const available = callCadencesAvailable(c.calls).map((x) => x.id);
        if (!available.includes(pivotCall)) {
          const cadLabel = CALL_CADENCES.find((x) => x.id === pivotCall)?.label ?? pivotCall;
          excludeReason = `no ${cadLabel.toLowerCase()} options listed`;
        } else {
          excludeReason = "variant pending";
        }
      } else {
        excludeReason = "loading chain…";
      }
    }
    return { entry, variant, excludeReason };
  });

  // Sort by net (single canonical metric now — the three sorts produced
  // basically the same order for any realistic basket, and the toggle was
  // adding noise without insight).
  const scoreFor = (v: IVCVariant | null): number => {
    if (!v) return -Infinity;
    return isFinite(v.net) ? v.net : -Infinity;
  };
  const ranked = [...rows].sort((a, b) => scoreFor(b.variant) - scoreFor(a.variant));
  const competing = ranked.filter((r) => r.variant != null);
  const bestScore = scoreFor(competing[0]?.variant ?? null);

  let nextRank = 1;
  const ranks = new Map<string, number>();
  for (const r of ranked) {
    if (r.variant) ranks.set(r.entry.id, nextRank++);
  }

  // Live IV per entry — back-solved from each chain's near-ATM call.
  // Compared to our 1y-baseline (IV_HINTS) in the card to flag elevated
  // levels (earnings catalyst, etc.).
  const liveIVByEntry = useMemo(() => {
    const m = new Map<string, number | null>();
    for (const e of basket.entries) {
      const c = chains[e.id];
      const price = Number(e.price);
      const cd = Number(basket.callDistance);
      const callStrike = isFinite(price) && isFinite(cd) ? price * (1 + cd / 100) : NaN;
      m.set(e.id, c ? backsolveLiveIV(c.calls, price, callStrike) : null);
    }
    return m;
  }, [basket.entries, chains, basket.callDistance]);

  // Cents/share delta against the immediate neighbor in the ranking — gives
  // each card a "by how much?" frame (e.g. "+$72k over #2", "−$14k vs #1").
  const deltaForRank = (i: number): number | null => {
    const me = competing[i]?.variant;
    if (!me) return null;
    if (i === 0) {
      // Top card → delta vs #2
      const next = competing[1]?.variant;
      if (!next) return null;
      return me.net - next.net;
    }
    const prev = competing[i - 1]?.variant;
    if (!prev) return null;
    return me.net - prev.net;
  };

  return (
    <div className="ivc3-leader">
      <div className="ivc3-leader-head">
        <div className="ivc3-leader-eyebrow">
          LEADERBOARD <span className="muted">· {basket.entries.length} of {BASKET_MAX_ENTRIES} · fair-value ranking (1y-baseline IV)</span>
        </div>
        {basket.perspectiveCallId == null && (
          <span className="ivc3-leader-auto">⚲ auto-picked perspective</span>
        )}
      </div>

      {/* Perspective picker — two pill rows, one click to pivot */}
      <div className="ivc3-leader-pills">
        <div className="ivc3-leader-pill-row">
          <span className="row-lbl">Calls</span>
          {availableCallCadences.map((c) => (
            <button
              key={c.id}
              type="button"
              className={`ivc3-leader-pill${pivotCall === c.id ? " on" : ""}`}
              onClick={() => onSetPerspective(c.id, pivotPut)}
            >
              {c.label}
            </button>
          ))}
        </div>
        <div className="ivc3-leader-pill-row">
          <span className="row-lbl">Puts</span>
          {PUT_HORIZONS.map((h) => (
            <button
              key={h.id}
              type="button"
              className={`ivc3-leader-pill${pivotPut === h.id ? " on" : ""}`}
              onClick={() => onSetPerspective(pivotCall, h.id)}
            >
              {h.label}
            </button>
          ))}
        </div>
      </div>

      <div className="ivc3-leader-strip">
        {ranked.map((r) => {
          const rankIdx = competing.findIndex((c) => c.entry.id === r.entry.id);
          const delta = rankIdx >= 0 ? deltaForRank(rankIdx) : null;
          return (
            <LeaderboardCard
              key={r.entry.id}
              rank={ranks.get(r.entry.id) ?? null}
              isBest={r.variant != null && scoreFor(r.variant) === bestScore && isFinite(bestScore)}
              isActive={r.entry.id === basket.activeEntryId}
              entry={r.entry}
              variant={r.variant}
              excludeReason={r.excludeReason}
              pivotCallShort={pivotCallShort}
              pivotPutShort={pivotPutShort}
              pivotPutDays={pivotPutDays}
              liveIV={liveIVByEntry.get(r.entry.id) ?? null}
              deltaToNeighbor={delta}
              isTopRank={rankIdx === 0}
              onClick={() => {
                if (r.variant) onJump(r.entry.id, r.variant.id);
              }}
            />
          );
        })}
        {Array.from({ length: Math.max(0, BASKET_MAX_ENTRIES - ranked.length) }).map((_, i) => (
          <button
            key={`empty-${i}`}
            type="button"
            className="ivc3-lead-card empty"
            onClick={onAddSlot}
          >
            <span className="ivc3-lead-empty">+ add</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function LeaderboardCard({
  rank, isBest, isActive, entry, variant, excludeReason,
  pivotCallShort, pivotPutShort, pivotPutDays,
  liveIV, deltaToNeighbor, isTopRank, onClick,
}: {
  rank: number | null;
  isBest: boolean;
  isActive: boolean;
  entry: IVCEntry;
  variant: IVCVariant | null;
  excludeReason: string | null;
  pivotCallShort: string;
  pivotPutShort: string;
  pivotPutDays: number;
  liveIV: number | null;
  deltaToNeighbor: number | null;
  isTopRank: boolean;
  onClick: () => void;
}) {
  const label = displayLabel(entry);
  const baselineIV = ivFor(entry.underlying);
  // IV elevation flag — live chain IV vs our 1y baseline. >1.25× = visibly
  // elevated (typical of an imminent catalyst like earnings).
  const ivRatio = liveIV != null && baselineIV > 0 ? liveIV / baselineIV : null;
  const ivElevated = ivRatio != null && ivRatio >= 1.25;
  const ivSubdued = ivRatio != null && ivRatio <= 0.8;

  if (!variant) {
    return (
      <button
        type="button"
        className={`ivc3-lead-card na${isActive ? " active" : ""}`}
        onClick={onClick}
      >
        <div className="ivc3-lead-rank">n/a</div>
        <div className="ivc3-lead-label">{label}</div>
        <div className="ivc3-lead-na-reason">{excludeReason ?? "not available"}</div>
        <div className="ivc3-lead-footline">
          IV <b>{Math.round(baselineIV * 100)}%</b>
          <span className="muted"> (1y avg)</span>
        </div>
      </button>
    );
  }

  const tone = variant.net >= 0 ? "pos" : "neg";
  const total = (variant.totalIncome || 0) + (variant.totalCost || 0);
  const incPct = total > 0 ? (variant.totalIncome / total) * 100 : 0;
  const ann = isFinite(variant.netAnnYield)
    ? `${variant.netAnnYield >= 0 ? "" : "−"}${Math.abs(variant.netAnnYield).toFixed(1)}%`
    : "—";
  const cov = !isFinite(variant.coverage) ? "—"
    : variant.coverage === Infinity ? "∞"
    : `${variant.coverage.toFixed(2)}×`;

  // Cycles needed for cumulative call income to cover the put cost.
  const cyclesToCoverPut =
    variant.incomePerCycle > 0
      ? Math.ceil(variant.totalCost / variant.incomePerCycle)
      : Infinity;
  // Pluralise the cycle unit ("wk" → "wks", but "day" → "days").
  const cycleUnit = variant.callPerUnit.replace("/", "");
  const cycleUnitPlural =
    cycleUnit === "day" ? "days" :
    cycleUnit === "run" ? "runs" :
    cycleUnit + "s";
  const horizonWord =
    pivotPutDays >= 350 ? "year" :
    pivotPutDays >= 170 ? "6 months" :
    pivotPutDays >= 110 ? "4 months" :
    pivotPutDays >= 80  ? "quarter" : "month";
  const incomePerCycleTxt = fmtMoney(variant.incomePerCycle, { decimals: 0 });

  let narrative: string;
  if (variant.net < 0) {
    narrative = `Puts cost ${fmtMoney(variant.totalCost, { decimals: 0 })} but calls only earn ${fmtMoney(variant.totalIncome, { decimals: 0 })} this ${horizonWord}.`;
  } else if (!isFinite(cyclesToCoverPut)) {
    narrative = `Calls earn ${incomePerCycleTxt} per ${cycleUnit} — no put to fund.`;
  } else {
    narrative = `Each ${pivotCallShort} call earns ${incomePerCycleTxt}. Recoups the ${pivotPutShort} put in ${cyclesToCoverPut} ${cyclesToCoverPut === 1 ? cycleUnit : cycleUnitPlural}.`;
  }

  // "Beats #2 by $X" / "Behind #1 by $X" — anchors the gap.
  let deltaLine: string | null = null;
  if (deltaToNeighbor != null && isFinite(deltaToNeighbor)) {
    const abs = Math.abs(deltaToNeighbor);
    if (abs >= 100) {
      deltaLine = isTopRank
        ? `Beats #2 by ${fmtMoney(abs, { decimals: 0 })}.`
        : `Behind #${(rank ?? 2) - 1} by ${fmtMoney(abs, { decimals: 0 })}.`;
    }
  }

  return (
    <button
      type="button"
      className={`ivc3-lead-card tone-${tone}${isBest ? " best" : ""}${isActive ? " active" : ""}`}
      onClick={onClick}
      title="Click to open this ticker's tab"
    >
      <div className="ivc3-lead-rank">
        {isBest ? "⭐ #1" : (rank != null ? `#${rank}` : "—")}
        {isActive && <span className="ivc3-lead-active-dot" aria-label="active tab">●</span>}
      </div>
      <div className="ivc3-lead-label">{label}</div>

      <div className="ivc3-lead-hero">
        {fmtMoney(variant.net, { signed: true, decimals: 0 })}
        <span className="ivc3-lead-hero-sub">over {horizonWord}</span>
      </div>

      {/* Context line — concrete strikes + capital at risk */}
      <div className="ivc3-lead-context">
        <span>K <b>{fmtMoney(variant.callStrike, { decimals: 0 })}</b> call</span>
        <span className="sep">·</span>
        <span>K <b>{fmtMoney(variant.putStrike, { decimals: 0 })}</b> put</span>
        <span className="sep">·</span>
        <span><b>{fmtMoney(variant.notional, { decimals: 0 })}</b> notional</span>
      </div>

      <div className="ivc3-lead-mini">
        <div className="bar inc" style={{ width: `${incPct}%` }} />
        <div className="bar cost" style={{ width: `${100 - incPct}%` }} />
      </div>

      <p className="ivc3-lead-narrative">{narrative}</p>
      {deltaLine && (
        <p className={`ivc3-lead-delta ${isTopRank ? "pos" : "neg"}`}>{deltaLine}</p>
      )}

      <div className="ivc3-lead-footline">
        Yield <b>{ann}/y</b> · Cov <b>{cov}</b> · IV <b>{Math.round(baselineIV * 100)}%</b>
        <span className="muted"> (1y avg)</span>
        {ivElevated && (
          <span className="ivc3-lead-iv-chip elevated" title="Live chain IV is significantly above the 1y baseline — often an earnings catalyst. Real premiums today are higher than what this fair-value ranking assumes.">
            ↑ live {Math.round((liveIV ?? 0) * 100)}%
          </span>
        )}
        {ivSubdued && (
          <span className="ivc3-lead-iv-chip subdued" title="Live chain IV is below the 1y baseline — quieter than usual.">
            ↓ live {Math.round((liveIV ?? 0) * 100)}%
          </span>
        )}
      </div>
    </button>
  );
}

// ── Tab strip ────────────────────────────────────────────────────
function EntryTabs({
  basket, onActivate, onAdd, onRemove, onRename,
}: {
  basket: IVCBasketState;
  onActivate: (entryId: string) => void;
  onAdd: () => void;
  onRemove: (entryId: string) => void;
  onRename: (entryId: string, label: string) => void;
}) {
  const [editingId, setEditingId] = useState<string | null>(null);
  return (
    <div className="ivc3-tabs">
      {basket.entries.map((e) => {
        const isActive = e.id === basket.activeEntryId;
        const lbl = displayLabel(e);
        if (editingId === e.id) {
          return (
            <input
              key={e.id}
              className="ivc3-tab editing"
              autoFocus
              defaultValue={lbl}
              onBlur={(ev) => {
                onRename(e.id, ev.target.value);
                setEditingId(null);
              }}
              onKeyDown={(ev) => {
                if (ev.key === "Enter") {
                  onRename(e.id, (ev.target as HTMLInputElement).value);
                  setEditingId(null);
                }
                if (ev.key === "Escape") setEditingId(null);
              }}
              aria-label="Rename ticker tab"
            />
          );
        }
        return (
          <div
            key={e.id}
            className={`ivc3-tab${isActive ? " active" : ""}`}
            onClick={() => onActivate(e.id)}
            onDoubleClick={() => setEditingId(e.id)}
            role="tab"
            tabIndex={0}
            aria-selected={isActive}
            title="Double-click to rename"
          >
            <span className="ivc3-tab-label">{lbl}</span>
            {basket.entries.length > 1 && (
              <button
                type="button"
                className="ivc3-tab-close"
                onClick={(ev) => { ev.stopPropagation(); onRemove(e.id); }}
                aria-label={`Remove ${lbl}`}
              >
                ×
              </button>
            )}
          </div>
        );
      })}
      {basket.entries.length < BASKET_MAX_ENTRIES && (
        <button
          type="button"
          className="ivc3-tab add"
          onClick={onAdd}
        >
          + Add ticker
        </button>
      )}
    </div>
  );
}

// ── Per-entry editing view (inputs + matrix + breakdown) ─────────
function EntryView({
  entry, basket, chains, variants, bestId, selected, lastFetchedTxt, onUpdate,
}: {
  entry: IVCEntry;
  basket: IVCBasketState;
  chains: EntryChains | undefined;
  variants: IVCVariant[];
  bestId: string | undefined;
  selected: IVCVariant | undefined;
  lastFetchedTxt: string;
  onUpdate: (updater: (e: IVCEntry) => IVCEntry) => void;
}) {
  const set = <K extends keyof IVCEntry>(k: K, v: IVCEntry[K]) =>
    onUpdate((e) => ({ ...e, [k]: v }));

  const callStrike = useMemo(() => {
    const p = Number(entry.price), d = Number(basket.callDistance);
    return isFinite(p) && p > 0 && isFinite(d) ? p * (1 + d / 100) : NaN;
  }, [entry.price, basket.callDistance]);
  const putStrike = useMemo(() => {
    const p = Number(entry.price), d = Number(basket.putDistance);
    return isFinite(p) && p > 0 && isFinite(d) ? p * (1 - d / 100) : NaN;
  }, [entry.price, basket.putDistance]);

  // SelectedBreakdown still reads state.callContracts / state.putContracts /
  // state.underlying for its labels — synthesize the legacy IVCState shape.
  const stateForBreakdown = useMemo(() => asIVCState(entry, basket), [entry, basket]);
  const refreshing = !chains;  // proxy: no chains yet ⇒ fetch pending

  return (
    <div className="ivc3-entry">
      <div className="ivc3-inputs">
        <div className="ivc3-in ticker">
          <div className="hf-label">Underlying</div>
          <input
            className="cyc-input ticker"
            type="text"
            value={entry.underlying}
            onChange={(e) => set("underlying", e.target.value.toUpperCase())}
            placeholder="SPY"
            aria-label="Underlying ticker"
          />
          <PullFromSunnyfi
            ticker={entry.underlying}
            onPull={({ price, shares }) =>
              onUpdate((cur) => ({
                ...cur,
                price: price.toFixed(2),
                ...(shares ? { shares: String(shares) } : {}),
              }))
            }
          />
        </div>

        <div className="ivc3-in">
          <div className="hf-label">Shares</div>
          <input
            className="cyc-input"
            type="text" inputMode="numeric"
            value={entry.shares}
            onChange={(e) => set("shares", e.target.value)}
            placeholder="0"
            aria-label="Shares"
          />
          <div className="ivc3-in-hint mono">
            = {fmtMoney((Number(entry.shares) || 0) * (Number(entry.price) || 0), { decimals: 0 })}
          </div>
        </div>

        <div className="ivc3-in">
          <div className="hf-label">Price · live</div>
          <div className="cyc-field-row">
            <span className="cyc-prefix">$</span>
            <input
              className="cyc-input"
              type="text" inputMode="decimal"
              value={entry.price}
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
          <span className="ivc3-side-tag">
            CALL <span className="muted">· sell · {basket.callDistance}% OTM</span>
          </span>
          <div className="ivc3-side-fields">
            <div className="ivc3-in tight">
              <div className="hf-label">Contracts</div>
              <div className="ivc3-field-input">
                <input
                  type="text" inputMode="numeric"
                  value={entry.callContracts}
                  onChange={(e) => set("callContracts", e.target.value)}
                  placeholder="0" spellCheck={false}
                  aria-label="Call contracts"
                />
              </div>
              <div className="ivc3-in-hint mono">
                {fmtCount((Number(entry.callContracts) || 0) * 100)} sh · K ≈ {fmtMoney(callStrike)}
              </div>
            </div>
          </div>
        </div>

        <div className="ivc3-side puts">
          <span className="ivc3-side-tag">
            PUT <span className="muted">· buy · {basket.putDistance}% below</span>
          </span>
          <div className="ivc3-side-fields">
            <div className="ivc3-in tight">
              <div className="hf-label">Contracts</div>
              <div className="ivc3-field-input">
                <input
                  type="text" inputMode="numeric"
                  value={entry.putContracts}
                  onChange={(e) => set("putContracts", e.target.value)}
                  placeholder="0" spellCheck={false}
                  aria-label="Put contracts"
                />
              </div>
              <div className="ivc3-in-hint mono">
                {fmtCount((Number(entry.putContracts) || 0) * 100)} sh · K ≈ {fmtMoney(putStrike)}
              </div>
            </div>
          </div>
        </div>
      </div>

      <VariantsGrid
        variants={variants}
        ticker={entry.underlying}
        selectedId={entry.selectedVariantId}
        bestId={bestId}
        onSelect={(id) => set("selectedVariantId", id)}
        lastFetchedTxt={lastFetchedTxt}
      />

      {selected && (
        <SelectedBreakdown variant={selected} state={stateForBreakdown} bestId={bestId} />
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
              <span className="ivc3-bar-perchunk">
                {fmtMoney(incomePerCycle, { decimals: 0 })}{v.callPerUnit}
                {v.callPerMonth !== 1 && (
                  <span className="ivc3-bar-perchunk-roll">
                    {" · ~"}{fmtMoney(incomePerCycle * v.callPerMonth, { decimals: 0 })}/mo
                  </span>
                )}
              </span>
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
