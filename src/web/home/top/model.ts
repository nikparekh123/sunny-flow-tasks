// The account chart's arithmetic (README 1, items 2 to 4), the phone's ChartModel (Home/AccountChart.swift) on the
// web: daily account values from the Home payload's chart (days, nav, deposits_cum, ...), today's point live.
// - A range starts on the last close on or before its start date; 1W is the last 5 closes plus the one before.
// - Ranges longer than the history are hidden, except All (1W and YTD always show), as the phone does.
// - The change takes deposits out (the phone's depositLine shows them on their own line).
// - Stats: Realized, Interest and Fees over the range; Unrealized, Time value and Margin at its last point.
import type { J } from '../../lib/data';
import { arrow, C, money, pct } from '../../lib/format';

export type Range = '1W' | '1M' | '3M' | 'YTD' | '1Y' | 'All';
export const RANGES: Range[] = ['1W', '1M', '3M', 'YTD', '1Y', 'All'];
/** The change line's words (the design's RGD and the phone's ChartRange.words). */
export const WORDS: Record<Range, string> = {
  '1W': 'past week', '1M': 'past month', '3M': 'past 3 months', YTD: 'this year', '1Y': 'past year', All: 'all time',
};

const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const parts = (iso: string) => { const [y, m, d] = iso.split('-').map(Number); return { y, m, d, wd: new Date(Date.UTC(y, m - 1, d)).getUTCDay() }; };
const iso = (y: number, m: number, d: number) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

/** An ISO date moved by whole months, clamped to the month's last day (Calendar.date(byAdding: .month) on the phone). */
export function shiftMonths(day: string, months: number): string {
  const p = parts(day);
  const idx = p.y * 12 + (p.m - 1) + months, y = Math.floor(idx / 12), m = (idx % 12) + 1;
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return iso(y, m, Math.min(p.d, last));
}
/** An ISO date moved by days. */
export function addDays(day: string, n: number): string {
  const p = parts(day), t = new Date(Date.UTC(p.y, p.m - 1, p.d + n));
  return iso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}
export const weekday = (day: string) => parts(day).wd;
/** "Thu Oct 15", with ", 2026" on 1Y and All (the design's hover date). */
export function dayLabel(day: string, r: Range): string {
  const p = parts(day);
  return `${WD[p.wd]} ${MO[p.m - 1]} ${p.d}` + (r === '1Y' || r === 'All' ? `, ${p.y}` : '');
}

export interface Line { k: string; v: string; c: string; l: string }

export interface ChartModel {
  n: number;
  days: string[];
  nav: (i: number) => number;
  dep: (s: number, i: number) => number;
  start: (r: Range) => number;
  available: (r: Range) => boolean;
}

export function chartModel(payload: J): ChartModel | null {
  const c = payload?.chart;
  const days: string[] = Array.isArray(c?.days) ? c.days : [];
  if (!days.length || !Array.isArray(c?.nav)) return null;
  const n = days.length, today: string = payload?.today ?? c.to ?? days[n - 1];
  const live = payload?.account?.value;
  const nav = (i: number) => (i === n - 1 && c.live_last && typeof live === 'number' ? live : +(c.nav[i] ?? 0));
  const dc: number[] | undefined = c.deposits_cum;
  const dep = (s: number, i: number) => (dc && dc[s] != null && dc[i] != null ? dc[i] - dc[s] : 0);
  const lastOnOrBefore = (from: string) => { for (let i = n - 1; i >= 0; i--) if (days[i] <= from) return i; return 0; };
  const start = (r: Range) => {
    if (n < 2) return 0;
    switch (r) {
      case '1W': return Math.max(0, n - 6);
      case 'All': return 0;
      case '1M': return lastOnOrBefore(shiftMonths(today, -1));
      case '3M': return lastOnOrBefore(shiftMonths(today, -3));
      case '1Y': return lastOnOrBefore(shiftMonths(today, -12));
      case 'YTD': return lastOnOrBefore(today.slice(0, 4) + '-01-01');
    }
  };
  const from: string = c.from ?? days[0];
  const available = (r: Range) => {
    if (n < 2) return r === 'All';
    switch (r) {
      case 'All': case '1W': case 'YTD': return true;
      case '1M': return from <= shiftMonths(today, -1);
      case '3M': return from <= shiftMonths(today, -3);
      case '1Y': return from <= shiftMonths(today, -12);
    }
  };
  return { n, days, nav, dep, start, available };
}

/** What the chart draws for a range: the points, the start value, the change and its tone. */
export interface RangeView {
  s: number; e: number;
  ser: number[]; labs: string[]; deps: number[];
  Sv: number; change: number; up: boolean; color: string;
  path: string; ys: number[]; y0: number;
}

