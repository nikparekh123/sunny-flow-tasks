/**
 * The Positions engine (handoff 2026-11-13-positions, README §3; Web Dark v2 `r150x`, `tk150`, `tk150b`, `d.sd153`).
 * ONE calculation block for the web Positions page and the phone's Positions tab (154a). Pure functions: no I/O, no
 * clock, no React. The phone ports this file to Swift line for line, so every function says what it reads and what it
 * gives back, in the README's words.
 *
 * Reused, not forked: the normal CDF, the cover rule (cover()) and the SD calculator's rule (calc(), on the server)
 * come from sd-engine.ts. The lane maths here is the README's §3.9.5 (P&L at expiry, the zone rule fixed in the
 * 13 Nov audit, lognormal chance of profit), which is a different rule from sd-engine's sale() on purpose.
 *
 * Notation (README §3): S0 the price now · K a strike · IV the expiry's implied volatility · td trading days to the
 * expiry · cd calendar days · m = IV × √(td ÷ 252) one SD as a log move · the price at k SD is S0 × e^(k·m) ·
 * z(x) = ln(x ÷ S0) ÷ m.
 *
 * Words: no em dashes anywhere (Nik). Money is never written here; strikes, prices, SD and % are.
 */
import { N, cover, fk, type Leg as SdLeg, type Name as SdName } from './sd-engine.ts';

export { N, fk };

/* ── Notation ─────────────────────────────────────────────────────────────── */

