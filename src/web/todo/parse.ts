// To do (handoff 2026-11-10-todo): the date words and the date parser, ported as is from the prototype's
// SunnyTodo logic class (`lab`, `due`, `full`, `parse`, `tk`, and the picker's days in `cal`). Pure functions:
// `today` (New York's calendar day, yyyy-mm-dd) is passed in. Dates are ISO yyyy-mm-dd read at noon UTC, so no
// time zone moves a day.

export const WD = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
export const MS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const ML = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

export const D = (s: string) => new Date(s + 'T12:00:00Z');
export const I = (d: Date) => d.toISOString().slice(0, 10);
export const plus = (s: string, n: number) => { const d = D(s); d.setUTCDate(d.getUTCDate() + n); return I(d); };
/** Whole days from `a` to `b`. */
export const days = (a: string, b: string) => Math.round((D(b).getTime() - D(a).getTime()) / 864e5);

/** A date as words: Today, Tomorrow, Day after, Friday, Tue Nov 3 (another year: Mon Jan 4, 2027); back: Yesterday,
    3 days ago, then the short date. */
export function lab(s: string | null | undefined, T: string): string {
  if (!s) return '';
  const n = days(T, s), d = D(s);
  if (n === 0) return 'Today';
  if (n === 1) return 'Tomorrow';
  if (n === 2) return 'Day after';
  if (n === -1) return 'Yesterday';
  if (n > 2 && n < 7) return WD[d.getUTCDay()];
  if (n < -1 && n > -7) return -n + ' days ago';
  return WD[d.getUTCDay()].slice(0, 3) + ' ' + MS[d.getUTCMonth()] + ' ' + d.getUTCDate() + (d.getUTCFullYear() !== D(T).getUTCFullYear() ? ', ' + d.getUTCFullYear() : '');
}

/** The preview line's words: due tomorrow, due the day after tomorrow, due Friday, due Tue Nov 3. */
export function due(s: string, T: string): string {
  const l = lab(s, T);
  return l === 'Day after' ? 'the day after tomorrow' : /^(Today|Tomorrow|Yesterday)$/.test(l) ? l.toLowerCase() : l;
}

/** "Tuesday, October 27" (the calendar days' labels). */
export function full(s: string): string {
  const d = D(s);
  return WD[d.getUTCDay()] + ', ' + ML[d.getUTCMonth()] + ' ' + d.getUTCDate();
}

export interface Parsed { iso: string; t: string }

/** Finds the first date written in the text and returns it with the text left once the date words (and a "by",
    "on", "due", "before", "for", "until" or "till" right before them) come out, trimmed, first letter capital. */
