/**
 * Payoff planner math — ported from the design handoff's logic class.
 *
 * The README is explicit that this block is "correct and load-bearing" and
 * should be lifted near-verbatim. It has been: the only change is that the
 * class getters became a `Ctx` argument so the functions are pure and
 * testable.
 *
 * ⚠ ONE DELIBERATE DEPARTURE. The design values every leg by MODEL (Black-
 * Scholes against the entry mark). Nik's ruling, 2026-09-08: "unrealized is
 * what the current value is, not anything else." So `unrealized()` anchors to
 * the BROKER mark at elapsed = 0 and lets the model take over only as the date
 * is scrubbed forward. Every leg carries its own IV from the broker's greeks,
 * so the model at spot should sit close to the mark and the hand-off is small
 * — but where they differ, the mark wins on day zero, because that is the
 * number the Options page also shows.
 */

export type LegKind = 'stock' | 'call' | 'put';

export interface Leg {
  id: string;
  kind: LegKind;
  /** Signed: negative is short. Contracts for options, shares for stock. */
  qty: number;
  strike: number;
  expiry: string;            // ISO, '' for stock
  premium: number;           // entry mark per share
  mark: number | null;       // broker's current mark per share, null if unpriced
  iv: number | null;         // per-leg vol from the broker, null = use book vol
  basis?: number;            // stock only
  history: [string, string, number][];
  /** Draft/plan bookkeeping. */
  plan?: boolean;
  replaces?: string;
}

export interface Ctx {
  spot: number;
  iv: number;        // the book vol (ATM), used where a leg carries none
  today: Date;
  ivMult: number;    // 1 = as quoted
}

/* ── distributions ──────────────────────────────────────────────────── */
export const erf = (x: number): number => {
  const s = x < 0 ? -1 : 1; x = Math.abs(x);
  const t = 1 / (1 + 0.3275911 * x);
  return s * (1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x));
};
export const NRM = (x: number): number => 0.5 * (1 + erf(x / Math.SQRT2));
export const phi = (x: number): number => Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math.PI);

/* ── Black-Scholes ──────────────────────────────────────────────────── */
export function bs(S: number, K: number, T: number, sig: number, isCall: boolean): number {
  if (T <= 0 || sig <= 0) return Math.max(0, isCall ? S - K : K - S);
  const v = sig * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * v * v) / v, d2 = d1 - v;
  return isCall ? S * NRM(d1) - K * NRM(d2) : K * NRM(-d2) - S * NRM(-d1);
}
export function bsDelta(S: number, K: number, T: number, sig: number, isCall: boolean): number {
  if (T <= 0) return isCall ? (S > K ? 1 : 0) : (S < K ? -1 : 0);
  const v = sig * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * v * v) / v;
  return isCall ? NRM(d1) : NRM(d1) - 1;
}
/** Per one vol point. */
export function bsVega(S: number, K: number, T: number, sig: number): number {
  if (T <= 0) return 0;
  const v = sig * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * v * v) / v;
  return S * phi(d1) * Math.sqrt(T) / 100;
}
/** Per day. */
export function bsTheta(S: number, K: number, T: number, sig: number): number {
  if (T <= 0) return 0;
  const v = sig * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * v * v) / v;
  return -S * phi(d1) * sig / (2 * Math.sqrt(T)) / 365;
}

/* ── dates ──────────────────────────────────────────────────────────── */
export const parseISO = (iso: string): Date => {
  const p = iso.split('-').map(Number);
  return new Date(p[0], p[1] - 1, p[2]);
};
export const dteOf = (iso: string, today: Date): number =>
  Math.round((parseISO(iso).getTime() - today.getTime()) / 864e5);

/* ── per-leg pricing ────────────────────────────────────────────────── */
export const sigOf = (leg: Leg, c: Ctx): number => (leg.iv != null && leg.iv > 0 ? leg.iv : c.iv) * c.ivMult;

/** The entry mark: what the leg cost or paid, per share. */
export const entryOf = (leg: Leg, c: Ctx): number => {
  if (leg.kind === 'stock') return leg.basis != null ? leg.basis : c.spot;
  return leg.premium;
};
const T_of = (leg: Leg, elapsed: number, c: Ctx) =>
  Math.max(0, dteOf(leg.expiry, c.today) - elapsed) / 365;

