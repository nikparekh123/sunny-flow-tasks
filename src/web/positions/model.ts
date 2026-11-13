// One name of a book on the Positions page (README "2 · Positions page"), on the real book.
//
// The maths runs on the server (Nik, 6 Nov 2026): sunny-positions sends every leg's P&L, delta, theta and vega on a
// price-by-date grid (book-engine.ts positionsGrid), and this file only adds up the legs that are switched on and reads
// between two grid prices, exactly as the phone's PositionsModel does (ios-app/Sunnyfi/Sunny/Brief/Sample/
// PositionsModel.swift). Two things the grid cannot hold are priced here with the same book engine, on the same
// inputs the server priced (Home's brief_inputs, the clock moved on to the grid's pricing time):
//   - a What if trade (a leg the book does not hold), as the phone may;
//   - a date the grid has no row for: "today" on the weekend, when the grid's first stop is Monday.
//
// P&L is "from today" (the design's plf): what each leg is worth at that price and date, less what it is worth now.
// No em dashes in any words this file writes.
import { NameBook, type Div, type Kind, type Leg } from '../../../supabase/functions/_shared/book-engine.ts';
import { count, money } from '../lib/format';
import { ny } from '../lib/clock';

export type Ty = 'S' | 'C' | 'P';
export interface StopW { tt: number; short: string; phrase: string; long: string; friday: boolean }
export interface GridLegW {
  k: string; kind: Kind; ty: Ty; K: number; q: number; ex: string; days: number; label: string;
  earned: number; value: number; pl: number[][]; d: number[][]; th: number[][]; vg: number[][]; pl0?: number[];
}
export interface WallW { k: number; gex: number }
export interface ChainW { ex: string; label: string; kind: string; days: number; trading: number; flip: number | null; c: WallW | null; f: WallW | null; a: WallW | null }
export interface GridW {
  t: string; S0: number; P0: number; iv: number; sd: number; X0: number; X1: number; S: number[]; stops: StopW[]; legs: GridLegW[];
  turnsShort: (number | null)[]; fridayStop: number; walls: ChainW[]; tech: { sma20: number | null; hi: number | null; lo: number | null } | null;
  built_at: string; priced_at?: string | null;
}
export interface InputName { t: string; S0: number; P0: number; iv: number; legs: Leg[]; divs: Div[]; otm?: { K: number; ex: string; days: number; label: string } | null; noIv?: boolean }
export interface Inputs { built_at: string; r: number; names: InputName[] }

/** A What if trade (README State: side, type, strike, expiry, count, on). `ex` is the ISO expiry. `src` 'sd': the SD
    calculator's sale (one at a time, handoff 2026-11-11-sd-whatif-totals 1.10); `pr`: opened at this premium a share
    instead of the model price; `iv`: priced on this IV (the calculator's sale: the chain's IV at that strike and
    expiry) instead of the name's. */
export interface Trade { id: number; side: 's' | 'b'; ty: 'c' | 'p'; K: number; ex: string; n: number; on: boolean; src?: 'sd'; pr?: number; iv?: number }

