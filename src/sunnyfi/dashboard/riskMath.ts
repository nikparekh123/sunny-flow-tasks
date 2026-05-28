/**
 * Constant-beta risk scenarios.
 *
 * Per CD-1 scoping: ship the simple shock math now; proper Black-
 * Scholes options re-pricing can come later.
 *
 *   shock = market_value × beta × pct_move
 *
 * Where:
 *   • market_value = qty × current_price for shares; contracts × 100 ×
 *     delta_equivalent × spot for options.
 *   • beta defaults to 1.0 (single-name shocks treat the ticker as
 *     beta-1 to itself). A future pass can plug per-ticker betas
 *     from a stored table.
 *   • Delta-equivalent for options:
 *       short call → −0.5 share / contract (rough OTM-ish call)
 *       short put  → +0.5 share / contract
 *       long  call → +0.5 share / contract
 *       long  put  → −0.5 share / contract
 *     This is a flat approximation; it lets a portfolio mostly long
 *     stock + short calls model the gamma direction without needing
 *     option marks.
 *
 * Three scenarios shipped:
 *   • SPY −5%        — broad-market sell-off
 *   • NVDA −10%      — single-name shock (any of your top concentrations)
 *   • VIX +50%       — vol regime shift, proxied as a 3% portfolio gap
 */

export interface RiskPositionInput {
  ticker: string;
  quantity: number;          // shares
  current_price: number | null;
  avg_cost: number;
}

export interface RiskOptionInput {
  ticker: string;
  option_type: "call" | "put";
  direction: "short" | "long";
  contracts: number;
  strike: number;
  premium: number;
}

export interface RiskScenarioResult {
  label: string;
  detail: string;
  dollars: number;           // signed; negative = loss
}

/** Δ-equivalent in shares per contract, given direction + type. */
function deltaEquiv(opt: RiskOptionInput): number {
  if (opt.option_type === "call") {
    return opt.direction === "short" ? -0.5 : +0.5;
  }
  return opt.direction === "short" ? +0.5 : -0.5;
}

/** Net portfolio exposure to one ticker = shares + Δ-equivalent shares
 *  across all options on that ticker. Multiplied by spot when computing
 *  dollar shocks. */
function nettedSharesByTicker(
  positions: RiskPositionInput[],
  options: RiskOptionInput[],
): Map<string, { shares: number; spot: number }> {
  const m = new Map<string, { shares: number; spot: number }>();
  for (const p of positions) {
    const spot = p.current_price ?? p.avg_cost;
    m.set(p.ticker, { shares: (m.get(p.ticker)?.shares ?? 0) + p.quantity, spot });
  }
  for (const o of options) {
    const spot = m.get(o.ticker)?.spot ?? o.strike;
    const equiv = deltaEquiv(o) * o.contracts * 100;
    const cur = m.get(o.ticker) ?? { shares: 0, spot };
    m.set(o.ticker, { shares: cur.shares + equiv, spot: cur.spot });
  }
  return m;
}

/** Apply a market-wide shock proportional to a beta. Returns total
 *  P&L change across all tickers. */
export function shockMarket(
  positions: RiskPositionInput[],
  options: RiskOptionInput[],
  pctMove: number,
  beta = 1.0,
): number {
  const net = nettedSharesByTicker(positions, options);
  let total = 0;
  for (const { shares, spot } of net.values()) {
    total += shares * spot * beta * pctMove;
  }
  return total;
}

/** Apply a shock to one ticker only. Other tickers untouched. */
export function shockSingleName(
  positions: RiskPositionInput[],
  options: RiskOptionInput[],
  ticker: string,
  pctMove: number,
): number {
  const net = nettedSharesByTicker(positions, options);
  const t = net.get(ticker);
  if (!t) return 0;
  return t.shares * t.spot * pctMove;
}

/** Build the 3-row scenario list used by RiskBlock. */
export function buildRiskScenarios(
  positions: RiskPositionInput[],
  options: RiskOptionInput[],
): RiskScenarioResult[] {
  // Find the largest single-name dollar exposure for the NVDA-style
  // single-name row. We default to NVDA if you don't hold it because
  // it's a canonical vol catalyst; otherwise use whatever you're most
  // long.
  const net = nettedSharesByTicker(positions, options);
  let topTicker = "NVDA";
  let topExposure = 0;
  for (const [t, { shares, spot }] of net) {
    const exp = Math.abs(shares * spot);
    if (exp > topExposure) {
      topExposure = exp;
      topTicker = t;
    }
  }

  // VIX +50% → assume −3% portfolio gap (rough proxy from historical
  // 30d corr of VIX spikes vs SPY drawdowns).
  const VIX_PCT_PROXY = -0.03;

  return [
    {
      label: "SPY −5%",
      detail: "broad-market sell-off · constant beta",
      dollars: shockMarket(positions, options, -0.05, 1.0),
    },
    {
      label: `${topTicker} −10%`,
      detail: "single-name shock",
      dollars: shockSingleName(positions, options, topTicker, -0.10),
    },
    {
      label: "VIX +50%",
      detail: "vol regime · ~−3% gap on book",
      dollars: shockMarket(positions, options, VIX_PCT_PROXY, 1.0),
    },
  ];
}

/** localStorage key for last-reviewed timestamp. Single-user app so we
 *  just persist client-side; if/when multi-device matters we lift this
 *  to Supabase. */
export const RISK_LAST_REVIEWED_KEY = "sunnyfi.dashboard.risk.lastReviewed";

export function loadLastReviewed(): Date | null {
  try {
    const s = localStorage.getItem(RISK_LAST_REVIEWED_KEY);
    if (!s) return null;
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d;
  } catch { return null; }
}

export function saveLastReviewed(d: Date): void {
  try { localStorage.setItem(RISK_LAST_REVIEWED_KEY, d.toISOString()); } catch { /* swallow */ }
}
