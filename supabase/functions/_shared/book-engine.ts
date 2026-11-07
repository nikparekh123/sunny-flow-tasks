// ── The book engine (handoff 6 Nov 2026, README 9.2 and 12) ─────────────────
// ONE engine for every screen that talks about a book: Home (Your position, To
// decide), Positions (one name: P&L and delta by price and date, turns short, the
// fixes) and Overview. Nik, 6 Nov 2026: the maths runs on the server; the phone
// only adds the numbers up and draws them. So this file works out every leg's
// value and Greeks on a price-by-date grid, and the phone sums the legs that are
// switched on.
//
// Pure: no I/O and no clock. Time is in CALENDAR DAYS FROM NOW (the build). A
// leg's `days` is calendar days from now to its expiry close; `tt` is how far on
// the valuation is (0 = now). The caller turns dates into days.
//
// Pricing (answer C5, 6 Nov 2026): Black-Scholes on each option's own implied
// volatility (Theta), a 4% rate, dividends counted as cash paid before expiry
// (escrowed: the present value of each dividend between the valuation and the
// expiry comes off the spot). With r = 0, no dividends and one IV per name it is
// the prototype's maths exactly (SunnyBriefs rv46, SunnyPositions m45), and the
// tests hold it to the design's numbers that way.
//
// No em dashes in any words this file writes (Nik).

export type Ty = 'S' | 'C' | 'P';
/** shares · LEAPS · OTM calls (the code key "Hedge call") · insurance puts · sold calls · sold puts. */
export type Kind = 'shares' | 'leaps' | 'otm' | 'ins' | 'sc' | 'sp';

export interface Leg {
  k: string;          // stable key for the phone ("sh", "s0", "l2")
  kind: Kind;
  ty: Ty;
  K: number;          // strike; for shares, the average cost
  q: number;          // signed: shares held, or contracts (+ bought, - sold)
  days: number;       // calendar days from now to the expiry close (shares: 0)
  iv: number;         // this option's implied volatility (shares: 0)
  ex: string;         // expiry as an ISO date ('' for shares)
  label: string;      // "Calls 36 ×72, Oct 30"
  at?: number;        // sold at / paid, per share
  now?: number;       // mark now, per share
}
/** A dividend still to go ex: calendar days from now to the ex-date, cash per share. */
export interface Div { days: number; amt: number }

export interface NameIn {
  t: string;
  S0: number;         // price now
  P0?: number;        // previous close
  iv: number;         // the name's IV for its priced move (the chain's IV at the strike nearest the price)
  legs: Leg[];
  divs?: Div[];
  r?: number;         // rate (4% in the app; 0 reproduces the prototype)
  t0?: number;        // days into today the "now" values sit at (the prototype's moment offset; 0 in the app)
}

// ── Black-Scholes, as the prototype writes it (Abramowitz-Stegun 7.1.26) ────
const erf = (x: number) => {
  const g = Math.sign(x), a = Math.abs(x), q = 1 / (1 + 0.3275911 * a);
  return g * (1 - (((((1.061405429 * q - 1.453152027) * q) + 1.421413741) * q - 0.284496736) * q + 0.254829592) * q * Math.exp(-a * a));
};
export const N = (x: number) => 0.5 * (1 + erf(x / Math.SQRT2));

/** Value per share. T in years; dpv = present value of dividends paid before expiry. */
export function bsValue(S: number, K: number, T: number, v: number, put: boolean, r = 0, dpv = 0): number {
  if (T <= 0) return put ? Math.max(K - S, 0) : Math.max(S - K, 0);
  const Sx = Math.max(S - dpv, 1e-9), df = Math.exp(-r * T), sq = v * Math.sqrt(T);
  const d1 = (Math.log(Sx / (K * df)) + v * v / 2 * T) / sq, c = Sx * N(d1) - K * df * N(d1 - sq);
  return put ? c - Sx + K * df : c;
}
/** Delta per share, with the prototype's floor of .02 days so an expiring leg never divides by zero. */
export function bsDelta(S: number, K: number, T: number, v: number, put: boolean, r = 0, dpv = 0): number {
  const TT = Math.max(T, 0.02 / 365), Sx = Math.max(S - dpv, 1e-9), df = Math.exp(-r * TT);
  const d1 = (Math.log(Sx / (K * df)) + v * v / 2 * TT) / (v * Math.sqrt(TT));
  return N(d1) - (put ? 1 : 0);
}