/** A leg as the page lists it: lb and ct strike first ("36 call · Oct 30"; a trade's lb "Sell 10 × 36.5 calls · Nov 6"), qt ("Sold 72"). */
export interface PLeg {
  k: string; kind: Kind; ty: Ty; K: number; q: number; ex: string; exL: string; group: 's' | 'l';
  lb: string; ct: string; qt: string;
  at: number | null;   // sold at / paid, per share (shares: the average cost)
  now: number;         // marked now, per share (shares: today's price)
  value: number;       // what it is worth now, $ (signed: a sold leg is a liability)
  trade?: number;      // the What if trade's id
}
/** A date on the chart: days on from the grid's pricing time, and its grid row (null: priced here). */
export interface DPt { tt: number; row: number | null }
/** One By date segment. */
/** `key` is the stop's long label ("Fri Nov 13 close"): one per stop, and the same across rebuilds. */
export interface Seg { i: number; key: string; label: string; tt: number; row: number; iso: string; friday: boolean; held: boolean }

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd }; };
const dayDiff = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);
/** A strike: 36, 42.5 (the server's fk). */
export const fk = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));
/** The server's expLabel: "Nov 13", or "Sep ’27" more than 183 days out. */
export const expLabel = (iso: string, daysOut: number) => { const x = ymd(iso); return daysOut <= 183 ? `${MON[x.m - 1]} ${x.d}` : `${MON[x.m - 1]} ’${String(x.y).slice(2)}`; };
/** The instant of an expiry's close: 4:00 PM New York on that date. */
export const nyClose = (iso: string) => {
  const x = ymd(iso);
  let t = Date.UTC(x.y, x.m - 1, x.d, 21, 0);   // 4:00 PM EST
  const h = +new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: '2-digit', hour12: false }).format(new Date(t)) % 24;
  if (h === 17) t -= 3_600_000;                  // EDT
  return t;
};
/** Strike first (Nik 12 Nov 2026: never "OTM calls", "Insurance puts" or "LEAPS"): "36 call · Oct 30". */
const ctOf = (ty: Ty, K: number, exL: string) => (ty === 'S' ? 'Shares' : `${fk(K)}\u00a0${ty === 'C' ? 'call' : 'put'} · ${exL.replace(/ /g, '\u00a0')}`);
const qtOf = (ty: Ty, q: number) => (ty === 'S' ? count(q) : (q < 0 ? 'Sold ' : 'Bought ') + count(q));
/** "Sell 10 × 36.5 calls · Nov 6" (handoff 2026-11-13 §3.6). */
export const tradeName = (u: { side: 's' | 'b'; ty: 'c' | 'p'; K: number; n: number }, exL: string) =>
  `${u.side === 's' ? 'Sell' : 'Buy'} ${count(u.n)} × ${fk(u.K)} ${u.ty === 'c' ? 'calls' : 'puts'} · ${exL}`;
export const updn = (v: number) => (v >= 0 ? 'Up ' : 'Down ') + money(v);

/** Sold first after the shares, as the design lists them: shares, then sold (by expiry, calls before puts, strike),
    then the long options (by expiry, strike). */
const order = (a: PLeg, b: PLeg) => {
  const r = (l: PLeg) => (l.ty === 'S' ? 0 : l.group === 's' ? 1 : 2);
  return r(a) - r(b) || a.ex.localeCompare(b.ex) || (a.ty === 'P' ? 1 : 0) - (b.ty === 'P' ? 1 : 0) || a.K - b.K;
};

export class PosModel {
  t: string; S0: number; P0: number; iv: number; S: number[]; stops: StopW[]; fridayStop: number;
  walls: ChainW[]; tech: GridW['tech']; turnsShort: (number | null)[];
  legs: PLeg[];
  pricedAt: number;
  /** "today" on the chart: the grid's first stop when it is now, else priced here. */
  today: DPt;
  r: number; divs: Div[];
  /** The IV a What if trade is priced on: the name's (the chain's IV at the strike nearest the price). */
  tradeIv: number;
  /** Each leg's grid, and the same legs in the engine (for dates the grid has no row for). */
  readonly g = new Map<string, GridLegW>();
  local: NameBook | null = null;
  readonly localLeg = new Map<string, Leg>();

