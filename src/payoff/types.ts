/** The payoff-book contract. Mirrors supabase/functions/payoff-book/index.ts. */
import type { Leg } from './math';

export interface ClosedRow {
  title: string;
  side: 'sold' | 'bought';
  outcome: 'Assigned' | 'Exercised' | 'Expired worthless' | 'Bought back' | 'Sold';
  pnl: number;
  when: string;
  expiry: string;
  closedOn: string;
}

export interface TickerBook {
  ticker: string;
  name: string;
  spot: number;
  chg: number;
  iv: number;
  emas: [string, number][];
  levels: [string, number][];
  wk52: [number, number] | null;
  d5: [number, number] | null;
  target: { low: number; median: number; high: number; n: number } | null;
  chain: string[];
  /** The vendor's real strike ladder, per expiry, ascending. Optional so an
      older deployment of payoff-book still decodes; the page falls back to a
      fixed step when an expiry is missing. */
  strikes?: Record<string, number[]>;
  legs: Leg[];
  closed: ClosedRow[];
}

export interface PayoffBook {
  ok: boolean;
  build: string;
  date: string;
  book: TickerBook[];
}

export interface SavedPlan {
  id: string;
  ticker: string;
  name: string;
  legs: Leg[];
  updated_at: string;
}

export type LayerKey = 'ema' | 'sr' | 'last5' | 'targets' | 'cone' | 'hist' | 'assign';
export type Layers = Record<LayerKey, boolean>;
export const DEFAULT_LAYERS: Layers = {
  ema: true, sr: true, last5: false, targets: false, cone: false, hist: false, assign: false,
};