export interface Opt { off?: Set<string>; extra?: Leg[]; earned?: boolean }

/** One name's book: every leg, valued at any price S and any time tt days on. */
export class NameBook {
  t: string; S0: number; P0: number; iv: number; legs: Leg[]; divs: Div[]; r: number; t0: number;
  constructor(x: NameIn) {
    this.t = x.t; this.S0 = x.S0; this.P0 = x.P0 ?? x.S0; this.iv = x.iv; this.legs = x.legs;
    this.divs = x.divs ?? []; this.r = x.r ?? 0; this.t0 = x.t0 ?? 0;
  }
  /** The weekly priced move in %: IV × √(5/252) (Nik: one weekly SD all week). */
  get sd(): number { return (this.iv || 0.3) * Math.sqrt(5 / 252) * 100; }
  private T(l: Leg, tt: number) { return Math.max(0, l.days - tt) / 365; }
  private dpv(l: Leg, tt: number) {
    let s = 0;
    for (const d of this.divs) if (d.days > tt && d.days <= l.days) s += d.amt * Math.exp(-this.r * (d.days - tt) / 365);
    return s;
  }
  /** What a leg is worth at S, tt days on (dv bumps its IV, for vega). */
  val(l: Leg, S: number, tt: number, dv = 0): number {
    if (l.ty === 'S') return l.q * S;
    return l.q * 100 * bsValue(S, l.K, this.T(l, tt), l.iv + dv, l.ty === 'P', this.r, this.dpv(l, tt));
  }
  /** A leg's delta in shares. */
  dl(l: Leg, S: number, tt: number): number {
    if (l.ty === 'S') return l.q;
    return l.q * 100 * bsDelta(S, l.K, this.T(l, tt), l.iv, l.ty === 'P', this.r, this.dpv(l, tt));
  }
  /** A leg's P&L from now: its value at (S, tt) less its value now. */
  lpl(l: Leg, S: number, tt: number): number { return this.val(l, S, tt) - this.val(l, this.S0, this.t0); }
  /** Premium already earned on a sold leg: sold at less what it is marked at now. */
  earned(l: Leg): number { return l.q < 0 && l.at != null && l.now != null ? -l.q * 100 * (l.at - l.now) : 0; }
  private on(o?: Opt): Leg[] { return this.legs.filter((l) => !o?.off?.has(l.k)).concat(o?.extra ?? []); }
  pl(S: number, tt: number, o?: Opt): number {
    let p = 0;
    for (const l of this.on(o)) { p += this.lpl(l, S, tt); if (o?.earned) p += this.earned(l); }
    return p;
  }
  delta(S: number, tt: number, o?: Opt): number { return this.on(o).reduce((a, l) => a + this.dl(l, S, tt), 0); }
  /** Shares plus the calls bought: what the sold legs are measured against for "thin". */
  longDelta(S: number, tt: number, o?: Opt): number {
    return this.on(o).filter((l) => l.q > 0 && l.ty !== 'P').reduce((a, l) => a + this.dl(l, S, tt), 0);
  }
  /** P&L from now, net delta and long delta if the name moves m % and it is tt days on (rv46 `at`). */
  at(m: number, tt: number): { p: number; n: number; lg: number } {
    const S = this.S0 * (1 + m / 100);
    let p = 0, n = 0, lg = 0;
    for (const l of this.legs) {
      p += this.lpl(l, S, tt);
      const x = this.dl(l, S, tt); n += x;
      if (l.q > 0 && l.ty !== 'P') lg += x;
    }
    return { p, n, lg };
  }
  /** Delta, gamma (±.2%), theta per day (P&L over .05 day) and vega (+1 vol point), as m45 `gk`. */
  greeks(S: number, tt: number, o?: Opt): { d: number; g: number; th: number; vg: number } {
    const on = this.on(o);
    return {
      d: this.delta(S, tt, o),
      g: (this.delta(S * 1.002, tt, o) - this.delta(S * 0.998, tt, o)) / (S * 0.004),
      th: (this.pl(S, tt + 0.05, o) - this.pl(S, tt, o)) / 0.05,
      vg: on.reduce((a, l) => l.ty === 'S' ? a : a + this.val(l, S, tt, 0.01) - this.val(l, S, tt), 0),
    };
  }
  /** TURNS SHORT (README 9.2, invariant 1): the first cent above today's price where net delta drops
   *  below zero on the date viewed, searched up to `hiS`. Home, To decide and the Positions chart all ask
   *  this one function, so they say the same price to the cent. `now` = already short at today's price. */
  turnsShort(tt: number, hiS: number, o?: Opt): { price: number; now: boolean } | null {
    const f = (S: number) => this.delta(S, tt, o);
    if (f(this.S0) < 0) return { price: this.S0, now: true };
    const step = this.S0 * 0.0005;
    let a = this.S0;
    for (let S = this.S0 + step; S <= hiS + 1e-9; S += step) {
      if (f(S) < 0) {
        let lo = a, hi = S;
        while (hi - lo > 0.001) { const mid = (lo + hi) / 2; if (f(mid) < 0) hi = mid; else lo = mid; }
        let c = Math.ceil(lo * 100 - 1e-9) / 100;
        while (f(c) >= 0 && c < hi + 0.02) c = Math.round(c * 100 + 1) / 100;
        return { price: c, now: false };
      }
      a = S;
    }
    return null;
  }
}

