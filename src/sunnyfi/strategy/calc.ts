// Strategy calc helpers — ported from swm-data.jsx (the handoff bundle).
// Pure functions over the joined StrategyPosition shape.

import {
  type StrategyPosition,
  type Bucket,
  BUCKET_META,
  TOTAL_CAPITAL,
  WEEKS_PER_PUT_PERIOD,
} from './types';

export type Cadence = 'month' | 'quarter' | 'year';

const PERIOD_WEEKS: Record<Cadence, number> = {
  month: 4.33,
  quarter: 13,
  year: 52,
};

const PERIOD_DAYS: Record<Cadence, number> = {
  month: 30,
  quarter: 91,
  year: 365,
};

export interface PositionCalc {
  cost: number;
  value: number;
  sharePL: number;
  sharePLPct: number;
  collected: number;
  realizedGains: number;
  /** Total put protection cost from put_protection.total_cost (0 if none). */
  putCost: number;
  /** Calendar days from today to put_protection.expiry (0 if expired/none). */
  daysToExpiry: number;
  /** put_cost ÷ trading days remaining (~5/7 of daysToExpiry). null if no protection. */
  costPerTradingDay: number | null;
  /** Net total = sharePL + collected + realizedGains − putCost. */
  total: number;
  target: number;
  weeklyTarget: number;
  expected: number;
  onTrack: number;
  shortfall: number;
  catchUpPerWeek: number;
  daysLeft: number;
  weeksLeft: number;
  verdict: 'good' | 'warn' | 'bad';
  underwater: boolean;
}

export function weeklyTargetFor(p: StrategyPosition): number {
  const cost = p.overlay?.put_cost ?? 0;
  const freq = p.overlay?.put_frequency ?? 'quarterly';
  return cost / WEEKS_PER_PUT_PERIOD[freq];
}

export function periodTargetFor(
  p: StrategyPosition,
  cadence: Cadence,
): number {
  return weeklyTargetFor(p) * PERIOD_WEEKS[cadence];
}

export function calcPosition(
  p: StrategyPosition,
  cadence: Cadence = 'quarter',
): PositionCalc {
  const qty = p.quantity ?? 0;
  const avgCost = p.avg_cost ?? 0;
  const px = p.current_price ?? avgCost;
  const daysHeld = p.overlay?.days_held ?? 0;

  const cost = qty * avgCost;
  const value = qty * px;
  const sharePL = value - cost;
  const sharePLPct = cost > 0 ? (sharePL / cost) * 100 : 0;

  // v2 schema: gain_entries has a `source` discriminator. Map back to the
  // old aggregate names to keep the rest of the Strategy page intact:
  //   collected     ← call (covered-call premium)
  //   realizedGains ← stock (realized stock gains, dividends)
  // Put-source gains aren't surfaced on the Strategy page yet (deferred to
  // the Positions v2 redesign that owns the 3-way split).
  const collected = p.entries
    .filter((e) => e.source === 'call')
    .reduce((s, e) => s + (e.amount || 0), 0);
  const realizedGains = p.entries
    .filter((e) => e.source === 'stock')
    .reduce((s, e) => s + (e.amount || 0), 0);

  // Put protection economics. Cost-per-trading-day = total_cost ÷ trading
  // days remaining to expiry, where trading days ≈ calendar days × 5/7.
  const putCost = p.putProtection?.total_cost ?? 0;
  let daysToExpiry = 0;
  let costPerTradingDay: number | null = null;
  if (p.putProtection) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const expiry = new Date(p.putProtection.expiry + 'T00:00:00');
    const diffMs = expiry.getTime() - today.getTime();
    daysToExpiry = Math.max(0, Math.round(diffMs / 86_400_000));
    const tradingDaysLeft = Math.max(1, daysToExpiry * (5 / 7));
    costPerTradingDay = putCost / tradingDaysLeft;
  }

  // Net total = unrealized + premium + realized − cost of put protection.
  const total = sharePL + collected + realizedGains - putCost;

  const daysInPeriod = PERIOD_DAYS[cadence];
  const target = periodTargetFor(p, cadence);
  const weeklyTarget = weeklyTargetFor(p);
  const expected =
    (weeklyTarget * Math.min(daysHeld, daysInPeriod)) / 7;
  const onTrack = expected > 0 ? collected / expected : 1;
  const shortfall = expected - collected;
  const daysLeft = Math.max(7, daysInPeriod - (daysHeld % daysInPeriod));
  const weeksLeft = Math.max(1, daysLeft / 7);
  const catchUpPerWeek = shortfall > 0 ? shortfall / weeksLeft : 0;
  const verdict =
    onTrack >= 1 ? 'good' : onTrack >= 0.85 ? 'warn' : 'bad';

  return {
    cost,
    value,
    sharePL,
    sharePLPct,
    collected,
    realizedGains,
    putCost,
    daysToExpiry,
    costPerTradingDay,
    total,
    target,
    weeklyTarget,
    expected,
    onTrack,
    shortfall,
    catchUpPerWeek,
    daysLeft,
    weeksLeft,
    verdict,
    underwater: sharePL < 0,
  };
}

