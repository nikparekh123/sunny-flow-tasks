// Derive a 13-week premium series from gain_entries.
// week 0 = current week (Monday), week 12 = oldest.

import type { GainEntryRow } from '../types';
import { mondayOf } from '../calc';

export interface WeekBucket {
  /** Monday ISO date for the week. */
  w: string;
  /** Sum of options premium across all positions in this week. */
  premium: number;
}

const MS_PER_WEEK = 7 * 24 * 60 * 60 * 1000;

function addWeeks(monday: string, n: number): string {
  const t = new Date(monday + 'T00:00:00Z').getTime() + n * MS_PER_WEEK;
  return new Date(t).toISOString().slice(0, 10);
}

/** Returns 13 weeks oldest → newest. Always 13 entries. */
export function weeklyPremium(entries: GainEntryRow[]): WeekBucket[] {
  const thisMonday = mondayOf();
  const byWeek = new Map<string, number>();
  for (const e of entries) {
    byWeek.set(e.week_start_date, (byWeek.get(e.week_start_date) ?? 0) + (e.options || 0));
  }
  const out: WeekBucket[] = [];
  for (let i = 12; i >= 0; i--) {
    const w = addWeeks(thisMonday, -i);
    out.push({ w, premium: byWeek.get(w) ?? 0 });
  }
  return out;
}

/** weekIdx 0 = this wk, 12 = oldest. */
export function weekStartForIdx(weekIdx: number): string {
  return addWeeks(mondayOf(), -weekIdx);
}

/** Reverse: how many weeks ago is this stored week_start_date? */
export function weekIdxOf(weekStart: string, refMonday = mondayOf()): number {
  const a = new Date(weekStart + 'T00:00:00Z').getTime();
  const b = new Date(refMonday + 'T00:00:00Z').getTime();
  return Math.round((b - a) / MS_PER_WEEK);
}