/** One SD as a log move: IV × √(td ÷ 252). */
export const sdMove = (iv: number, td: number): number => (iv > 0 && td > 0 ? iv * Math.sqrt(td / 252) : 0);
/** The price k SD from S0 (k < 0 below). */
export const atSd = (S0: number, k: number, m: number): number => S0 * Math.exp(k * m);
/** How many SD a price is from S0 (signed; 0 when m is 0). */
export const zOf = (x: number, S0: number, m: number): number => (m > 0 && x > 0 && S0 > 0 ? Math.log(x / S0) / m : 0);
/** $2.80 (a price, two decimals, no sign). */
export const f2 = (x: number): string => '$' + Math.abs(x).toFixed(2);
/** 2.7% from a fraction: one decimal, two under 0.1%, no sign. */
export const pcx = (x: number): string => { const a = Math.abs(x) * 100; return (a > 0 && a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%'; };
/** ↑2.7% or ↓2.7% from a fraction (never a minus sign). */
export const arrowPct = (x: number): string => (x >= 0 ? '↑' : '↓') + pcx(x);
/** An SD level with the fewest digits: 0.25, 0.5, 1, 1.25 (README §5). */
export const sdK = (k: number): string => String(+k.toFixed(2));

/** Black-Scholes with no rates or dividends (README §3), T in years = cd ÷ 365. p value a share, d delta, g gamma,
    t theta a calendar day, vg vega a vol point. At or past expiry: intrinsic, delta 0 or ±1. */
export function bs(put: boolean, S: number, K: number, T: number, iv: number): { p: number; d: number; g: number; t: number; vg: number } {
  if (!(T > 1e-6) || !(iv > 0)) {
    return { p: Math.max(0, put ? K - S : S - K), d: put ? (S < K ? -1 : 0) : (S > K ? 1 : 0), g: 0, t: 0, vg: 0 };
  }
  const sq = iv * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * iv * iv * T) / sq, d2 = d1 - sq;
  const n1 = Math.exp(-d1 * d1 / 2) / Math.sqrt(2 * Math.PI);
  return {
    p: put ? K * N(-d2) - S * N(-d1) : S * N(d1) - K * N(d2),
    d: put ? N(d1) - 1 : N(d1),
    g: n1 / (S * sq),
    t: -S * n1 * iv / (2 * Math.sqrt(T)) / 365,
    vg: S * n1 * Math.sqrt(T) / 100,
  };
}

/* ── The SD ramp (README §4: oklch(0.86 0.03 282) to oklch(0.42 0.085 277), six steps) ───────────────────────── */

/** The SD levels the lanes draw, and their colours, nearest level first. */
export const LV = [0.25, 0.5, 0.75, 1, 1.5, 2];
export const SD_RAMP = ['oklch(0.86 0.03 282)', 'oklch(0.77 0.055 281)', 'oklch(0.68 0.08 280)', 'oklch(0.59 0.095 279)', 'oklch(0.50 0.095 278)', 'oklch(0.42 0.085 277)'];
/** The ramp colour of the level nearest |k|. */
export function sdColour(k: number): string {
  const a = Math.abs(k);
  let bi = 0;
  LV.forEach((v, i) => { if (Math.abs(v - a) < Math.abs(LV[bi] - a)) bi = i; });
  return SD_RAMP[bi];
}

/* ── Trading days (the calculator's count, sd-engine tradingYears, here as days) ─────────────────────────────── */

/** Trading days after `today` through `ex` (weekends and `closed` days left out). On the expiry day, the share of the
    session left (at least a quarter hour), so an expiring leg still has an SD. `mins`: New York minutes now. */
export function tradingDays(today: string, ex: string, closed: Set<string>, mins: number): number {
  let n = 0;
  const d = new Date(today + 'T12:00:00Z'), end = Date.parse(ex + 'T12:00:00Z');
  for (d.setUTCDate(d.getUTCDate() + 1); d.getTime() <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    const w = d.getUTCDay(), s = d.toISOString().slice(0, 10);
    if (w !== 0 && w !== 6 && !closed.has(s)) n++;
  }
  return n > 0 ? n : ex === today ? Math.max(0.25, (16 * 60 - mins) / 60) / 6.5 : 0;
}

/* ── §3.3 Sold, in SD ─────────────────────────────────────────────────────── */

/** One sold option leg, as the book holds it. `entry` is the premium a share it was sold at, `mark` today's mark,
    `iv` the IV it is priced on (the leg's own, Nik 11 Nov), `td`/`cd` trading and calendar days to its expiry, `z0`
    the signed SD it sat at when sold (saved at the fill; null when not saved: no hollow dot, never back-solved). */
export interface SoldIn {
  t: string; S: number; put: boolean; K: number; n: number; ex: string; exLabel: string;
  entry: number | null; mark: number | null; iv: number; td: number; cd: number; z0?: number | null;
}
export type Tone = 'red' | 'orange' | 'quiet';
export interface SoldRow extends SoldIn {
  key: string;
  /** SD now, signed (puts below today read negative), and its size. */
  z: number; a: number;
  itm: boolean;
  /** The size of the SD when sold, and whether the price came closer since, on the out-of-the-money side (null: not saved). */
  a0: number | null; closer: boolean | null;
  /** |N(d1)| for calls, |N(d1) − 1| for puts. */
  delta: number;
  /** Kept = 1 − mark ÷ entry (negative: lost). Null without an entry or a mark. */
  kept: number | null;
  /** The per-share breakeven with the whole premium for this name and expiry on this leg (the cross when the name
      sells both sides at that expiry), its SD (signed), whether the price is already past it. */
  be: number | null; zb: number | null; past: boolean;
  /** Shown only under 0.5 SD or in the money. */
  showBE: boolean;
  tone: Tone;
  /** Sort key: in the money first (-1), then SD now, nearest first. */
  rank: number;
  /** Where to draw on the track, 0 to 1 (2.2 SD each side of today; pinned at the edges). */
  x: number; xb: number | null; x0: number | null;
}

/** The track's half width in SD. */
export const TRACK_SD = 2.2;
/** A signed SD on the track, 0 to 1, pinned at ±2.2 SD. */
export const trackX = (z: number): number => 0.5 + Math.max(-TRACK_SD, Math.min(TRACK_SD, z)) / TRACK_SD / 2;
/** The colours: red under 0.5 SD, orange 0.5 to 1 SD, quiet past 1 SD; in the money red (filled). */
export const toneOf = (a: number, itm: boolean): Tone => (itm || a < 0.5 ? 'red' : a < 1 ? 'orange' : 'quiet');

/** Every sold leg on one SD axis, one row per leg (never added across strikes), in the money first, then SD now,
    nearest first. */
export function soldInSd(legs: SoldIn[]): { rows: SoldRow[]; within: number; inTheMoney: number } {
  // The premium of each name and expiry, all sides together (the cross).
  const tot = new Map<string, number>();
  for (const l of legs) if (l.entry != null) tot.set(l.t + '|' + l.ex, (tot.get(l.t + '|' + l.ex) ?? 0) + l.n * 100 * l.entry);
  const rows = legs.filter((l) => l.S > 0 && l.K > 0 && l.n > 0).map((l): SoldRow => {
    const m = sdMove(l.iv, l.td), z = zOf(l.K, l.S, m), a = Math.abs(z);
    const itm = l.put ? l.S < l.K : l.S > l.K;
    const b = bs(l.put, l.S, l.K, l.cd / 365, l.iv), delta = Math.abs(b.d);
    const all = tot.get(l.t + '|' + l.ex);
    const be = all != null && l.entry != null ? (l.put ? l.K - all / (l.n * 100) : l.K + all / (l.n * 100)) : null;
    const zb = be != null && be > 0 ? zOf(be, l.S, m) : null;
    const past = be != null && (l.put ? l.S <= be : l.S >= be);
    const a0 = l.z0 != null && Number.isFinite(l.z0) ? Math.abs(l.z0) : null;
    // Closer or further on the out-of-the-money side (signed: a strike the price went through came closer).
    const out = (zz: number) => (l.put ? -zz : zz);
    const kept = l.entry != null && l.entry > 0 && l.mark != null ? 1 - l.mark / l.entry : null;
    return {
      ...l, key: `${l.t}|${l.put ? 'p' : 'c'}|${l.K}|${l.ex}`, z, a, itm, a0, closer: a0 == null ? null : out(z) < out(l.z0!) - 0.005,
      delta, kept, be, zb, past, showBE: be != null && (itm || a < 0.5), tone: toneOf(a, itm), rank: itm ? -1 : a,
      x: trackX(z), xb: zb == null ? null : trackX(zb), x0: l.z0 == null || !Number.isFinite(l.z0) ? null : trackX(l.z0),
    };
  }).sort((p, q) => p.rank - q.rank || p.t.localeCompare(q.t));
  return { rows, within: rows.filter((r) => !r.itm && r.a < 0.5).length, inTheMoney: rows.filter((r) => r.itm).length };
}

/** The name strip's dot (A7): red when the name is short at the priced move by Friday (Home's brief.names st = 2),
    orange when one of its sold legs is in the money or within 0.5 SD, else none. */
export function nameDot(st: number | null | undefined, rows: SoldRow[], t: string): 'red' | 'orange' | null {
  if (st === 2) return 'red';
  return rows.some((r) => r.t === t && (r.itm || r.a < 0.5)) ? 'orange' : null;
}

/* ── §3.9.5 The lanes' maths: Held, + New, = Both ─────────────────────────── */

/** A short option at the chosen expiry: contracts and the premium a share. */
export interface ShortLeg { put: boolean; K: number; n: number; p: number }

/** P&L at expiry for a set of short legs: Σ n × 100 × (premium − intrinsic). */
export const plAtExpiry = (set: ShortLeg[], x: number): number =>
  set.reduce((a, l) => a + l.n * 100 * (l.p - Math.max(0, l.put ? l.K - x : x - l.K)), 0);

/** The breakevens (the 13 Nov audit's zone rule): the P&L on S0 × e^(z·m), z from −4 to 4 (801 points); the stretches
    where the set makes money; the one that holds S0, or the nearest one when the price is outside it (an in-the-money
    strike). dn/up null = past 4 SD on that side; none = the set never makes money. */
export function breakevens(set: ShortLeg[], S0: number, m: number): { dn: number | null; up: number | null; none: boolean } {
  if (!set.length || !(m > 0) || !(S0 > 0)) return { dn: null, up: null, none: true };
  const GX = Array.from({ length: 801 }, (_, i) => S0 * Math.exp((-4 + (8 * i) / 800) * m)), ys = GX.map((x) => plAtExpiry(set, x));
  const cx = (i: number) => GX[i - 1] + (GX[i] - GX[i - 1]) * ys[i - 1] / (ys[i - 1] - ys[i]);
  const iv: [number | null, number | null][] = [];
  let lo: number | null = null;
  for (let i = 0; i < GX.length; i++) {
    const p = ys[i] > 0, q = i > 0 && ys[i - 1] > 0;
    if (p && !q) lo = i === 0 ? null : cx(i);
    if (!p && q) iv.push([lo, cx(i)]);
  }
  if (ys[GX.length - 1] > 0) iv.push([lo, null]);
  if (!iv.length) return { dn: null, up: null, none: true };
  const dz = ([a, b]: [number | null, number | null]) => ((a == null || a <= S0) && (b == null || b >= S0) ? 0
    : Math.min(a == null ? Infinity : Math.abs(a - S0), b == null ? Infinity : Math.abs(b - S0)));
  const [dn, up] = iv.reduce((p, c) => (dz(c) < dz(p) ? c : p));
  return { dn, up, none: false };
}

/** Chance of profit = N(z(up)) − N(z(dn)), lognormal with no drift; z = ±9 for a side with no breakeven, 0 when
    nothing makes money. */
export function chanceOfProfit(r: { dn: number | null; up: number | null; none: boolean }, S0: number, m: number): number {
  if (r.none) return 0;
  return N(r.up == null ? 9 : zOf(r.up, S0, m)) - N(r.dn == null ? -9 : zOf(r.dn, S0, m));
}

export interface Lane {
  has: boolean;
  /** The breakevens of the whole set (the cross when both sides are in it). */
  dn: number | null; up: number | null; none: boolean;
  /** Chance of profit, 0 to 1. */
  cp: number;
  /** The premium in, $. */
  inc: number;
  calls: number; puts: number;
  /** Each side alone (only when the set has both sides): calls' breakeven up, puts' breakeven down. */
  callsAlone: number | null; putsAlone: number | null;
  /** The strikes, for the rings. */
  strikes: number[];
}
export function lane(set: ShortLeg[], S0: number, m: number): Lane {
  if (!set.length) return { has: false, dn: null, up: null, none: true, cp: 0, inc: 0, calls: 0, puts: 0, callsAlone: null, putsAlone: null, strikes: [] };
  const r = breakevens(set, S0, m), cs = set.filter((l) => !l.put), ps = set.filter((l) => l.put), both = cs.length > 0 && ps.length > 0;
  return {
    has: true, dn: r.dn, up: r.up, none: r.none, cp: chanceOfProfit(r, S0, m),
    inc: set.reduce((a, l) => a + l.n * 100 * l.p, 0),
    calls: cs.reduce((a, l) => a + l.n, 0), puts: ps.reduce((a, l) => a + l.n, 0),
    callsAlone: both ? breakevens(cs, S0, m).up : null, putsAlone: both ? breakevens(ps, S0, m).dn : null,
    strikes: [...new Set(set.map((l) => l.K))],
  };
}
/** The cross adds |z(cross)| − |z(alone)| in SD (how much room the other side's premium gives this side). */
export const crossAdds = (cross: number, alone: number, S0: number, m: number): number =>
  Math.abs(zOf(cross, S0, m)) - Math.abs(zOf(alone, S0, m));

/* ── §3.9.3 Touched and closed through ────────────────────────────────────── */

/** Today's session (the server's `day`): the prior close, today's high and low, the last price, and the official
    close once confirmed after 4:00 PM ET. */
export interface Day { prev: number; high: number; low: number; last: number; closedToday: boolean; close?: number }
export type LevelState = 'idle' | 'touch' | 'up' | 'dn';
/** Idle, touched today (today's high or low reached it), or closed through (the prior close and the official close sit
    on opposite sides). An intraday cross stays "touched" until the close. No session: idle. */
export function levelState(L: number | null | undefined, day: Day | null | undefined): LevelState {
  if (L == null || !Number.isFinite(L) || !day) return 'idle';
  if (day.closedToday && day.close != null && (day.prev - L) * (day.close - L) < 0) return day.close > L ? 'up' : 'dn';
  return L >= Math.min(day.low, day.high) && L <= Math.max(day.low, day.high) ? 'touch' : 'idle';
}

/* ── Move: last week, this week, the pace ─────────────────────────────────── */

export interface Close { d: string; c: number }
const addDays = (d: string, n: number) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
/** The Monday of the week `today` falls in (Saturday and Sunday belong to the week just ended). */
export const mondayOf = (today: string): string => { const w = new Date(today + 'T12:00:00Z').getUTCDay(); return addDays(today, w === 0 ? -6 : 1 - w); };

export interface Move {
  /** Last week: Friday's close to Friday's close, the range of closes behind it. */
  lw: { from: number; to: number; fromD: string; toD: string; r: number; lo: number; hi: number } | null;
  /** This week so far: last Friday's close to now, and that move in weekly SD at the expiry's IV. */
  tw: { from: number; r: number; sd: number } | null;
  /** The 5-day pace carried to the expiry: S0 × (1 + r5 ÷ 5 × td), held inside ±1.5 SD. Flat under 0.5%. */
  pace: { r5: number; r20: number | null; flat: boolean; to: number; capped: boolean } | null;
}
/** `closes`: daily closes (any order); only sessions before `today` count, S0 is today's price. */
export function moveOf(closes: Close[], S0: number, today: string, iv: number, td: number, m: number): Move {
  const P = closes.filter((x) => x.d < today && x.c > 0).sort((a, b) => a.d.localeCompare(b.d));
  if (!P.length || !(S0 > 0)) return { lw: null, tw: null, pace: null };
  const mon = mondayOf(today), lastBefore = (d: string) => [...P].reverse().find((x) => x.d < d) ?? null;
  const w1 = lastBefore(mon), w0 = w1 ? lastBefore(addDays(mon, -7)) : null;
  const wk = w0 && w1 ? P.filter((x) => x.d >= w0.d && x.d <= w1.d).map((x) => x.c) : [];
  const wsd = iv > 0 ? iv * Math.sqrt(5 / 252) : 0;
  const lw = w0 && w1 ? { from: w0.c, to: w1.c, fromD: w0.d, toD: w1.d, r: w1.c / w0.c - 1, lo: Math.min(...wk), hi: Math.max(...wk) } : null;
  const tw = w1 ? { from: w1.c, r: S0 / w1.c - 1, sd: wsd > 0 ? Math.abs(Math.log(S0 / w1.c)) / wsd : 0 } : null;
  let pace: Move['pace'] = null;
  if (P.length >= 5) {
    const r5 = S0 / P[P.length - 5].c - 1, r20 = P.length >= 20 ? S0 / P[P.length - 20].c - 1 : null;
    const pj0 = S0 * (1 + (r5 / 5) * td), lo = atSd(S0, -1.5, m), hi = atSd(S0, 1.5, m);
    const to = m > 0 ? Math.max(lo, Math.min(hi, pj0)) : pj0;
    pace = { r5, r20, flat: Math.abs(r5) < 0.005, to, capped: Math.abs(to - pj0) > 0.005 };
  }
  return { lw, tw, pace };
}

/* ── IV: rank and the tone ────────────────────────────────────────────────── */

/** IV rank = (IV − 52-week low) ÷ (high − low) × 100, else the server's rank. Rich if rank ≥ 70 or IV ≥ 1.3 × HV20;
    cheap if rank ≤ 20 or IV ≤ HV20; else fair. Null without the history. */
export function ivTone(iv: number, t: { ivLow52?: number | null; ivHigh52?: number | null; ivRank?: number | null; hv20?: number | null } | null | undefined):
  { rank: number | null; ratio: number | null; tone: 'rich' | 'cheap' | 'fair' | null } {
  if (!t) return { rank: null, ratio: null, tone: null };
  const lo = t.ivLow52, hi = t.ivHigh52;
  const rank = lo != null && hi != null && hi > lo ? Math.max(0, Math.min(100, Math.round(((iv - lo) / (hi - lo)) * 100))) : t.ivRank != null ? Math.round(t.ivRank) : null;
  const ratio = t.hv20 && t.hv20 > 0 ? iv / t.hv20 : null;
  if (rank == null && ratio == null) return { rank, ratio, tone: null };
  const rich = (rank != null && rank >= 70) || (ratio != null && ratio >= 1.3);
  const cheap = !rich && ((rank != null && rank <= 20) || (ratio != null && ratio <= 1));
  return { rank, ratio, tone: rich ? 'rich' : cheap ? 'cheap' : 'fair' };
}

/* ── A6 Cover check (sd-engine cover(), the engine's own rule) ────────────── */

/** Calls sold = calls still open at this expiry and later + the new sale; covered = ⌊shares ÷ 100⌋ first, then OTM
    calls bought that end on or after each sold call (LEAPS never count). */
export function coverCheck(o: { shares: number; held: { K: number; n: number; ex: string }[]; otm: { n: number; ex: string }[]; sale: { K: number; n: number } | null; ex: string }):
  { sold: number; open: number; sale: number; byShares: number; byOtm: number; uncovered: number; capShares: number; capOtm: number } {
  const open = o.held.filter((l) => l.ex >= o.ex);
  const sold: SdLeg[] = [...open, ...(o.sale && o.sale.n > 0 ? [{ K: o.sale.K, n: o.sale.n, ex: o.ex }] : [])]
    .sort((a, b) => a.ex.localeCompare(b.ex)).map((l) => ({ K: l.K, n: l.n, ex: l.ex, at: null, iv: 0, days: 0 }));
  const longCalls: SdLeg[] = o.otm.map((l) => ({ K: 0, n: l.n, ex: l.ex, at: null, iv: 0, days: 0 }));
  const c = cover({ shares: o.shares, soldCalls: sold, longCalls } as unknown as SdName);
  return {
    sold: c.n, open: open.reduce((a, l) => a + l.n, 0), sale: o.sale?.n ?? 0, byShares: c.covered, byOtm: c.capped, uncovered: c.naked,
    capShares: Math.floor(o.shares / 100), capOtm: o.otm.filter((l) => l.ex >= o.ex).reduce((a, l) => a + l.n, 0),
  };
}

/* ── §3.9.4 The read ──────────────────────────────────────────────────────── */

export interface Levels {
  ceiling?: number | null; floor?: number | null; accelerator?: number | null;
  resistance?: number | null; support?: number | null;
  sma20?: number | null; sma50?: number | null; sma100?: number | null; sma200?: number | null;
}
export interface ReadSide { K: number; k: number }
export interface ReadIn {
  S0: number;
  /** The chain's strike step (half a step, or 0.6% of S0, is "on" a strike). */
  step: number;
  /** The sale's sides (web: the sale being picked; phone: what is sold). Null leaves that side out. */
  call: ReadSide | null; put: ReadSide | null;
  levels: Levels;
  /** Calls left uncovered after the sale, and the calls in the sale (the lead counts only a new call sale). */
  uncovered: number; newCalls: number;
  earnings: boolean; dividend: boolean;
  /** Where the 5-day pace lands by the expiry (null when flat or unknown). */
  pace: number | null;
  /** The sale's chance of profit, 0 to 1 (null leaves the odds out). */
  odds: number | null;
  /** Premiums high, low or normal (ivTone). */
  tone: 'rich' | 'cheap' | 'fair' | null;
}
const anA = (n: number) => (/^(8|11|18)$|^8\d$/.test(String(n)) ? 'an' : 'a');
const lvl = (v: number) => fk(+v.toFixed(2));
/** The read: one lead, one line on both strikes, the odds, the premiums if there is room; 150 characters at most. */
export function theRead(x: ReadIn): { lead: string; rest: string } {
  const { S0, call, put } = x, L = x.levels, tol = Math.max(x.step * 0.5, S0 * 0.006);
  const ok = (v: number | null | undefined): v is number => v != null && Number.isFinite(v) && v > 0;
  const MA: [string, number | null | undefined][] = [['the 20-day', L.sma20], ['the 50-day', L.sma50], ['the 100-day', L.sma100], ['the 200-day', L.sma200]];
  const CM = ([['the ceiling', L.ceiling], ['resistance', L.resistance], ...MA] as [string, number | null | undefined][]).filter((m): m is [string, number] => ok(m[1]));
  const PM = ([['the floor', L.floor], ['support', L.support], ...MA] as [string, number | null | undefined][]).filter((m): m is [string, number] => ok(m[1]));
  const Kc = call?.K ?? null, Kp = put?.K ?? null;
  const cItm = Kc != null && S0 > Kc, pItm = Kp != null && S0 < Kp;
  const cOn = Kc == null ? [] : CM.filter((m) => Math.abs(m[1] - Kc) <= tol);
  const cIn = Kc == null ? [] : CM.filter((m) => m[1] > S0 && m[1] < Kc - tol).sort((p, q) => p[1] - q[1]);
  const pOn = Kp == null ? [] : PM.filter((m) => Math.abs(m[1] - Kp) <= tol);
  const pIn = Kp == null ? [] : PM.filter((m) => m[1] < S0 && m[1] > Kp + tol).sort((p, q) => q[1] - p[1]);
  const A = ok(L.accelerator) ? L.accelerator : null;
  const accIn = A != null && Kp != null && A < S0 && A >= Kp - tol, accNear = accIn && Math.abs(A! - Kp!) <= x.step * 2;
  const cM = cOn[0] ?? cIn[0] ?? null, pM = pOn[0] ?? pIn[0] ?? null;
  const mvC = x.pace != null && Kc != null && x.pace >= Kc - tol, mvP = x.pace != null && Kp != null && x.pace <= Kp + tol;
  const lead = x.uncovered > 0 && x.newCalls > 0 ? `${x.uncovered} ${x.uncovered === 1 ? 'call' : 'calls'} would be uncovered.`
    : cItm ? 'Your call is in the money.' : pItm ? 'Your put is in the money.'
    : x.earnings ? 'Earnings land before expiry.' : x.dividend ? 'The dividend lands before expiry.'
    : accNear ? 'A drop could speed up.' : mvC ? 'Running toward your call.' : mvP ? 'Sliding toward your put.'
    : call && !cM ? 'The call has no cushion.' : put && !pM ? 'The put has no cushion.'
    : call && put ? 'Both strikes look covered.' : call ? 'The call looks covered.' : 'The put looks covered.';
  const cP = Kc == null ? '' : cItm ? `The price is ${f2(S0 - Kc)} past call ${fk(Kc)}` : cOn.length ? `Call ${fk(Kc)} sits on ${cM![0]}`
    : cIn.length ? `Call ${fk(Kc)} has ${cM![0]} at ${lvl(cM![1])} in front` : `Nothing caps call ${fk(Kc)}`;
  const pP = Kp == null ? '' : pItm ? `the price is ${f2(Kp - S0)} under put ${fk(Kp)}` : accNear ? `put ${fk(Kp)} sits by a fast drop at ${fk(A!)}`
    : pOn.length ? `put ${fk(Kp)} sits on ${pM![0]}` : pIn.length ? `put ${fk(Kp)} has ${pM![0]} at ${lvl(pM![1])} in front` : `nothing holds a fall to put ${fk(Kp)}`;
  const s1 = !cP && !pP ? '' : (!pP ? cP : !cP ? pP.charAt(0).toUpperCase() + pP.slice(1) : cP + '; ' + pP) + '.';
  const sdP = call && put ? (call.k === put.k ? `${sdK(call.k)} SD` : `${sdK(call.k)} and ${sdK(put.k)} SD`) : call ? `${sdK(call.k)} SD` : put ? `${sdK(put.k)} SD` : '';
  const cpN = x.odds == null ? null : Math.round(x.odds * 100);
  const s2 = cpN == null ? '' : cItm || pItm ? `${anA(cpN) === 'an' ? 'An' : 'A'} ${cpN}% chance you still finish ahead.` : `At ${sdP}, ${anA(cpN)} ${cpN}% chance you finish ahead.`;
  const s3 = x.earnings ? 'Premiums are up for the report.' : x.tone === 'rich' ? 'Premiums are high.' : x.tone === 'cheap' ? 'Premiums are low.' : '';
  let rest = '';
  for (const s of [s1, s2, s3]) { if (!s) continue; const nx = rest ? rest + ' ' + s : s; if ((lead + ' ' + nx).length <= READ_MAX) rest = nx; }
  return { lead, rest };
}
/** The read never passes 150 characters (README §8). */
export const READ_MAX = 150;

/* ── One price scale for the lanes ────────────────────────────────────────── */

/** The lanes' scale: ±2 SD at least, and every level given (each held to ±3.5 SD so one far average does not squash
    the rest), 5% padding. fr(x) is 0 to 1 across it; ticks every $1, $2, $5, $10 or $20 by its width. */
export function priceScale(S0: number, m: number, levels: (number | null | undefined)[]): { X0: number; W: number; fr: (x: number) => number; ticks: number[] } {
  const lim = (v: number) => Math.max(atSd(S0, -3.5, m), Math.min(atSd(S0, 3.5, m), v));
  const pts = [atSd(S0, -2, m), atSd(S0, 2, m), ...levels.filter((v): v is number => v != null && Number.isFinite(v) && v > 0).map(lim)];
  const lo = Math.min(...pts), hi = Math.max(...pts), pd = (hi - lo) * 0.05 || S0 * 0.05;
  const X0 = lo - pd, W = hi - lo + 2 * pd;
  const stp = W <= 7 ? 1 : W <= 14 ? 2 : W <= 35 ? 5 : W <= 70 ? 10 : 20;
  const ticks: number[] = [];
  for (let v = Math.ceil(X0 / stp) * stp; v <= X0 + W + 1e-9; v += stp) ticks.push(+v.toFixed(2));
  return { X0, W, fr: (x: number) => (x - X0) / W, ticks };
}

/** The strike step the design uses when the chain's own is not to hand: $0.50 under $50, $1 under $200, else $5. */
export const stepOf = (S0: number): number => (S0 < 50 ? 0.5 : S0 < 200 ? 1 : 5);
/** Weekly, monthly (the third Friday, or the Thursday before it on a holiday) or earnings, for the expiry line. */
export const expiryKind = (ex: string, earnings: boolean): string => {
  if (earnings) return 'earnings';
  const d = new Date(ex + 'T12:00:00Z'), wd = d.getUTCDay(), dd = d.getUTCDate();
  return (wd === 5 && dd >= 15 && dd <= 21) || (wd === 4 && dd >= 14 && dd <= 20) ? 'monthly' : 'weekly';
};
/** D1: Intelligence opens on this Friday's expiry, or the first one after it. */
export const openExpiry = (exps: { ex: string }[], friday: string): string | null =>
  (exps.find((e) => e.ex === friday) ?? exps.find((e) => e.ex >= friday) ?? exps[0])?.ex ?? null;
