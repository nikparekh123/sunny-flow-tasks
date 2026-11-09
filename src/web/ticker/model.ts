// The ticker page's numbers (README "4 · Ticker page") from sunny-chart's reply, the way the phone reads it
// (Brief/TickerChart.swift, TickerChartLive.swift): five years of daily closes, the price and the previous close,
// the book's legs in this name (Positions), the nearest weekly's walls and the move priced by Friday (Walls). The
// 20 and 50-day averages are worked out here from the closes, as the phone does (TKCalc).
import type { J } from '../lib/data';

export type Range = '1W' | '1M' | '3M' | 'YTD' | '1Y' | 'All';
export const RANGES: Range[] = ['1W', '1M', '3M', 'YTD', '1Y', 'All'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** A strike as the design writes it: 39, 38.5, 42.25. */
export const fk = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));

/** Simple moving average of every close (null until a full window), the phone's TKCalc. */
export function sma(c: number[], L: number): (number | null)[] {
  const a: (number | null)[] = new Array(c.length).fill(null);
  let s = 0;
  for (let i = 0; i < c.length; i++) {
    s += c[i];
    if (i >= L) s -= c[i - L];
    if (i >= L - 1) a[i] = s / L;
  }
  return a;
}

const md = (iso: string) => `${MON[+iso.slice(5, 7) - 1]} ${+iso.slice(8, 10)}`;
const mdy = (iso: string) => `${md(iso)}, ${iso.slice(0, 4)}`;

/** "Sold call 40 ×50, Nov 13" → "Sold call 40 ×50"; "Puts 37.5 ×30" → "Put 37.5 ×30" (the phone's shortLeg). */
const shortLeg = (s: string) => {
  let x = s.replace(/,\s*[A-Z][a-z]{2} \d{1,2}$/, '');
  if (x.startsWith('Puts ')) x = 'Put ' + x.slice(5);
  return x;
};

export interface Line { k: number; label: string; solid: boolean }

/** One line per strike; its legs named short unless two would read the same, sold legs first (the phone's tags). */
export function positionLines(pos: J[]): Line[] {
  const by: { k: number; solid: boolean; legs: string[] }[] = [];
  for (const p of pos ?? []) {
    const k = Number(p.k);
    if (!Number.isFinite(k)) continue;
    const legs = String(p.label ?? '').split(' · ').map((s) => s.trim()).filter(Boolean);
    const e = by.find((x) => Math.abs(x.k - k) < 1e-9);
    if (e) { e.solid = e.solid || !!p.solid; e.legs.push(...legs); } else by.push({ k, solid: !!p.solid, legs });
  }
  return by.map((s) => {
    const sh = s.legs.map(shortLeg);
    const named = s.legs.map((l, i) => (sh.filter((x) => x === sh[i]).length > 1 ? l : sh[i]));
    const order = named.map((_, i) => i).sort((a, b) => {
      const sa = named[a].startsWith('Sold'), sb = named[b].startsWith('Sold');
      return sa !== sb ? (sa ? -1 : 1) : a - b;
    });
    return { k: s.k, solid: s.solid, label: order.map((i) => named[i]).join(' · ') };
  });
}

/** This week's Ceiling and Floor (the design draws those two): "Ceiling 39 · Nov 13". */
export function wallLines(walls: J[]): (Line & { floor: boolean })[] {
  const out: (Line & { floor: boolean })[] = [];
  for (const w of walls ?? []) {
    const [kind, exp] = String(w.label ?? '').split(' · ').map((s) => s.trim());
    const k = Number(w.k);
    if ((kind === 'Ceiling' || kind === 'Floor') && Number.isFinite(k)) {
      out.push({ k, label: `${kind} ${fk(k)}${exp ? ` · ${exp}` : ''}`, solid: false, floor: kind === 'Floor' });
    }
  }
  return out;
}

