// Strategy types — overlay rows, journal entries, and the joined view
// the page renders.

export type Bucket = 'income' | 'invest' | 'yield';
export type PutFrequency =
  | 'weekly'
  | 'biweekly'
  | 'monthly'
  | 'quarterly'
  | 'yearly';

export interface StrategyOverlayRow {
  id: string;
  ticker: string;
  bucket: Bucket;
  put_cost: number;
  put_frequency: PutFrequency;
  days_held: number;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export type GainSource = 'stock' | 'call' | 'put';

export interface GainEntryRow {
  id: string;
  ticker: string;
  /** ISO yyyy-mm-dd of the gain event (NOT bucketed to Monday). */
  gain_date: string;
  source: GainSource;
  /** Signed USD. Negative for realized losses. */
  amount: number;
  note: string | null;
}

export interface PutProtectionRow {
  id: string;
  ticker: string;
  total_cost: number;
  expiry: string;           // ISO yyyy-mm-dd
  purchase_date: string;    // ISO yyyy-mm-dd
  created_at: string;
  updated_at: string;
}

export interface WatchingRow {
  id: string;
  ticker: string;
  name: string | null;
  sector: string;
  current_price: number | null;
}

/**
 * A position joined with its overlay + journal — the renderable unit
 * the Strategy page works with. `overlay = null` ⇒ unassigned.
 * `position = null` ⇒ closed (overlay survives, position is gone).
 */
export interface StrategyPosition {
  ticker: string;
  name: string | null;
  sector: string;
  quantity: number | null; // null when closed
  avg_cost: number | null; // null when closed
  current_price: number | null;
  overlay: StrategyOverlayRow | null;
  entries: GainEntryRow[];
}

export const BUCKET_META: Record<
  Bucket,
  { name: string; pct: number; dollar: number; tone: string }
> = {
  income: { name: 'Income',     pct: 40, dollar: 1_200_000, tone: 'income' },
  invest: { name: 'Investment', pct: 40, dollar: 1_200_000, tone: 'invest' },
  yield:  { name: 'Yield',      pct: 20, dollar:   600_000, tone: 'yield'  },
};

export const TOTAL_CAPITAL = 3_000_000;

export const PUT_FREQUENCIES: PutFrequency[] = [
  'weekly',
  'biweekly',
  'monthly',
  'quarterly',
  'yearly',
];

export const WEEKS_PER_PUT_PERIOD: Record<PutFrequency, number> = {
  weekly: 1,
  biweekly: 2,
  monthly: 4.33,
  quarterly: 13,
  yearly: 52,
};

export const FREQ_LABEL: Record<PutFrequency, string> = {
  weekly: 'wk',
  biweekly: '2wk',
  monthly: 'mo',
  quarterly: 'qtr',
  yearly: 'yr',
};