  constructor(w: GridW, inp: Inputs | null) {
    this.t = w.t; this.S0 = w.S0; this.P0 = w.P0; this.iv = w.iv; this.S = w.S; this.stops = w.stops;
    this.fridayStop = Math.min(Math.max(0, w.fridayStop), Math.max(0, w.stops.length - 1));
    this.walls = w.walls ?? []; this.tech = w.tech ?? null; this.turnsShort = w.turnsShort ?? [];
    this.pricedAt = Date.parse(w.priced_at || w.built_at) || Date.now();
    const iname = inp?.names.find((n) => n.t === w.t) ?? null;
    const gone = inp ? (this.pricedAt - Date.parse(inp.built_at)) / 864e5 : 0;
    this.r = inp?.r ?? 0.04;
    this.divs = (iname?.divs ?? []).map((d) => ({ ...d, days: d.days - gone }));
    const ivs = (iname?.legs ?? []).filter((l) => l.ty !== 'S' && l.iv > 0.03).map((l) => l.iv);
    this.tradeIv = w.iv > 0 ? w.iv : ivs.length ? ivs.reduce((a, b) => a + b, 0) / ivs.length : 1e-4;
    const inLeg = new Map((iname?.legs ?? []).map((l) => [l.k, l]));
    if (iname) {
      const legs = iname.legs.map((l) => (l.ty === 'S' ? l : { ...l, days: l.days - gone }));
      this.local = new NameBook({ t: w.t, S0: w.S0, P0: w.P0, iv: w.iv, legs, divs: this.divs, r: this.r, noIv: !!iname.noIv });
      for (const l of legs) this.localLeg.set(l.k, l);
    }
    this.legs = w.legs.map((l) => {
      this.g.set(l.k, l);
      const src = inLeg.get(l.k);
      const exL = l.ty === 'S' ? '' : (l.label.split(', ').pop() ?? '');
      const now = l.ty === 'S' ? w.S0 : src?.now ?? (l.q ? Math.abs(l.value / (l.q * 100)) : 0);
      const at = l.ty === 'S' ? l.K : src?.at ?? null;
      return {
        k: l.k, kind: l.kind, ty: l.ty, K: l.K, q: l.q, ex: l.ex, exL, group: l.q < 0 && l.ty !== 'S' ? 's' : 'l',
        lb: ctOf(l.ty, l.K, exL), ct: ctOf(l.ty, l.K, exL), qt: qtOf(l.ty, l.q), at, now, value: l.value,
      } as PLeg;
    }).sort(order);
    this.today = w.stops[0] && Math.abs(w.stops[0].tt) < 1e-6 ? { tt: 0, row: 0 } : { tt: 0, row: null };
  }

  /** The NY date a grid date falls on. */
  isoAt(tt: number) { return ny(new Date(this.pricedAt + tt * 864e5)).date; }
  /** Calendar days from the grid's pricing time to an expiry's close. */
  daysTo(iso: string) { return (nyClose(iso) - this.pricedAt) / 864e5; }
  /** Whole days from the pricing day to an expiry (the Expiry select's "· 10 days"). */
  wholeDays(iso: string) { return dayDiff(this.isoAt(0), iso); }

  /** The widest zoom step the grid's prices cover (the phone's widestZoom): ±50% on the wide grid, else ±12%. */
  widest(zooms: number[]) {
    const lo = this.S[0], hi = this.S[this.S.length - 1];
    const r = Math.min(this.S0 - lo, hi - this.S0) / this.S0 + 1e-4;
    let k = 0; zooms.forEach((z, i) => { if (z / 100 <= r) k = i; });
    return k;
  }
  /** The top of the turns-short search: +50%, or as far as the grid reaches. */
  get topPct() { return Math.round(Math.min(50, (this.S[this.S.length - 1] / this.S0 - 1) * 100)); }

  /** A value between two grid prices, on the straight line between them (held at the ends). */
  at(a: number[], x: number) {
    const S = this.S, n = S.length;
    if (!a || a.length !== n || n < 2) return a?.[0] ?? 0;
    if (x <= S[0]) return a[0];
    if (x >= S[n - 1]) return a[n - 1];
    let i = 0, j = n - 1;
    while (j - i > 1) { const k = (i + j) >> 1; if (S[k] <= x) i = k; else j = k; }
    const w = S[j] > S[i] ? (x - S[i]) / (S[j] - S[i]) : 0;
    return a[i] + (a[j] - a[i]) * w;
  }

  /** The By date segments (README: "Today · Wed · Thu · Fri Oct 30 · Nov 6 ..."): every stop to this Friday, then
      each later expiry Friday the grid reaches; at most nine. */
  segments(): Seg[] {
    const held = new Set(this.legs.filter((l) => l.ty !== 'S').map((l) => l.ex));
    const out: Seg[] = [];
    this.stops.forEach((s, i) => {
      if (i > this.fridayStop && !s.friday) return;
      const wd = s.long.split(' ')[0];
      const label = i === this.fridayStop && s.friday && !/^(Today|Mon|Tue|Wed|Thu|Fri)$/.test(s.short) ? `${wd} ${s.short}` : s.short;
      const iso = this.isoAt(s.tt);
      out.push({ i, key: s.long, label, tt: s.tt, row: i, iso, friday: s.friday, held: s.friday && held.has(iso) });
    });
    return out.slice(0, 9);
  }
  /** The wall chain a date reads: the first expiry on or after it. */
  chainFor(iso: string) { return this.walls.find((c) => c.ex >= iso) ?? null; }
}

