/**
 * Greeks atoms — A13 portfolioDelta, A14 portfolioGamma, A15
 * portfolioTheta, A16 portfolioVega, A17 betaWeightedDelta. Pure
 * compute, same shape as A1–A12 in `./atoms.ts`.
 *
 * Inputs (raw rows; the same shapes the DB returns):
 *   positions      — for the shares contribution to delta (1 share = 1 Δ)
 *   trades         — open option legs (filtered to remaining > 0)
 *   greeks         — per-leg per-share Δ/Γ/Θ/V (from option_greeks)
 *   quotes         — per-ticker beta (from ticker_quotes), only needed
 *                    by A17
 *
 * Position-level conventions:
 *   - Per-share Greeks come from the data provider.
 *   - Position contribution = per-share × remaining_contracts × 100 ×
 *     side_sign (short = −1, long = +1).
 *   - Stock contributes only delta (= signed quantity), all others 0.
 *
 * Filter notes (`AtomFilter` shared with A1–A12):
 *   - `ticker`: narrows positions + option legs to that symbol.
 *   - `optionType` / `direction`: narrow option legs only — stock is
 *     always included for the delta sum unless `ticker` excludes it.
 *   - `liveState`: only meaningful for open legs (matches A9/A10/A11).
 */
import { type AtomFilter, type LiveState } from "./atoms";
import type { OptionTrade, PositionRow } from "../types";

// ─── Minimal shapes for Greeks + quotes ─────────────────────────
// These mirror the DB columns. Defined here so atoms.ts doesn't need
// to import from src/portfolio/ (atoms are a lower layer).
export interface LegGreek {
  option_trade_id: string;
  delta: number | null;
  gamma: number | null;
  theta: number | null;
  vega: number | null;
}
export interface TickerQuote {
  ticker: string;
  beta: number | null;
}

const todayIsoUTC = (): string => new Date().toISOString().slice(0, 10);

function inWindow(dateIso: string, w?: AtomFilter["window"]): boolean {
  if (!w) return true;
  if (w.start && dateIso < w.start) return false;
  if (w.end && dateIso >= w.end) return false;
  return true;
}

function daysUntil(iso: string, today: string): number {
  const a = new Date(iso + "T00:00:00Z").getTime();
  const b = new Date(today + "T00:00:00Z").getTime();
  return Math.round((a - b) / 86_400_000);
}

function liveStateOf(expiry: string, today: string): LiveState {
  const d = daysUntil(expiry, today);
  if (d < 0) return "expired";
  if (d === 0) return "today";
  if (d <= 7) return "in_le_7d";
  return "in_gt_7d";
}

function matchesLiveState(expiry: string, f: AtomFilter["liveState"], today: string): boolean {
  if (!f) return true;
  const s = liveStateOf(expiry, today);
  return Array.isArray(f) ? f.includes(s) : s === f;
}

function passesLegFilter(t: OptionTrade, f: AtomFilter | undefined, today: string): boolean {
  if (!f) return true;
  if (f.ticker && t.ticker !== f.ticker) return false;
  if (f.optionType && t.option_type !== f.optionType) return false;
  if (f.direction && t.direction !== f.direction) return false;
  if (f.window && !inWindow(t.trade_date, f.window)) return false;
  if (!matchesLiveState(t.expiry, f.liveState, today)) return false;
  return true;
}

/** Build remaining-contracts map (same logic as atoms.ts). Exported so
 *  hooks can reuse without re-walking the trades array. */
export function remainingByOpenId(trades: OptionTrade[]): Map<string, number> {
  const open = new Map<string, OptionTrade>();
  const closedQty = new Map<string, number>();
  for (const t of trades) {
    if (t.action === "open") open.set(t.id, t);
    else if (t.action === "close" && t.closes_trade_id) {
      closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
    }
  }
  const out = new Map<string, number>();
  for (const [id, o] of open) out.set(id, Math.max(0, o.contracts - (closedQty.get(id) ?? 0)));
  return out;
}