export function parse(s: string | null | undefined, T: string): Parsed | null {
  if (!s || !s.trim()) return null;
  const t0 = D(T).getUTCDay(), A = (n: number) => plus(T, n), y0 = D(T).getUTCFullYear();
  const WK: Record<string, number> = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
  const MO: Record<string, number> = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
  const NUM: Record<string, number> = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10 };
  const md = (m: number, d: number): string | null => {
    if (!(m >= 0 && m <= 11) || d < 1 || d > 31) return null;
    const x = new Date(Date.UTC(y0, m, d, 12));
    if (x.getUTCMonth() !== m) return null;
    let s2 = I(x);
    if (s2 < T) s2 = I(new Date(Date.UTC(y0 + 1, m, d, 12)));
    return s2;
  };
  const wd = (w: number, mod: string | undefined) => {
    let n = (w - t0 + 7) % 7;
    if (mod === 'this') return A(n);
    if (!n) n = 7;
    if (mod === 'next' && n <= (7 - t0) % 7) n += 7;
    return A(n);
  };
  const WR = 'mon(?:day)?|tue(?:s(?:day)?)?|wed(?:s|nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?';
  const MR = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';
  const P: [RegExp, (m: RegExpExecArray) => string | null][] = [
    [/\b(?:the\s+)?day\s+after\s+(?:tomorrow|tmrw)\b/i, () => A(2)],
    [/\b(?:the\s+)?day\s+after\b/i, () => A(2)],
    [/\b(?:today|tonight|tonite|eod)\b/i, () => A(0)],
    [/\b(?:tomorrow|tmrw|tmr|tmw)\b/i, () => A(1)],
    [/\bin\s+(\d{1,3}|an?|one|two|three|four|five|six|seven|eight|nine|ten)\s+(day|week|month)s?\b/i, (m) => {
      const n = NUM[m[1].toLowerCase()] || parseInt(m[1], 10), u = m[2].toLowerCase();
      if (u === 'day') return A(n);
      if (u === 'week') return A(7 * n);
      const d = D(T); d.setUTCMonth(d.getUTCMonth() + n); return I(d);
    }],
    [/\bnext\s+week\b/i, () => A(((1 - t0 + 7) % 7) || 7)],
    [/\bnext\s+month\b/i, () => { const d = D(T); d.setUTCMonth(d.getUTCMonth() + 1, 1); return I(d); }],
    [/\b(?:(?:the|this)\s+)?weekend\b/i, () => A((6 - t0 + 7) % 7)],
    [/\bend\s+of\s+(?:the\s+)?week\b|\beow\b/i, () => A((5 - t0 + 7) % 7)],
    [/\bend\s+of\s+(?:the\s+)?month\b|\beom\b/i, () => { const d = D(T); return I(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0, 12))); }],
    [new RegExp('\\b(?:(this|next)\\s+)?(' + WR + ')\\b', 'i'), (m) => wd(WK[m[2].slice(0, 3).toLowerCase()], m[1] && m[1].toLowerCase())],
    [new RegExp('\\b(' + MR + ')\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b', 'i'), (m) => md(MO[m[1].slice(0, 3).toLowerCase()], +m[2])],
    [new RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(' + MR + ')\\b', 'i'), (m) => md(MO[m[2].slice(0, 3).toLowerCase()], +m[1])],
    [/\b(\d{1,2})\/(\d{1,2})\b/, (m) => md(+m[1] - 1, +m[2])],
  ];
  for (const [re, f] of P) {
    const m = re.exec(s);
    if (!m) continue;
    const iso = f(m);
    if (!iso) continue;
    let a = m.index;
    const b = a + m[0].length, pre = /\b(?:by|on|due|before|for|until|till)\s+$/i.exec(s.slice(0, a));
    if (pre) a = pre.index;
    let t = (s.slice(0, a) + ' ' + s.slice(b)).replace(/\s+/g, ' ').replace(/\s+([,.;:!?])/g, '$1').replace(/^[\s,;:-]+|[\s,;:-]+$/g, '');
    if (!t) t = s.trim();
    return { iso, t: t.charAt(0).toUpperCase() + t.slice(1) };
  }
  return null;
}

/** The first ticker in the text that the book or its watchlist holds (2 to 5 capitals). */
export function tk(t: string, known: Set<string>): { t: string; i: number } | null {
  const re = /\b[A-Z]{2,5}\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(t))) if (known.has(m[0])) return { t: m[0], i: m.index };
  return null;
}

/** The picker's quick chips: Today, Tomorrow, Day after, Friday (only when 3 or more days away), Next week (Monday). */
export function quick(T: string): [string, string][] {
  const t0 = D(T).getUTCDay(), fr = (5 - t0 + 7) % 7;
  const qs: [string, number][] = [['Today', 0], ['Tomorrow', 1], ['Day after', 2]];
  if (fr > 2) qs.push(['Friday', fr]);
  qs.push(['Next week', ((1 - t0 + 7) % 7) || 7]);
  const seen = new Set<string>(), out: [string, string][] = [];
  for (const [t, n] of qs) { const s = plus(T, n); if (seen.has(s)) continue; seen.add(s); out.push([t, s]); }
  return out;
}

/** One month's grid, Monday first: null for the blanks before the 1st and after the last day. */
export function month(base: string): { title: string; cells: (string | null)[] } {
  const d0 = D(base), y = d0.getUTCFullYear(), m = d0.getUTCMonth();
  const lead = (d0.getUTCDay() + 6) % 7, nd = new Date(Date.UTC(y, m + 1, 0, 12)).getUTCDate();
  const cells: (string | null)[] = [];
  for (let i = 0; i < lead; i++) cells.push(null);
  for (let i = 1; i <= nd; i++) cells.push(I(new Date(Date.UTC(y, m, i, 12))));
  while (cells.length % 7) cells.push(null);
  return { title: ML[m] + ' ' + y, cells };
}

/** The first of the month `n` months from `base`'s. */
export function shiftMonth(base: string, n: number): string {
  const d = D(base); d.setUTCMonth(d.getUTCMonth() + n, 1); return I(d);
}