export interface BucketCalc {
  key: Bucket;
  name: string;
  tone: string;
  targetPct: number;
  targetDollar: number;
  count: number;
  cost: number;
  value: number;
  sharePL: number;
  realizedGains: number;
  collected: number;
  /** Sum of put_protection.total_cost across positions in this bucket. */
  putCost: number;
  target: number;
  expected: number;
  shortfall: number;
  catchUp: number;
  total: number;
  onTrack: number;
  verdict: 'good' | 'warn' | 'bad';
}

export function calcBucket(
  positions: StrategyPosition[],
  key: Bucket,
  cadence: Cadence = 'quarter',
): BucketCalc {
  const meta = BUCKET_META[key];
  const acc = positions.reduce(
    (a, p) => {
      const c = calcPosition(p, cadence);
      a.cost += c.cost;
      a.value += c.value;
      a.sharePL += c.sharePL;
      a.realizedGains += c.realizedGains;
      a.collected += c.collected;
      a.putCost += c.putCost;
      a.target += c.target;
      a.expected += c.expected;
      a.shortfall += c.shortfall;
      a.catchUp += c.catchUpPerWeek;
      a.total += c.total;
      return a;
    },
    {
      cost: 0,
      value: 0,
      sharePL: 0,
      realizedGains: 0,
      collected: 0,
      putCost: 0,
      target: 0,
      expected: 0,
      shortfall: 0,
      catchUp: 0,
      total: 0,
    },
  );
  const onTrack = acc.expected > 0 ? acc.collected / acc.expected : 1;
  return {
    key,
    name: meta.name,
    tone: meta.tone,
    targetPct: meta.pct,
    targetDollar: meta.dollar,
    count: positions.length,
    ...acc,
    onTrack,
    verdict: onTrack >= 1 ? 'good' : onTrack >= 0.85 ? 'warn' : 'bad',
  };
}

export interface PortfolioCalc {
  cost: number;
  value: number;
  sharePL: number;
  realizedGains: number;
  collected: number;
  target: number;
  expected: number;
  shortfall: number;
  catchUp: number;
  total: number;
  onTrack: number;
  verdict: 'ahead' | 'on-track' | 'behind';
  deployedPct: number;
  totalCapital: number;
}

export function calcPortfolio(
  buckets: Record<Bucket, BucketCalc>,
): PortfolioCalc {
  const p = (['income', 'invest', 'yield'] as Bucket[]).reduce(
    (a, k) => {
      const b = buckets[k];
      a.cost += b.cost;
      a.value += b.value;
      a.sharePL += b.sharePL;
      a.realizedGains += b.realizedGains;
      a.collected += b.collected;
      a.target += b.target;
      a.expected += b.expected;
      a.shortfall += b.shortfall;
      a.catchUp += b.catchUp;
      a.total += b.total;
      return a;
    },
    {
      cost: 0,
      value: 0,
      sharePL: 0,
      realizedGains: 0,
      collected: 0,
      target: 0,
      expected: 0,
      shortfall: 0,
      catchUp: 0,
      total: 0,
    },
  );
  const onTrack = p.expected > 0 ? p.collected / p.expected : 1;
  const verdict: PortfolioCalc['verdict'] =
    onTrack >= 1.02 ? 'ahead' : onTrack >= 0.92 ? 'on-track' : 'behind';
  return {
    ...p,
    onTrack,
    verdict,
    deployedPct: (p.cost / TOTAL_CAPITAL) * 100,
    totalCapital: TOTAL_CAPITAL,
  };
}

// ── Formatters ───────────────────────────────────────────────────────
const MINUS = '−';
export const fmt$ = (n: number, digits = 0): string =>
  (n < 0 ? MINUS : '') +
  '$' +
  Math.abs(Math.round(n)).toLocaleString('en-US', {
    maximumFractionDigits: digits,
  });

export const fmtPx = (n: number): string => '$' + n.toFixed(2);

export const fmtSigned = (n: number): string =>
  (n >= 0 ? '+$' : MINUS + '$') +
  Math.abs(Math.round(n)).toLocaleString('en-US');

export const fmtPct = (n: number, digits = 1): string =>
  n.toFixed(digits) + '%';

export const fmtK = (n: number): string => {
  const abs = Math.abs(n);
  const sign = n < 0 ? MINUS : '';
  if (abs >= 1_000_000) return sign + '$' + (abs / 1_000_000).toFixed(2) + 'M';
  if (abs >= 10_000) return sign + '$' + (abs / 1000).toFixed(0) + 'k';
  if (abs >= 1000) return sign + '$' + (abs / 1000).toFixed(1) + 'k';
  return sign + '$' + Math.round(abs);
};

// ── Week date helpers (anchored Monday) ──────────────────────────────
export function mondayOf(d: Date = new Date()): string {
  const day = d.getDay(); // 0 Sun .. 6 Sat
  const diff = (day === 0 ? -6 : 1 - day); // shift to Monday
  const m = new Date(d);
  m.setDate(d.getDate() + diff);
  m.setHours(0, 0, 0, 0);
  return m.toISOString().slice(0, 10);
}

/** Convert a stored week_start_date to a human label like "this wk" / "−1". */
export function weekLabel(date: string, refMonday = mondayOf()): string {
  const a = new Date(date + 'T00:00:00Z').getTime();
  const b = new Date(refMonday + 'T00:00:00Z').getTime();
  const weeks = Math.round((b - a) / (7 * 24 * 60 * 60 * 1000));
  if (weeks === 0) return 'this wk';
  if (weeks > 0) return '−' + weeks;
  return '+' + Math.abs(weeks);
}