/** Build a Greeks-by-id map for fast lookup inside the loops below. */
function greekById(greeks: LegGreek[]): Map<string, LegGreek> {
  return new Map(greeks.map((g) => [g.option_trade_id, g]));
}

/** Sum a single Greek across open option legs only (no stock). */
function sumLegGreek(
  greek: "delta" | "gamma" | "theta" | "vega",
  trades: OptionTrade[],
  greeks: LegGreek[],
  f?: AtomFilter,
  today: string = todayIsoUTC(),
): number {
  const remaining = remainingByOpenId(trades);
  const gById = greekById(greeks);
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "open") continue;
    const left = remaining.get(t.id) ?? 0;
    if (left <= 0) continue;
    if (!passesLegFilter(t, f, today)) continue;
    const g = gById.get(t.id);
    const per = g?.[greek];
    if (per == null) continue;
    const sideSign = t.direction === "short" ? -1 : 1;
    sum += per * left * 100 * sideSign;
  }
  return sum;
}

// ─── A13 portfolioDelta ─────────────────────────────────────────
/** Σ leg Δ contributions + Σ share quantities over open positions.
 *  Share contribution = qty (1 share = 1 Δ), positive for long-only
 *  positions. Filter-aware (ticker filter narrows both stock + legs;
 *  optionType / direction narrow legs only — stock is still included). */
export function portfolioDelta(
  positions: PositionRow[],
  trades: OptionTrade[],
  greeks: LegGreek[],
  f?: AtomFilter,
  today: string = todayIsoUTC(),
): number {
  let sum = sumLegGreek("delta", trades, greeks, f, today);
  for (const p of positions) {
    if (p.status === "closed" || p.quantity <= 0) continue;
    if (f?.ticker && p.ticker !== f.ticker) continue;
    sum += p.quantity;
  }
  return sum;
}

// ─── A14 / A15 / A16 ────────────────────────────────────────────
/** Σ leg Γ contributions (stock contributes 0). */
export function portfolioGamma(trades: OptionTrade[], greeks: LegGreek[], f?: AtomFilter, today?: string): number {
  return sumLegGreek("gamma", trades, greeks, f, today);
}
/** Σ leg Θ contributions per day (stock contributes 0). */
export function portfolioTheta(trades: OptionTrade[], greeks: LegGreek[], f?: AtomFilter, today?: string): number {
  return sumLegGreek("theta", trades, greeks, f, today);
}
/** Σ leg V contributions per 1% IV move (stock contributes 0). */
export function portfolioVega(trades: OptionTrade[], greeks: LegGreek[], f?: AtomFilter, today?: string): number {
  return sumLegGreek("vega", trades, greeks, f, today);
}

// ─── A17 betaWeightedDelta ──────────────────────────────────────
/** Per-ticker delta × ticker.beta, summed across the book. Useful as a
 *  single SPY-equivalent exposure number. Tickers without a beta in
 *  quotes default to 1.0 (treated like a market-following stock). */
export function betaWeightedDelta(
  positions: PositionRow[],
  trades: OptionTrade[],
  greeks: LegGreek[],
  quotes: TickerQuote[],
  f?: AtomFilter,
  today: string = todayIsoUTC(),
): number {
  const betaByT = new Map(quotes.map((q) => [q.ticker.toUpperCase(), q.beta ?? 1]));
  // Per-ticker delta totals (legs + stock), then × beta. Walk per ticker
  // so each beta multiplies the WHOLE ticker exposure (matches the
  // industry definition; not the sum of per-leg β·Δ).
  const tickers = new Set<string>([
    ...positions.filter((p) => p.status === "open" && p.quantity > 0).map((p) => p.ticker.toUpperCase()),
    ...trades.filter((t) => t.action === "open").map((t) => t.ticker.toUpperCase()),
  ]);
  let total = 0;
  for (const t of tickers) {
    if (f?.ticker && t !== f.ticker) continue;
    const d = portfolioDelta(positions, trades, greeks, { ...(f ?? {}), ticker: t }, today);
    const beta = betaByT.get(t) ?? 1;
    total += d * beta;
  }
  return total;
}