/**
 * ⚠ EVERY LEG IS CALIBRATED TO ITS BROKER MARK. Nik, 2026-09-09, on the hover
 * card: "the numbers are wrong". They were. At NKE's spot the chart read −$28
 * while the page's own Unrealized read −$6,095, because the header uses the
 * broker's marks and the curve was repricing everything from scratch.
 *
 * The gap was almost entirely the LEAP: this Black-Scholes carries NO INTEREST
 * RATE, which on a 499-day $30 call is worth about $1.60 a share — 60 contracts
 * of it, $6,720. Adding a rate would fix that one omission and leave every
 * other difference from the vendor's model (dividends, borrow, skew) in place.
 *
 * So instead the model is corrected to the mark: `adj` is what the mark says
 * the model is wrong by TODAY, and it is carried across the curve. It decays
 * with the leg's remaining time, because a model error in an option's value is
 * an error in its TIME value — at expiry the payoff is intrinsic and there is
 * nothing left to be wrong about. At elapsed 0 the correction is exact, so the
 * curve now passes through the broker's number at spot by construction.
 */
const adjOf = (leg: Leg, c: Ctx): number => {
  if (leg.kind === 'stock' || leg.mark == null) return 0;
  const T0 = Math.max(0, dteOf(leg.expiry, c.today)) / 365;
  if (T0 <= 0) return 0;
  return leg.mark - bs(c.spot, leg.strike, T0, sigOf(leg, c), leg.kind === 'call');
};

export function legValue(leg: Leg, p: number, elapsed: number, c: Ctx): number {
  const T0 = Math.max(0, dteOf(leg.expiry, c.today)) / 365;
  const T = T_of(leg, elapsed, c);
  const model = bs(p, leg.strike, T, sigOf(leg, c), leg.kind === 'call');
  return model + (T0 > 0 ? adjOf(leg, c) * (T / T0) : 0);
}

export function legPL(leg: Leg, p: number, elapsed: number, c: Ctx): number {
  if (leg.kind === 'stock') return leg.qty * (p - entryOf(leg, c));
  return leg.qty * 100 * (legValue(leg, p, elapsed, c) - entryOf(leg, c));
}
export const total = (p: number, elapsed: number, legs: Leg[], c: Ctx): number =>
  legs.reduce((s, l) => s + legPL(l, p, elapsed, c), 0);

export function legDelta(leg: Leg, elapsed: number, c: Ctx): number {
  if (leg.kind === 'stock') return leg.qty;
  return leg.qty * 100 * bsDelta(c.spot, leg.strike, T_of(leg, elapsed, c), sigOf(leg, c), leg.kind === 'call');
}
export function liveMark(leg: Leg, elapsed: number, c: Ctx): number {
  if (leg.kind === 'stock') return c.spot;
  /* Calibrated, so a leg is never priced one way on the card and another on
     the curve. At elapsed 0 this returns the broker's mark exactly. */
  return legValue(leg, c.spot, elapsed, c);
}
export function intrinsic(leg: Leg, c: Ctx): number {
  if (leg.kind === 'stock') return c.spot;
  return Math.max(0, leg.kind === 'call' ? c.spot - leg.strike : leg.strike - c.spot);
}

/**
 * ⚠ THE BROKER MARK ON DAY ZERO. This is the one place the design's model is
 * overridden, per Nik. A leg with no mark yet falls back to the model — the
 * same "unpriced" handling the option cards learned the hard way.
 */
export function unrealized(legs: Leg[], elapsed: number, c: Ctx): number {
  return legs.reduce((s, l) => {
    if (elapsed === 0 && l.kind !== 'stock' && l.mark != null) {
      return s + l.qty * 100 * (l.mark - entryOf(l, c));
    }
    return s + legPL(l, c.spot, elapsed, c);
  }, 0);
}

/** What closing the option legs would pay (+) or cost (−), and the extrinsic left. */
export function premiumNow(legs: Leg[], elapsed: number, c: Ctx): { close: number; extrinsic: number } {
  let close = 0, extr = 0;
  legs.filter((l) => l.kind !== 'stock').forEach((l) => {
    const m = elapsed === 0 && l.mark != null ? l.mark : liveMark(l, elapsed, c);
    close += l.qty * 100 * m;
    extr += l.qty * 100 * (m - intrinsic(l, c));
  });
  return { close, extrinsic: extr };
}