export function rangeView(m: ChartModel, r: Range): RangeView {
  const e = m.n - 1, s = Math.min(m.start(r), e);
  const ser: number[] = [], labs: string[] = [], deps: number[] = [];
  for (let i = s; i <= e; i++) { ser.push(m.nav(i)); labs.push(dayLabel(m.days[i], r)); deps.push(m.dep(s, i)); }
  const Sv = ser[0];
  const change = ser[ser.length - 1] - Sv - deps[deps.length - 1];
  const up = change >= 0;
  // The design's scale: the line and the start value, 8% headroom above and below.
  let lo = Math.min(...ser, Sv), hi = Math.max(...ser, Sv);
  const pd = (hi - lo) * 0.08 || 1; lo -= pd; hi += pd;
  const cy = (v: number) => ((hi - v) / (hi - lo)) * 100;
  const k = ser.length;
  const ys = ser.map(cy);
  const path = k === 1
    ? `M0 ${ys[0].toFixed(2)} L400 ${ys[0].toFixed(2)}`
    : ys.map((y, i) => (i ? 'L' : 'M') + ((i / (k - 1)) * 400).toFixed(1) + ' ' + y.toFixed(2)).join(' ');
  return { s, e, ser, labs, deps, Sv, change, up, color: up ? C.green : C.red, path, ys, y0: cy(Sv) };
}

/** "▼ $2.6K · 2.7%" for a change from a start value. */
export const changeText = (d: number, from: number) => `${arrow(d)} ${money(d)} · ${pct(from ? (Math.abs(d) / Math.abs(from)) * 100 : 0)}`;

/** The day's change in account value on the brief's day (open and post): the live figure for the current brief,
    else that day's close against the one before. */
export function todayChange(m: ChartModel | null, payload: J, day: string | undefined, current: boolean): number | null {
  const t = payload?.account?.today;
  if (current && t && typeof t.amount === 'number') return t.amount;
  if (!m || !day) return null;
  const i = m.days.indexOf(day);
  if (i < 1) return null;
  return m.nav(i) - m.nav(i - 1) - m.dep(i - 1, i);
}

/** The week's change in account value for a Week in Review dated `day`: its Friday's close against the close before
    its Monday. */
export function weekChange(m: ChartModel | null, day: string | undefined): number | null {
  if (!m || !day) return null;
  const wd = weekday(day), monday = addDays(day, wd === 0 ? -6 : 1 - wd), friday = addDays(monday, 4);
  let e = -1, b = -1;
  for (let i = 0; i < m.n; i++) { if (m.days[i] <= friday) e = i; if (m.days[i] < monday) b = i; }
  if (e < 0 || b < 0 || e <= b) return null;
  return m.nav(e) - m.nav(b) - m.dep(b, e);
}

export interface Stat { k: string; l: string; v: string; c: string; tv?: boolean }

/** The stats row (README 1, item 4): Realized · Unrealized · Time value › · Margin · Interest · Fees. */
export function stats(payload: J, m: ChartModel | null, r: Range): Stat[] {
  const c = payload?.chart, a = payload?.account ?? {};
  const loss = (x: number) => (Math.round(x) < 0 ? C.red : C.ink);
  if (!m || !c) {
    const u = +(a.unrealized ?? 0);
    return [
      { k: 'r', l: 'Realized', v: money(0), c: C.ink },
      { k: 'u', l: 'Unrealized', v: money(u), c: loss(u) },
      { k: 'tv', l: 'Time value ›', v: money(a.time_value_sold), c: C.ink, tv: true },
      { k: 'm', l: 'Margin', v: money(a.margin), c: C.ink },
      { k: 'i', l: 'Interest', v: money(0), c: C.ink },
      { k: 'f', l: 'Fees', v: money(0), c: C.ink },
    ];
  }
  const e = m.n - 1, s = Math.min(m.start(r), e), live = !!c.live_last;
  const diff = (k: string) => (+(c[k]?.[e] ?? 0)) - (+(c[k]?.[s] ?? 0));
  const realized = diff('realized_cum');
  const unreal = live && a.unrealized != null ? +a.unrealized : +(c.unrealized?.[e] ?? 0);
  const tv = live && a.time_value_sold != null ? +a.time_value_sold : +(c.time_value?.[e] ?? 0);
  const margin = live && a.margin != null ? +a.margin : +(c.margin?.[e] ?? 0);
  const interest = diff('interest_cum'), fees = diff('commission_cum');
  return [
    { k: 'r', l: 'Realized', v: money(realized), c: loss(realized) },
    { k: 'u', l: 'Unrealized', v: money(unreal), c: loss(unreal) },
    { k: 'tv', l: 'Time value ›', v: money(tv), c: C.ink, tv: true },
    { k: 'm', l: 'Margin', v: money(margin), c: C.ink },
    // Red says negative (README): interest paid on margin is red, interest earned on cash ink.
    { k: 'i', l: 'Interest', v: money(interest), c: loss(interest) },
    { k: 'f', l: 'Fees', v: money(fees), c: loss(fees) },
  ];
}