/** The legs that are on, priced: the book's from the grid (or the engine for a date the grid has no row for), the
    What if trades with the engine. */
export class Pricer {
  m: PosModel;
  trades: PLeg[];
  private tnb: NameBook | null = null;
  private tleg = new Map<string, Leg>();
  /** A trade opened at its own premium (`pr`): its model value now less what it was opened at, added to its P&L. */
  private edge = new Map<string, number>();
  constructor(m: PosModel, trades: Trade[]) {
    this.m = m;
    const legs: Leg[] = trades.map((u) => this.engineLeg(u));
    if (legs.length) this.tnb = new NameBook({ t: m.t, S0: m.S0, P0: m.P0, iv: m.tradeIv, legs, divs: m.divs, r: m.r });
    legs.forEach((l, i) => {
      this.tleg.set(l.k, l);
      const p = trades[i].pr;
      if (this.tnb && p != null && p >= 0) this.edge.set(l.k, this.tnb.val(l, m.S0, 0) - l.q * 100 * p);
    });
    this.trades = trades.map((u, i) => this.pleg(u, legs[i]));
  }
  private engineLeg(u: Trade): Leg {
    const q = u.side === 's' ? -u.n : u.n, ty: Ty = u.ty === 'c' ? 'C' : 'P';
    const kind: Kind = u.side === 's' ? (u.ty === 'c' ? 'sc' : 'sp') : u.ty === 'p' ? 'ins' : 'otm';
    return { k: 'u' + u.id, kind, ty, K: u.K, q, days: this.m.daysTo(u.ex), iv: u.iv && u.iv > 0.03 ? u.iv : this.m.tradeIv, ex: u.ex, label: '' };
  }
  private pleg(u: Trade, l: Leg): PLeg {
    const exL = expLabel(u.ex, this.m.wholeDays(u.ex));
    // Opened at `pr` when it carries one (the SD calculator's sale, at the premium it was priced at), else the model.
    const mk = this.edge.has(l.k) ? u.pr! : this.tnb ? this.tnb.val(l, this.m.S0, 0) / (l.q * 100) : 0;
    return { k: l.k, kind: l.kind, ty: l.ty, K: l.K, q: l.q, ex: u.ex, exL, group: l.q < 0 ? 's' : 'l', lb: tradeName(u, exL),
      ct: ctOf(l.ty, l.K, exL), qt: qtOf(l.ty, l.q), at: mk, now: mk, value: l.q * 100 * mk, trade: u.id };
  }
  /** A trade not yet added: its price a share, delta and cash today (the summary line). */
  quote(u: Omit<Trade, 'id' | 'on'>) {
    const l = this.engineLeg({ ...u, id: -1, on: true });
    const nb = new NameBook({ t: this.m.t, S0: this.m.S0, P0: this.m.P0, iv: this.m.tradeIv, legs: [l], divs: this.m.divs, r: this.m.r });
    const per = nb.val(l, this.m.S0, 0) / (l.q * 100);
    return { per, delta: nb.dl(l, this.m.S0, 0), cash: -l.q * 100 * per };
  }

  private gl(l: PLeg) { return this.m.g.get(l.k); }
  private ll(l: PLeg) { return this.m.localLeg.get(l.k); }
  private lnb() { return this.m.local; }