const MON3 = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const parseDay = (s: string): number => {
  const p = String(s).split(' ');
  return new Date(+p[2], MON3.indexOf(p[1]), +p[0]).getTime();
};

/** Lifetime cash on the book's option legs, plus the trailing-7-day window. */
export function premiumHistory(bookLegs: Leg[], planned: Leg[], c: Ctx) {
  const cut = c.today.getTime() - 7 * 864e5;
  let got = 0, paid = 0, week = 0, last: number | null = null;
  bookLegs.filter((l) => l.kind !== 'stock').forEach((l) => {
    (l.history || []).forEach((h) => {
      const cash = h[2], t = parseDay(h[0]);
      if (cash > 0) {
        got += cash;
        if (t >= cut) week += cash;
        if (last == null || t > last) last = t;
      } else paid += -cash;
    });
  });
  const planAdd = planned.filter((l) => l.kind !== 'stock' && l.qty < 0)
    .reduce((s, l) => s + -l.qty * 100 * entryOf(l, c), 0);
  return { got, paid, week, last, planAdd };
}

export function netGreeks(legs: Leg[], elapsed: number, c: Ctx): { delta: number; theta: number; vega: number } {
  let d = 0, th = 0, ve = 0;
  legs.forEach((l) => {
    d += legDelta(l, elapsed, c);
    if (l.kind === 'stock') return;
    const T = T_of(l, elapsed, c);
    th += l.qty * 100 * bsTheta(c.spot, l.strike, T, sigOf(l, c));
    ve += l.qty * 100 * bsVega(c.spot, l.strike, T, sigOf(l, c));
  });
  return { delta: d, theta: th, vega: ve };
}

/** Moneyness is a WORD, and on a short leg it is also a warning. */
export function moneyness(leg: Leg, c: Ctx): { word: string; risk: 'assign' | 'near' | null } {
  if (leg.kind === 'stock') return { word: '', risk: null };
  const S = c.spot, K = leg.strike, dte = dteOf(leg.expiry, c.today);
  const inPct = leg.kind === 'call' ? (S - K) / K : (K - S) / K;
  let word: string;
  if (inPct > 0.10) word = 'Deep in the money';
  else if (inPct > 0.015) word = 'In the money';
  else if (inPct > -0.015) word = 'At the money';
  else if (inPct > -0.10) word = 'Out of the money';
  else word = 'Far out of the money';
  let risk: 'assign' | 'near' | null = null;
  if (leg.qty < 0) {
    if (inPct > 0) risk = dte <= 21 ? null : 'assign';
    else if (inPct > -0.02) risk = 'near';
  }
  return { word, risk };
}

/* ── probability ────────────────────────────────────────────────────── */
export function density(p: number, dte: number, c: Ctx): number {
  const sig = c.iv * c.ivMult;
  const s = sig * Math.sqrt(Math.max(dte, 1) / 365), z = (Math.log(p / c.spot) + 0.5 * s * s) / s;
  return Math.exp(-0.5 * z * z) / (p * s * Math.sqrt(2 * Math.PI));
}
export function chance(legs: Leg[], dte: number, c: Ctx): number {
  const lo = c.spot * 0.1, hi = c.spot * 5, n = 1400, st = (hi - lo) / n;
  let hit = 0, all = 0;
  for (let i = 0; i < n; i++) {
    const p = lo + (i + 0.5) * st, w = density(p, dte, c) * st;
    all += w;
    if (total(p, dte, legs, c) > 0) hit += w;
  }
  return all ? hit / all : 0;
}
export function bounds(legs: Leg[], dte: number, c: Ctx) {
  const lo = c.spot * 0.05, hi = c.spot * 4, n = 900, st = (hi - lo) / n;
  let mn = Infinity, mx = -Infinity, prev: number | null = null;
  const bes: number[] = [];
  for (let i = 0; i <= n; i++) {
    const p = lo + i * st, v = total(p, dte, legs, c);
    if (v < mn) mn = v; if (v > mx) mx = v;
    if (prev !== null && ((prev < 0 && v >= 0) || (prev > 0 && v <= 0))) bes.push(p - st * v / (v - prev));
    prev = v;
  }
  const edge = total(hi, dte, legs, c) - total(hi - st, dte, legs, c);
  return { min: mn, max: mx, bes, lossUnbounded: edge < -1, gainUnbounded: edge > 1 };
}

