// New York time for the Sunny web. The moment itself comes from the server's brief (doc.moment), which follows the
// New York clock exactly (A2: pre 4:00, open 9:30, post 16:00, weekend from Friday 20:00), as the phone does.
import { useEffect, useState } from 'react';

const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export interface NY { date: string; wd: string; mins: number; h: number; m: number; month: number; day: number }

/** The New York wall clock now (or at `at`). */
export function ny(at: Date = new Date()): NY {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
    weekday: 'short', hour12: false,
  }).formatToParts(at).map((x) => [x.type, x.value]));
  const h = +p.hour % 24, m = +p.minute;
  return { date: `${p.year}-${p.month}-${p.day}`, wd: p.weekday, mins: h * 60 + m, h, m, month: +p.month, day: +p.day };
}

/** "8:05 AM" */
export const clock12 = (n: NY) => `${((n.h + 11) % 12) + 1}:${String(n.m).padStart(2, '0')} ${n.h < 12 ? 'AM' : 'PM'}`;
/** "Tue Oct 27 · 8:05 AM ET" (the header's market time). */
export const headerTime = (n: NY) => `${n.wd} ${MO[n.month - 1]} ${n.day} · ${clock12(n)} ET`;
/** "Tue Oct 27" from an ISO date. */
export const shortDate = (iso: string) => {
  const d = new Date(iso + 'T12:00:00Z');
  return `${WD[d.getUTCDay()]} ${MO[d.getUTCMonth()]} ${d.getUTCDate()}`;
};
/** "Oct 27" from an ISO date. */
export const monthDay = (iso: string) => {
  const d = new Date(iso + 'T12:00:00Z');
  return `${MO[d.getUTCMonth()]} ${d.getUTCDate()}`;
};

const weekend = (n: NY) => n.wd === 'Sat' || n.wd === 'Sun';
/** The sign-in page's market line (README 0). */
export function marketStatus(n: NY): { live: boolean; line: string } {
  if (weekend(n) || (n.wd === 'Fri' && n.mins >= 20 * 60)) return { live: false, line: 'Markets closed · opens Monday 9:30 AM ET' };
  if (n.mins < 4 * 60) return { live: false, line: 'Markets closed · pre-market at 4:00 AM ET' };
  if (n.mins < 9 * 60 + 30) return { live: true, line: 'Pre-market · the open at 9:30 AM ET' };
  if (n.mins < 16 * 60) return { live: true, line: 'Market open · closes 4:00 PM ET' };
  if (n.mins < 20 * 60) return { live: true, line: 'After hours · until 8:00 PM ET' };
  return { live: false, line: 'Markets closed · pre-market at 4:00 AM ET' };
}

/** Inside 4:00 to 20:00 New York on a weekday: the server rebuilds Home every 15 to 30 s. */
export const liveHours = (n: NY = ny()) => !weekend(n) && n.mins >= 4 * 60 && n.mins < 20 * 60;
/** The regular session, 9:30 to 16:00 (holidays aside: the brief's calendar decides those). */
export const regularHours = (n: NY = ny()) => !weekend(n) && n.mins >= 9 * 60 + 30 && n.mins < 16 * 60;

/** Re-renders every `ms` with the New York clock. */
export function useNY(ms = 15_000): NY {
  const [n, setN] = useState(() => ny());
  useEffect(() => {
    const id = setInterval(() => setN(ny()), ms);
    return () => clearInterval(id);
  }, [ms]);
  return n;
}