  plL(l: PLeg, x: number, d: DPt): number {
    if (l.ty === 'S') return l.q * (x - this.m.S0);
    if (l.trade != null) { const e = this.tleg.get(l.k); return e && this.tnb ? this.tnb.lpl(e, x, d.tt) + (this.edge.get(l.k) ?? 0) : 0; }
    const g = this.gl(l);
    if (g && d.row != null) return this.m.at(g.pl[d.row], x);
    if (g?.pl0 && d.tt === 0) return this.m.at(g.pl0, x);
    const e = this.ll(l), nb = this.lnb();
    if (e && nb) return nb.lpl(e, x, d.tt);
    return g ? this.m.at(g.pl[0], x) : 0;
  }
  dL(l: PLeg, x: number, d: DPt): number {
    if (l.ty === 'S') return l.q;
    if (l.trade != null) { const e = this.tleg.get(l.k); return e && this.tnb ? this.tnb.dl(e, x, d.tt) : 0; }
    const g = this.gl(l);
    if (g && d.row != null) return this.m.at(g.d[d.row], x);
    const e = this.ll(l), nb = this.lnb();
    if (e && nb) return nb.dl(e, x, d.tt);
    if (g?.pl0 && d.tt === 0) return (this.m.at(g.pl0, x * 1.002) - this.m.at(g.pl0, x * 0.998)) / (x * 0.004);
    return g ? this.m.at(g.d[0], x) : 0;
  }
  thL(l: PLeg, x: number, d: DPt): number {
    if (l.ty === 'S') return 0;
    const e = l.trade != null ? this.tleg.get(l.k) : this.ll(l), nb = l.trade != null ? this.tnb : this.lnb();
    if (l.trade == null) { const g = this.gl(l); if (g && d.row != null) return this.m.at(g.th[d.row], x); }
    if (e && nb) return (nb.val(e, x, d.tt + 0.05) - nb.val(e, x, d.tt)) / 0.05;
    const g = this.gl(l); return g ? this.m.at(g.th[0], x) : 0;
  }
  vgL(l: PLeg, x: number, d: DPt): number {
    if (l.ty === 'S') return 0;
    const e = l.trade != null ? this.tleg.get(l.k) : this.ll(l), nb = l.trade != null ? this.tnb : this.lnb();
    if (l.trade == null) { const g = this.gl(l); if (g && d.row != null) return this.m.at(g.vg[d.row], x); }
    if (e && nb) return nb.val(e, x, d.tt, 0.01) - nb.val(e, x, d.tt);
    const g = this.gl(l); return g ? this.m.at(g.vg[0], x) : 0;
  }

  pl(set: PLeg[], x: number, d: DPt) { let s = 0; for (const l of set) s += this.plL(l, x, d); return s; }
  delta(set: PLeg[], x: number, d: DPt) { let s = 0; for (const l of set) s += this.dL(l, x, d); return s; }
  /** Delta, gamma (±0.2%, the slope of the summed delta), theta ($ a day) and vega ($ a vol point): the phone's. */
  greeks(set: PLeg[], x: number, d: DPt) {
    let th = 0, vg = 0;
    for (const l of set) { th += this.thL(l, x, d); vg += this.vgL(l, x, d); }
    return { d: this.delta(set, x, d), g: (this.delta(set, x * 1.002, d) - this.delta(set, x * 0.998, d)) / (x * 0.004), th, vg };
  }
  /** TURNS SHORT: the first price above today where net delta drops below zero on that date (today's price when it
      already has). The book as it is on a grid date: the server's price to the cent, the one Home says. With changes:
      read off the grid, to the cent, as far as it reaches (at most +50%). */
  shortAt(set: PLeg[], d: DPt, asIs: boolean): number | null {
    const m = this.m;
    if (asIs && d.row != null && d.row < m.turnsShort.length) {
      const v = m.turnsShort[d.row];
      return v != null && v <= m.S0 * 1.5 + 1e-9 ? v : null;
    }
    const top = Math.min(m.S0 * 1.5, m.S[m.S.length - 1]);
    let px = m.S0, pd = this.delta(set, px, d);
    if (pd < 0) return m.S0;
    for (const x of m.S) {
      if (x <= m.S0 || x > top + 1e-9) continue;
      const dx = this.delta(set, x, d);
      if (dx < 0) return Math.ceil((px + (x - px) * pd / (pd - dx)) * 100 - 1e-9) / 100;
      px = x; pd = dx;
    }
    return null;
  }
}