/* ── axis + labels ──────────────────────────────────────────────────── */
export const niceStep = (raw: number): number => {
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const n = raw / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
};
export const strikeStep = (spot: number): number => spot < 100 ? 2.5 : spot < 300 ? 5 : spot < 800 ? 10 : 25;
export const basisStep = (spot: number): number => spot < 50 ? 0.5 : spot < 300 ? 1 : 5;

export interface LabelItem {
  kind: 'lab' | 'assign';
  anchor: 'left' | 'mid';
  l: number;      // x in plot space
  w: number;      // measured width
  name: string;
  val: string;
  nameInk?: string;
  valInk?: string;
  t?: number;     // assigned row top
}
/** Three rows, filled nearest-the-plot first; anything that will not fit is dropped. */
export function place(items: LabelItem[], rows: number[] = [55, 29, 3]): LabelItem[] {
  const taken: { a: number; b: number }[][] = rows.map(() => []);
  const out: LabelItem[] = [];
  items.forEach((it) => {
    const a = it.l - (it.anchor === 'mid' ? it.w / 2 : 0), b = a + it.w;
    let r = 0;
    for (; r < rows.length; r++) if (!taken[r].some((o) => a < o.b + 10 && o.a < b + 10)) break;
    if (r >= rows.length) return;
    it.t = rows[r];
    taken[r].push({ a, b });
    out.push(it);
  });
  return out;
}
/** Labels within 34px of each other collapse into one `N LEVELS` range label. */
export function cluster(labs: LabelItem[]): LabelItem[] {
  const groups: { items: LabelItem[]; lastL: number }[] = [];
  labs.slice().sort((a, b) => a.l - b.l).forEach((it) => {
    const g = groups[groups.length - 1];
    if (g && it.l - g.lastL < 34) { g.items.push(it); g.lastL = it.l; }
    else groups.push({ items: [it], lastL: it.l });
  });
  return groups.map((g) => {
    if (g.items.length === 1) return g.items[0];
    const vals = g.items.map((x) => parseFloat(x.val.replace(/[^0-9.]/g, ''))).filter((v) => !isNaN(v));
    const name = g.items.length + ' LEVELS';
    const val = Math.min(...vals).toFixed(2) + '–' + Math.max(...vals).toFixed(2);
    return { kind: 'lab', anchor: 'mid', l: g.items.reduce((s, x) => s + x.l, 0) / g.items.length,
      w: Math.max(name.length, val.length) * 6.4, name, val };
  });
}

/* ── formatters (exact — they are part of the design) ───────────────── */
export const money = (v: number): string => (v < 0 ? '−$' : '$') + Math.abs(Math.round(v)).toLocaleString('en-US');
export const money2 = (v: number): string => (v < 0 ? '−$' : '$') + Math.abs(v).toFixed(2);
export const priceLab = (v: number): string => '$' + (v >= 500 ? Math.round(v).toLocaleString('en-US') : v.toFixed(2));
export const priceShort = (v: number): string => priceLab(v).replace('.00', '');
export const signed = (v: number): string => (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(Math.round(v)).toLocaleString('en-US');
export const signed1 = (v: number): string => (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(v).toFixed(1);
export const fmtK = (v: number): string => v >= 1000 ? (v / 1000).toFixed(1) + 'k' : String(v);
export const fmtExp = (iso: string, today: Date): string => {
  const d = parseISO(iso);
  return MON3[d.getMonth()] + ' ' + d.getDate() + (d.getFullYear() !== today.getFullYear() ? ' ’' + String(d.getFullYear()).slice(2) : '');
};
export const fmtStamp = (d: Date): string => {
  const days = ['SUN','MON','TUE','WED','THU','FRI','SAT'];
  const h = d.getHours(), m = String(d.getMinutes()).padStart(2, '0');
  const hh = String(((h + 11) % 12) + 1).padStart(2, '0');
  return `${days[d.getDay()]} · ${MON3[d.getMonth()].toUpperCase()} ${String(d.getDate()).padStart(2, '0')} · ${hh}:${m} ${h < 12 ? 'AM' : 'PM'} PT`;
};
export const fmtLongDate = (d: Date): string =>
  d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