// ── Words and money (README 11.5) ───────────────────────────────────────────
export const fK = (x: number) => { const a = Math.abs(x); return a >= 1e4 ? '$' + Math.round(a / 1000) + 'K' : a >= 1000 ? '$' + (a / 1000).toFixed(1) + 'K' : '$' + Math.round(a); };
export const f$ = (x: number) => '$' + Math.round(Math.abs(x)).toLocaleString('en-US');
export const fn = (x: number) => Math.round(Math.abs(x)).toLocaleString('en-US');
export const f1 = (x: number) => (Math.round(x * 10) / 10).toFixed(1);
export const f2 = (x: number) => x.toFixed(2);

export interface Span { t: string; b?: boolean; c?: string }
const sp = (t: string, b = false, c?: string): Span => (c ? { t, b, c } : b ? { t, b } : { t });

// ── Your position (block 30, rv46) ──────────────────────────────────────────
export interface PositionClock {
  th: number;            // days on to the Friday close the card is about
  weekend: boolean;      // this week's calls have ended and next week's are not sold yet
  nextFriday: boolean;   // the Friday is next week's (the weekend)
  sub: string;           // the subtitle for the moment
}
export interface CoverIn { shares: number; covered: number }
export interface AssignIn { t: string; exLabel: string }

export interface PositionRow {
  id: string; name: string; line: string; lineColor: string; right: string; rightColor: string; at: string; st: number;
  fp: number | null; n: number; lg: number; frac: number; sd: number;
}
export interface YourPosition {
  subtitle: string; sentence: Span[]; grid: number[]; friday: number[]; today: number[]; shortAt: number | null;
  stats: { v: string; l: string; c: string }[]; cover: string; assign: string | null; count: string; countColor: string;
  rows: PositionRow[]; aria: string;
  // raw numbers, for the invariant checks and Overview
  dollarDelta: number; up5: number; flat: number; dn5: number; coverPct: number; nShort: number; nThin: number;
}

/** The whole book by Friday's close if every name moves the same %, the sentence, the three numbers, the
 *  cover line, the early-assignment line and the By name rows. `name(t)` gives the company name. */
