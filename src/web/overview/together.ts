// Overview · both accounts together (handoff 2026-11-18 §4, SunnyOverview 165). Every figure is the server's:
// sunny-home puts the two books together in book S's build (payload.together, together.ts). This file only reads
// it and does the chart's arithmetic: which ranges the closes cover, where a range starts, its change with the
// deposits inside it left out, and the line drawn net of those deposits so it never jumps when money comes in.
import type { J } from '../lib/data';

export interface Part { n: number; today: number; all: number }
export interface Item {
  key: string; t: string; name: string;
  /** "150 puts · Nov 25" or "shares". */
  label: string;
  /** sc | sp | sh | hc | ip */
  k: string;
  n: number; today: number; all: number; value: number; base: number;
  /** Each book's part, null where that book does not hold it. */
  parts: (Part | null)[];
}
export interface PosRow {
  k: string; l: string; sold: boolean;
  today: number; all: number; value: number; base: number; n: number;
  names: number; only: string | null; hedgeCalls: number; hedgePuts: number;
  items: Item[];
}
export interface PosGroup { k: string; l: string; rows: PosRow[] }
export interface Ev { d: string; wd: string; md: string; week: boolean; kind: string; t: string | null; title: string; sub: string }
export interface Month { m: string; l: string; s: string; y: number; per: (number | null)[]; total: number; part: boolean }
export interface Realized {
  month: { per: number[] };
  year: { per: number[] };
  byMonth: Month[];
  trend: { slope: number; fit: number[]; since: string } | null;
  starts: { name: string; start: string; md: string }[];
  dividends: { year: number[] };
}
export interface Together {
  ids: string[];
  names: string[];
  today: string;
  built: string[];
  line: { d: string; v: (number | null)[]; dep: number }[];
  live: { d: string; v: (number | null)[]; today: number; todays: number[] } | null;
  positions: PosGroup[];
  events: Ev[];
  realized: Realized;
}

/** The server's together block, or null while it is missing. */
export function readTogether(payload: J): Together | null {
  const t = payload?.together;
  if (!t || t.error || !Array.isArray(t.line) || !Array.isArray(t.names)) return null;
  return {
    ...t,
    positions: Array.isArray(t.positions) ? t.positions : [],
    events: Array.isArray(t.events) ? t.events : [],
    built: Array.isArray(t.built) ? t.built : [],
  } as Together;
}

/* ── Dates ──────────────────────────────────────────────────────────────── */
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd, wd: new Date(Date.UTC(y, m - 1, dd)).getUTCDay() }; };
/** "Wed Nov 18", with ", 2026" when asked. */
export const dayLabel = (d: string, year = false) => { const p = ymd(d); return `${WD[p.wd]} ${MO[p.m - 1]} ${p.d}` + (year ? `, ${p.y}` : ''); };
/** "Nov 18". */
export const monthDay = (d: string) => { const p = ymd(d); return `${MO[p.m - 1]} ${p.d}`; };
/** The day of the month: 18. */
export const dom = (d: string) => ymd(d).d;
function shiftMonths(d: string, k: number): string {
  const p = ymd(d), idx = p.y * 12 + (p.m - 1) + k, y = Math.floor(idx / 12), m = (idx % 12) + 1;
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return `${y}-${String(m).padStart(2, '0')}-${String(Math.min(p.d, last)).padStart(2, '0')}`;
}

/* ── The value line ─────────────────────────────────────────────────────── */
export type Range = '1W' | 'MTD' | '1M' | '3M' | 'YTD' | '1Y' | 'All';
export const RANGES: Range[] = ['1W', 'MTD', '1M', '3M', 'YTD', '1Y', 'All'];
export const WORDS: Record<Range, string> = {
  '1W': 'past week', MTD: 'this month', '1M': 'past month', '3M': 'past 3 months', YTD: 'this year', '1Y': 'past year', All: 'all time',
};

export interface Pt {
  d: string;
  /** Each book's value; null before that book started. */
  per: (number | null)[];
  /** The books added (a book not started counts as 0). */
  v: number;
  /** Money in that day (deposits, and a book's whole value on the day it first appears). */
  dep: number;
}

const total = (a: (number | null)[]) => a.reduce<number>((s, x) => s + (x == null ? 0 : +x), 0);

/** IBKR's closes by day, then the value now (it replaces today's close when there is one). */
export function points(t: Together): Pt[] {
  const pts: Pt[] = t.line.map((p) => {
    const per = (p.v ?? []).map((x) => (x == null ? null : +x));
    return { d: p.d, per, v: total(per), dep: +(p.dep ?? 0) || 0 };
  });
  if (t.live && t.live.d) {
    const per = (t.live.v ?? []).map((x) => (x == null ? null : +x));
    const last = pts[pts.length - 1];
    if (last && last.d === t.live.d) pts[pts.length - 1] = { d: t.live.d, per, v: total(per), dep: last.dep };
    else if (!last || last.d < t.live.d) pts.push({ d: t.live.d, per, v: total(per), dep: 0 });
  }
  return pts;
}

/** Where each range starts (an index into the points); a range the closes do not reach is left out. */
export function rangeStarts(pts: Pt[], today: string): Partial<Record<Range, number>> {
  const n = pts.length, out: Partial<Record<Range, number>> = {};
  if (!n) return out;
  const lastAt = (pred: (d: string) => boolean) => { for (let i = n - 1; i >= 0; i--) if (pred(pts[i].d)) return i; return -1; };
  const from = (cut: string) => (pts[0].d > cut ? -1 : lastAt((d) => d <= cut));
  const put = (r: Range, i: number) => { if (i >= 0 && i < n - 1) out[r] = i; };
  put('1W', n >= 6 ? n - 6 : -1);
  put('MTD', lastAt((d) => d < today.slice(0, 8) + '01'));
  put('1M', from(shiftMonths(today, -1)));
  put('3M', from(shiftMonths(today, -3)));
  put('YTD', from(`${Number(today.slice(0, 4)) - 1}-12-31`));
  put('1Y', from(shiftMonths(today, -12)));
  out.All = 0;
  return out;
}

export interface View {
  pts: Pt[];
  /** Deposits since the range's first point, at each point (0 at the first). */
  cum: number[];
  /** The drawn values: each point less the money put in since the first point. */
  net: number[];
  path: (a: number, b: number) => string;
  x: (i: number) => number;
  y: (v: number) => number;
}

/** One range: its points and its drawing on a 400 × 100 box. */
export function rangeView(all: Pt[], start: number): View {
  const pts = all.slice(start), n = pts.length, cum: number[] = [];
  let c = 0;
  pts.forEach((p, i) => { if (i) c += p.dep; cum.push(c); });
  const net = pts.map((p, i) => p.v - cum[i]);
  let lo = Math.min(...net), hi = Math.max(...net);
  const pd = (hi - lo) * 0.1 || 1; lo -= pd; hi += pd;
  const x = (i: number) => (n > 1 ? (i / (n - 1)) * 400 : i ? 400 : 0);
  const y = (v: number) => ((hi - v) / (hi - lo)) * 100;
  const path = (a: number, b: number) => {
    if (n === 1) return `M0 ${y(net[0]).toFixed(2)} L400 ${y(net[0]).toFixed(2)}`;
    if (b <= a) return '';
    let d = '';
    for (let q = a; q <= b; q++) d += (q === a ? 'M' : 'L') + x(q).toFixed(1) + ' ' + y(net[q]).toFixed(2);
    return d;
  };
  return { pts, cum, net, path, x, y };
}
