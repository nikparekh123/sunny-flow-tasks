// The moment tabs (README 1, item 1): Pre-market · Market hours · Post-market · Weekend. The current one follows
// the server's brief (doc.moment); each moment's last brief is saved (useBriefLog), so another tab reads that one
// (Nik, 9 Nov). A tab is greyed out and does nothing when there is no saved brief, or when its brief is not from
// the last session day: on a weekday, a moment not reached yet today; on the weekend, a brief from before Friday.
import type { BriefLogRow, J, Tab } from '../../lib/data';
import { addDays, weekday } from './model';

export const TABS: { k: Tab; l: string }[] = [
  { k: 'pre', l: 'Pre-market' }, { k: 'open', l: 'Market hours' }, { k: 'post', l: 'Post-market' }, { k: 'weekend', l: 'Weekend' },
];
const ORDER: Record<Tab, number> = { pre: 0, open: 1, post: 2, weekend: 3 };

/** The last trading day on or before `day` (weekends and the calendar's closed days skipped). */
export function lastSessionDay(day: string, calendar: J): string {
  const closed = new Set<string>((Array.isArray(calendar) ? calendar : []).filter((c: J) => c?.kind === 'closed').map((c: J) => String(c.date)));
  let d = day;
  for (let k = 0; k < 10; k++) {
    const wd = weekday(d);
    if (wd !== 0 && wd !== 6 && !closed.has(d)) return d;
    d = addDays(d, -1);
  }
  return d;
}

export interface TabState { k: Tab; l: string; on: boolean; enabled: boolean }

export function tabStates(cur: Tab, curDoc: J, log: Partial<Record<Tab, BriefLogRow>> | undefined, picked: Tab, calendar: J): TabState[] {
  const today: string = curDoc?.built_for ?? '';
  const last = cur === 'weekend' ? lastSessionDay(today, calendar) : today;
  return TABS.map(({ k, l }) => {
    let enabled: boolean;
    if (k === cur) enabled = true;
    else {
      const row = log?.[k];
      if (!row?.doc) enabled = false;
      else if (k === 'weekend') enabled = true;                                       // the last Week in Review
      else if (cur !== 'weekend' && ORDER[k] > ORDER[cur]) enabled = false;           // not reached yet today
      else enabled = String(row.built_for ?? row.doc?.built_for ?? '') >= last;        // from the last session day
    }
    return { k, l, on: k === picked, enabled };
  });
}