export function yourPosition(names: NameBook[], clk: PositionClock, name: (t: string) => string,
                             cover: CoverIn, assign: AssignIn[]): YourPosition {
  const { th, weekend: wk } = clk;
  const t0 = names[0]?.t0 ?? 0;
  const M: number[] = []; for (let m = -10; m <= 10.001; m += 0.25) M.push(+m.toFixed(2));
  const bk = (m: number, tt: number) => names.reduce((a, x) => { const r = x.at(m, tt); return { p: a.p + r.p, n: a.n + r.n, d$: a.d$ + r.n * x.S0 * (1 + m / 100) / 100 }; }, { p: 0, n: 0, d$: 0 });
  const F = M.map((m) => bk(m, th)), Nw = M.map((m) => bk(m, t0));
  const fi = M.findIndex((m, i) => m > 0 && F[i].n < 0), fm = fi >= 0 ? M[fi] : null, now = bk(0, t0);
  const fri = clk.nextFriday ? 'next Friday' : 'Friday';

  const rows: PositionRow[] = names.map((x) => {
    const r = x.at(x.sd, th), thin = r.n >= 0 && r.n < 0.25 * r.lg, short = r.n < 0;
    const ts = x.turnsShort(th, x.S0 * (1 + x.sd * 3 / 100));
    const fp = ts ? ts.price : null, st = short ? 2 : thin ? 1 : 0;
    return {
      id: x.t, name: name(x.t), st, fp, n: r.n, lg: r.lg, frac: r.lg ? r.n / r.lg : 1, sd: x.sd,
      /* Nik, 7 Nov 2026: "short above $X" read as "you start losing above $X", which is not true. Say where the
         P&L peaks instead; the right side keeps the delta. */
      line: fp != null ? (ts!.now ? 'Already past its best by ' + fri : 'Makes the most at $' + f2(fp) + ' by ' + fri) : thin ? 'Thin by Friday, still gains as it rises' : 'Keeps making more past ↑' + f1(x.sd * 3) + '%',
      lineColor: fp != null ? (short ? 'red' : 'orange') : 'secondary',
      right: short ? 'Short ' + fn(r.n) + ' Δ' : thin ? 'Thin' : 'Long ' + fn(r.n) + ' Δ',
      rightColor: short ? 'red' : thin ? 'orange' : 'ink', at: 'at ↑' + f1(x.sd) + '%',
    };
  }).sort((a, b) => b.st - a.st || a.frac - b.frac);

  const nS = rows.filter((r) => r.st === 2).length, nT = rows.filter((r) => r.st === 1).length, first = rows.find((r) => r.st > 0);
  const story: Span[] = wk
    ? [sp('This week’s calls ended Friday, so you are '), sp('long only', true), sp(' until Monday’s sales: a 1% rise makes you '), sp(fK(now.d$), true, 'green'), sp('. Selling again caps how much a rise can make.')]
    : [sp('Long now: a 1% rise makes you '), sp(fK(now.d$), true, 'green'), sp('. ')].concat(fm != null
      ? [sp('Your book makes the most if the market rises '), sp(f1(fm) + '%', true, 'orange'), sp(' by ' + fri + (first ? '. ' + first.name + ' gets there first.' : '.'))]
      : [sp('Your book keeps making more even if the market rises 10% by ' + fri)].concat(first
        ? [sp(', but '), sp(first.name, true, first.st === 2 ? 'red' : 'orange'), sp(first.st === 2 && first.fp != null ? ' makes the most at $' + f2(first.fp) + '.' : ' runs thin.')]
        : [sp('.')]));

  const i0 = M.indexOf(0), pv = F[i0].p, up5 = F[M.indexOf(5)].p, dn5 = F[M.indexOf(-5)].p;
  const col = (v: number) => (v < 0 ? 'red' : 'green');
  const coverPct = Math.round(cover.covered / Math.max(1, cover.shares) * 100);
  return {
    subtitle: clk.sub, sentence: story, grid: M, friday: F.map((r) => Math.round(r.p)), today: Nw.map((r) => Math.round(r.p)), shortAt: fm,
    stats: [{ v: fK(up5), l: 'if up 5%', c: col(up5) }, { v: fK(pv), l: clk.nextFriday ? 'flat to next Fri' : 'flat to Friday', c: col(pv) }, { v: fK(dn5), l: 'if down 5%', c: col(dn5) }],
    cover: cover.shares > 0 ? 'Insurance puts cover ' + fn(cover.covered) + ' of your ' + fn(cover.shares) + ' shares, ' + coverPct + '%. Shares have no floor below that.' : '',
    assign: assign.length ? 'Ex-dividend this week: ' + assign.map((a) => name(a.t) + ' ' + a.exLabel).join(', ') + '. Calls in the money with less time value than the dividend can be assigned the day before.' : null,
    count: nS || nT ? [nS ? nS + (nS === 1 ? ' past its best' : ' past their best') : '', nT ? nT + ' thin' : ''].filter(Boolean).join(', ') + ' at a priced move' : 'Every name long at a priced move',
    countColor: nS ? 'red' : nT ? 'orange' : 'secondary', rows,
    aria: 'Your position, P&L by ' + fri + ' if the market moves 10% down to 10% up. ' + (fm != null ? 'Makes the most at a ' + f1(fm) + '% rise.' : 'Keeps making more all the way up.'),
    dollarDelta: now.d$, up5, flat: pv, dn5, coverPct, nShort: nS, nThin: nT,
  };
}