export interface Series {
  pts: number[];
  dates: string[];
  m20: (number | null)[];
  m50: (number | null)[];
  /** The range's words: "past 3 months"; All reads "since Nov 8, 2021" (the phone's), five years being what is sent. */
  phrase: string;
  /** Under the chart at the left: "3 months ago" (the design's), or the first close's date where those words fail. */
  x0: string;
}

const PHRASE: Record<Range, string> = { '1W': 'past week', '1M': 'past month', '3M': 'past 3 months', YTD: 'this year', '1Y': 'past year', All: '' };
const AGO: Partial<Record<Range, string>> = { '1W': 'Week ago', '1M': 'Month ago', '3M': '3 months ago', '1Y': 'Year ago' };

/** The range's closes (the phone's counts: 1W 5, 1M 22, 3M 63, YTD this year's sessions, 1Y 252, All every close,
    plus the close before them) and its two averages, cut from the averages of the whole history. */
export function series(closes: number[], dates: string[], rg: Range, ma: { m20: (number | null)[]; m50: (number | null)[] }): Series {
  const yr = dates.at(-1)?.slice(0, 4) ?? '';
  const ytd = dates.filter((d) => d.startsWith(yr)).length;
  const n = { '1W': 5, '1M': 22, '3M': 63, YTD: ytd, '1Y': 252, All: closes.length }[rg];
  const s0 = Math.max(0, closes.length - (n + 1));
  const ds = dates.slice(s0);
  const first = ds[0] ?? '';
  return {
    pts: closes.slice(s0), dates: ds, m20: ma.m20.slice(s0), m50: ma.m50.slice(s0),
    phrase: rg === 'All' ? (first ? `since ${mdy(first)}` : '') : PHRASE[rg],
    x0: AGO[rg] ?? (first ? (rg === 'All' ? mdy(first) : md(first)) : ''),
  };
}

/** The labels on one side of the chart, pushed apart so none overlap (the phone's spread, 19 apart), kept inside. */
export function spread(ys: number[], lo: number, hi: number, gap = 19): number[] {
  const order = ys.map((_, i) => i).sort((a, b) => (ys[a] !== ys[b] ? ys[a] - ys[b] : a - b));
  const v = order.map((i) => Math.min(hi, Math.max(lo, ys[i])));
  for (let i = 1; i < v.length; i++) if (v[i] - v[i - 1] < gap) v[i] = v[i - 1] + gap;
  if (v.length && v[v.length - 1] > hi) {
    v[v.length - 1] = hi;
    for (let i = v.length - 2; i >= 0; i--) if (v[i + 1] - v[i] < gap) v[i] = v[i + 1] - gap;
  }
  const out = ys.slice();
  order.forEach((i, j) => { out[i] = v[j]; });
  return out;
}

/** The right-hand labels (the walls) share the room after today with the price pill: those above the price stay
    clear above it, those below clear below it, each 19 apart, kept inside. `above`/`below` are the nearest a
    label's line may sit to the pill's centre (its tag hangs 11 over the line). */
export function spreadAround(ys: number[], lo: number, hi: number, pill: number, above = 16, below = 21, gap = 19): number[] {
  const order = ys.map((_, i) => i).sort((a, b) => (ys[a] !== ys[b] ? ys[a] - ys[b] : a - b));
  const up = order.filter((i) => ys[i] <= pill), dn = order.filter((i) => ys[i] > pill);
  const out = ys.slice();
  let lim = pill - above;
  for (const i of up.slice().reverse()) { out[i] = Math.min(ys[i], lim); lim = out[i] - gap; }
  let top = lo;
  for (const i of up) { if (out[i] < top) out[i] = top; top = out[i] + gap; }
  lim = pill + below;
  for (const i of dn) { out[i] = Math.max(ys[i], lim); lim = out[i] + gap; }
  let bot = hi;
  for (const i of dn.slice().reverse()) { if (out[i] > bot) out[i] = bot; bot = out[i] - gap; }
  return out;
}