// ── Positions: one name on a price-by-date grid (block 31, m45) ─────────────
/** A date-slider stop: days on, the short label, the phrase, the long label, and whether it is an expiry Friday. */
export interface Stop { tt: number; short: string; phrase: string; long: string; friday: boolean }

export interface GridLeg {
  k: string; kind: Kind; ty: Ty; K: number; q: number; ex: string; days: number; label: string;
  earned: number;              // premium already earned (sold legs), added when the leg is on
  value: number;               // what it is worth now
  pl: number[][];              // [stop][price] P&L from now, $
  pl0?: number[];              // [price] P&L now, when the first stop is not now (the chart's dashed Today line)
  d: number[][];               // [stop][price] delta, shares
  th: number[][];              // [stop][price] theta, $ a day
  vg: number[][];              // [stop][price] vega, $ a vol point
}
export interface PositionsGrid {
  t: string; S0: number; P0: number; iv: number; sd: number; X0: number; X1: number;
  S: number[];                 // the price grid
  stops: Stop[];
  legs: GridLeg[];
  fix: { otm: { K: number; ex: string; days: number; label: string; cost: number; pl: number[][]; d: number[][] } | null };
  turnsShort: (number | null)[]; // per stop, every leg on (the phone recomputes from the sums when a leg is off)
}

const r0 = (x: number) => Math.round(x);
const r1 = (x: number) => Math.round(x * 10) / 10;

/** Every leg's P&L, delta, theta and vega on the chart's price grid (today's price ±12%) at every stop.
 *  The phone adds the legs that are on; gamma is the slope of the summed delta between grid points. */
export function positionsGrid(nb: NameBook, stops: Stop[], otm: { K: number; ex: string; days: number; label: string } | null, nPts = 101): PositionsGrid {
  const X0 = nb.S0 * 0.88, X1 = nb.S0 * 1.12, S: number[] = [];
  for (let i = 0; i < nPts; i++) S.push(+(X0 + (X1 - X0) * i / (nPts - 1)).toFixed(4));
  const grid = (l: Leg, f: (l: Leg, s: number, tt: number) => number, rd: (x: number) => number) => stops.map((st) => S.map((s) => rd(f(l, s, st.tt))));
  const legs: GridLeg[] = nb.legs.map((l) => ({
    k: l.k, kind: l.kind, ty: l.ty, K: l.K, q: l.q, ex: l.ex, days: +l.days.toFixed(3), label: l.label,
    earned: r0(nb.earned(l)), value: r0(l.ty === 'S' ? l.q * nb.S0 : (l.now != null ? l.q * 100 * l.now : nb.val(l, nb.S0, nb.t0))),
    pl: grid(l, (x, s, tt) => nb.lpl(x, s, tt), r0),
    d: grid(l, (x, s, tt) => nb.dl(x, s, tt), r1),
    th: grid(l, (x, s, tt) => (nb.val(x, s, tt + 0.05) - nb.val(x, s, tt)) / 0.05, r1),
    vg: grid(l, (x, s, tt) => (x.ty === 'S' ? 0 : nb.val(x, s, tt, 0.01) - nb.val(x, s, tt)), r1),
    ...((stops[0]?.tt ?? 0) > 0 ? { pl0: S.map((s) => r0(nb.lpl(l, s, nb.t0))) } : {}),
  }));
  let fix: PositionsGrid['fix'] = { otm: null };
  if (otm) {
    const one: Leg = { k: 'fix-otm', kind: 'otm', ty: 'C', K: otm.K, q: 1, days: otm.days, iv: nb.iv, ex: otm.ex, label: otm.label };
    fix = { otm: { ...otm, cost: r0(nb.val(one, nb.S0, nb.t0)), pl: grid(one, (x, s, tt) => nb.lpl(x, s, tt), r0), d: grid(one, (x, s, tt) => nb.dl(x, s, tt), (x) => Math.round(x * 1000) / 1000) } };
  }
  return {
    t: nb.t, S0: nb.S0, P0: nb.P0, iv: nb.iv, sd: nb.S0 * nb.iv * Math.sqrt(5 / 252), X0, X1, S, stops, legs, fix,
    turnsShort: stops.map((st) => nb.turnsShort(st.tt, X1 * 1.05)?.price ?? null),
  };
}

/** The OTM call a fix buys (A5, as designed): about 7.5% out, strike on the name's step. */
export function otmStrike(S0: number): number {
  const z = S0 < 50 ? 0.5 : S0 < 200 ? 1 : 5;
  return Math.round(S0 * 1.075 / z) * z;
}

// ── One name's holdings for the totals row and the whole-name book ──────────
export interface Holdings {
  sh: [number, number]; lp: [number, number]; oc: [number, number]; ip: [number, number];   // [value, today]
  sc: [number, number]; sp: [number, number];                                                // [left to earn, kept]
  tv: { lp: number; oc: number; ip: number; sc: number; sp: number };                       // time value now
}
export function holdings(nb: NameBook): Holdings {
  const h: Holdings = { sh: [0, 0], lp: [0, 0], oc: [0, 0], ip: [0, 0], sc: [0, 0], sp: [0, 0], tv: { lp: 0, oc: 0, ip: 0, sc: 0, sp: 0 } };
  const mv = nb.S0 - nb.P0;
  for (const l of nb.legs) {
    if (l.ty === 'S') { h.sh[0] += l.q * nb.S0; h.sh[1] += l.q * mv; continue; }
    const per = l.now ?? nb.val(l, nb.S0, nb.t0) / (l.q * 100);
    const intr = l.ty === 'C' ? Math.max(0, nb.S0 - l.K) : Math.max(0, l.K - nb.S0);
    const tv = Math.abs(l.q) * 100 * Math.max(0, per - intr);
    if (l.q < 0) {
      const key = l.kind === 'sp' ? 'sp' : 'sc';
      h[key][0] += -l.q * 100 * per; h[key][1] += l.at != null ? -l.q * 100 * (l.at - per) : 0; h.tv[key] += tv;
      continue;
    }
    const key = l.kind === 'ins' ? 'ip' : l.kind === 'leaps' ? 'lp' : 'oc';
    h[key][0] += l.q * 100 * per; h[key][1] += nb.dl(l, nb.S0, nb.t0) * mv; h.tv[key] += tv;
  }
  return h;
}
