/**
 * The SD calculator's engine (handoff 2026-11-11-sd-calculator, SunnySD.dc.html sd135 and card136), on real data.
 * For one name and one expiry: the 1 SD move (m = IV × √T), the strike at each SD step snapped to a listed strike,
 * its premium, breakeven and chance of finishing in the money, the 5-year "won" rate, and the suggested call and put
 * (README 1.5 rules, in order) with the signals that moved them. sunny-sd gathers the inputs; the app and the web only
 * draw what this returns and work out the chance of profit for the strikes picked.
 *
 * Nik's answers (11 Nov 2026): puts ATM to 1 SD (D2, not the brief's 1.5); defaults and thresholds fixed here (D4);
 * strikes snap to the chain's own listed strikes (A2); after the close the premiums are the closing mid (A3, the chain
 * snapshot's last quotes); the 5-year IV is the saved IV, else HV20 × the name's IV/HV ratio (A1).
 * No em dashes in any words here (Nik).
 */

/** The design's normal CDF (Abramowitz-Stegun 26.2.17), kept so the numbers match the prototype's test case. */
export const N = (x: number): number => {
  const t = 1 / (1 + 0.2316419 * Math.abs(x)), d = 0.3989422804014327 * Math.exp(-x * x / 2);
  const q = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x > 0 ? 1 - q : q;
};
export const bs = (S: number, K: number, T: number, r: number, q: number, s: number, put: boolean): number => {
  const v = s * Math.sqrt(T), d1 = (Math.log(S / K) + (r - q + s * s / 2) * T) / v, d2 = d1 - v;
  return put ? K * Math.exp(-r * T) * N(-d2) - S * Math.exp(-q * T) * N(-d1) : S * Math.exp(-q * T) * N(d1) - K * Math.exp(-r * T) * N(d2);
};
export const dl = (S: number, K: number, T: number, s: number, q: number, r: number, put: boolean): number => {
  if (!(T > 0) || !(s > 0)) return put ? (S < K ? -1 : 0) : (S > K ? 1 : 0);
  const d1 = (Math.log(S / K) + (r - q + s * s / 2) * T) / (s * Math.sqrt(T));
  return Math.exp(-q * T) * (put ? N(d1) - 1 : N(d1));
};

/** The rules' thresholds (README 1.5; Nik D4: fixed in code for now). pHi 1.0 (Nik D2: puts ATM to 1 SD). */
export const CFG = { c0: 0.5, cLo: 0.5, cHi: 1.25, p0: 1, pLo: 0, pHi: 1, zDn: -1, zDn2: -0.5, zUp: 0.5, zUp2: 1,
  rkHi: 70, rkLo: 20, rtHi: 1.3, rtLo: 1, rsiHi: 70, rsiLo: 30, sr: 0.25, nudge: 0.25, spr: 0.1, oi: 100 };
/** The Every SD table's steps. */
export const KS = [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

export interface Quote { mid: number; bid: number | null; ask: number | null; oi: number | null; est: boolean; liq: boolean }
export interface Expiry {
  ex: string; label: string; long: string;
  /** Trading days after today through the expiry, and calendar days. */
  td: number; cd: number;
  /** Years: td / 252, or on the expiry day the hours left / (6.5 × 252). */
  T: number;
  /** The expiry's at-the-money IV (the SD math uses each expiry's own). */
  iv: number;
  /** Listed strikes, low to high. */
  strikes: number[];
  quote: (K: number, put: boolean) => Quote;
  /** Earnings before this expiry. */
  earnB: boolean;
}
export interface Leg { K: number; n: number; ex: string; at: number | null; iv: number; days: number }
export interface Name {
  t: string; S: number; S5: number; iv5: number; iv30: number; hv20: number; rank: number; ratio: number;
  rsi: number; sup: number; res: number; r: number; q: number;
  shares: number; soldCalls: Leg[]; soldPuts: Leg[]; longCalls: Leg[]; longPuts: Leg[];
}
export type Fx = [kind: 'c' | 'p' | 'b' | 'x' | 'n', text: string];
export interface Row { k: number; K: number; x: number; kA: number; pr: number; be: number; itm: number; est: boolean; liq: boolean }

export const f1 = (x: number) => x.toFixed(1), f2 = (x: number) => x.toFixed(2);
/** A strike as the design writes it: "40", "42.5", "40.85". */
export const fk = (x: number) => (x % 1 ? (Math.round(x * 100) % 10 ? x.toFixed(2) : x.toFixed(1)) : String(x));
export const sdl = (k: number) => (k === 0 ? 'ATM' : (k % 1 ? String(k) : k.toFixed(1)) + ' SD');
/** A percentage, one decimal, two under 0.1%; never a sign. */
export const pc = (x: number) => { const a = Math.abs(x) * 100; return (a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%'; };
export const dir = (x: number) => (x >= 0 ? '↑ ' : '↓ ') + pc(x);

/** The nearest listed strike (A2), or the price itself when the chain has none. */
export function snapTo(strikes: number[], K: number): number {
  if (!strikes.length) return +K.toFixed(2);
  let best = strikes[0];
  for (const s of strikes) if (Math.abs(s - K) < Math.abs(best - K)) best = s;
  return best;
}

/** One strike's row: snapped strike, premium (the mid, or Black-Scholes marked ≈), breakeven, in the money. */
export function row(c: Name, e: Expiry, k: number, put: boolean, K0?: number): Row {
  const m = e.iv * Math.sqrt(e.T), S = c.S;
  const K = K0 != null ? K0 : snapTo(e.strikes, S * Math.exp((put ? -k : k) * m)), x = Math.log(K / S), kA = (put ? -x : x) / m;
  const qt = e.quote(K, put), pr = qt.mid, be = put ? K - pr : K + pr;
  return { k, K, x, kA, pr, be, itm: N(-kA), est: qt.est, liq: qt.liq };
}

export interface Calc {
  m: number; z: number; rich: boolean; cheap: boolean; ernB: boolean;
  kc: number; kp: number; mvC: boolean; mvP: boolean; capC: boolean; capP: boolean;
  C: Row; P: Row; fx: { wk: Fx[]; iv: Fx[]; rsi: Fx[]; er: Fx[]; res: Fx[]; sup: Fx[] };
}

/** The suggestion (README 1.5): the week, rich or cheap, RSI, earnings, clamp, then support and resistance. */
export function calc(c: Name, e: Expiry, o: { c0?: number; p0?: number; atm?: boolean } = {}): Calc {
  const G = CFG, S = c.S, m = e.iv * Math.sqrt(e.T), atm = o.atm !== false;
  const c0 = o.c0 ?? G.c0, p0 = o.p0 ?? G.p0, ernB = e.earnB;
  const z = Math.log(S / c.S5) / (c.iv5 * Math.sqrt(5 / 252));
  let kc = c0, kp = p0;
  const fx: Calc['fx'] = { wk: [], iv: [], rsi: [], er: [], res: [], sup: [] };
  // 1. The week. In an earnings window nothing moves closer.
  if (z <= G.zDn) { kc += 0.5; if (!ernB) kp = atm ? 0 : 0.25; }
  else if (z <= G.zDn2) { kc += 0.25; if (!ernB) kp -= 0.25; }
  else if (z >= G.zUp2) kp += 0.5;
  else if (z >= G.zUp) kp += 0.25;
  if (z <= G.zDn) fx.wk.push(['c', 'Call 0.5 SD wider'], ernB ? ['n', 'Put kept: earnings'] : ['p', 'Put to ' + (atm ? 'ATM' : '0.25 SD')]);
  else if (z <= G.zDn2) fx.wk.push(['c', 'Call 0.25 SD wider'], ernB ? ['n', 'Put kept: earnings'] : ['p', 'Put 0.25 SD closer']);
  else if (z >= G.zUp2) fx.wk.push(['p', 'Put 0.5 SD wider']);
  else if (z >= G.zUp) fx.wk.push(['p', 'Put 0.25 SD wider']);
  if (z <= G.zDn && c.soldCalls.length) fx.wk.push(['x', 'Buy back the ' + [...new Set(c.soldCalls.map((x) => fk(x.K)))].join(' and ') + ' calls, no roll down']);
  // 2. Rich or cheap, on the 30-day IV. Rich wins when both read true.
  const rich = c.rank >= G.rkHi || c.ratio >= G.rtHi, cheap = !rich && (c.rank <= G.rkLo || c.ratio <= G.rtLo);
  if (rich && !ernB) { kc -= 0.25; kp -= 0.25; } else if (cheap) { kc += 0.25; kp += 0.25; }
  if (rich) fx.iv.push(ernB ? ['n', 'Skipped: earnings'] : ['b', 'Both 0.25 SD closer']); else if (cheap) fx.iv.push(['b', 'Both 0.25 SD wider']);
  // 3. RSI only widens.
  const ob = c.rsi >= G.rsiHi, os = c.rsi <= G.rsiLo;
  if (ob) { kp += 0.25; fx.rsi.push(['p', 'Put 0.25 SD wider']); }
  if (os) { kc += 0.25; fx.rsi.push(['c', 'Call 0.25 SD wider']); }
  // 4. Earnings before expiry.
  if (ernB) { kc += 0.5; kp += 0.5; fx.er.push(['b', 'Both 0.5 SD wider'], ['n', 'Nothing moves closer']); }
  // 5. Clamp and round to 0.25.
  const cl = (v: number, lo: number, hi: number) => Math.round(Math.min(hi, Math.max(lo, v)) * 4) / 4;
  const kc5 = cl(kc, G.cLo, G.cHi), kp5 = cl(kp, G.pLo, G.pHi);
  // 6. Support and resistance: within 0.25 SD of the strike, out to the first listed strike past it, 0.25 SD at most.
  let Kc = snapTo(e.strikes, S * Math.exp(kc5 * m)), Kp = snapTo(e.strikes, S * Math.exp(-kp5 * m)), mvC = false, mvP = false;
  if (c.res > Kc && Math.log(c.res / Kc) / m <= G.sr) {
    const K = e.strikes.find((s) => s > c.res + 1e-9);
    if (K != null && Math.log(K / Kc) / m <= G.nudge) { Kc = K; mvC = true; }
  }
  if (c.sup < Kp && Math.log(Kp / c.sup) / m <= G.sr) {
    const K = [...e.strikes].reverse().find((s) => s < c.sup - 1e-9);
    if (K != null && Math.log(Kp / K) / m <= G.nudge) { Kp = K; mvP = true; }
  }
  if (mvC) fx.res.push(['c', 'Call out to ' + fk(Kc)]);
  if (mvP) fx.sup.push(['p', 'Put out to ' + fk(Kp)]);
  return { m, z, rich, cheap, ernB, kc: kc5, kp: kp5, mvC, mvP, capC: kc5 !== kc, capP: kp5 !== kp,
    C: row(c, e, kc5, false, Kc), P: row(c, e, kp5, true, Kp), fx };
}

/** The 5-year "won" rates for one expiry length (README 1.7): every start day, a strike k SD out set with that day's
    IV, held the same number of trading days; won = it expired out of the money. `iv` holds each day's IV (saved, or
    HV20 scaled: Nik A1). */
export function won(closes: number[], iv: (number | null)[], n: number): { n: number; call: (k: number) => number; put: (k: number) => number } {
  const z: number[] = [], h = Math.max(1, n);
  for (let d = 20; d + h < closes.length; d++) {
    const v = iv[d];
    if (!(v && v > 0) || !(closes[d] > 0) || !(closes[d + h] > 0)) continue;
    z.push(Math.log(closes[d + h] / closes[d]) / (v * Math.sqrt(h / 252)));
  }
  z.sort((a, b) => a - b);
  const below = (k: number) => { let lo = 0, hi = z.length; while (lo < hi) { const md = (lo + hi) >> 1; if (z[md] < k) lo = md + 1; else hi = md; } return lo; };
  return { n: z.length, call: (k) => (z.length ? below(k) / z.length : NaN), put: (k) => (z.length ? 1 - below(-k) / z.length : NaN) };
}

/** Cover (README 1.6): shares first, one per 100; then long calls (not LEAPS) that expire on or after the short call,
    lowest strike first; the rest are naked. */
export function cover(c: Name): { n: number; covered: number; capped: number; naked: number } {
  let sh = Math.floor(c.shares / 100), covered = 0, capped = 0, naked = 0;
  const used = c.longCalls.map(() => 0);
  for (const s of c.soldCalls) {
    let left = s.n;
    const a = Math.min(left, sh); covered += a; sh -= a; left -= a;
    c.longCalls.map((l, i) => ({ l, i })).filter((x) => x.l.ex >= s.ex).sort((x, y) => x.l.K - y.l.K).forEach(({ l, i }) => {
      const b = Math.min(left, l.n - used[i]);
      if (b > 0) { used[i] += b; capped += b; left -= b; }
    });
    naked += left;
  }
  return { n: c.soldCalls.reduce((a, x) => a + x.n, 0), covered, capped, naked };
}

/** Net delta in shares today: shares plus every option leg's delta × 100. */
export function netDelta(c: Name, leaps: Leg[]): number {
  const S = c.S, D = (l: Leg, put: boolean) => dl(S, l.K, Math.max(l.days, 0.01) / 365, l.iv || c.iv30, c.q, c.r, put);
  let d = c.shares;
  for (const l of [...c.longCalls, ...leaps]) d += l.n * 100 * D(l, false);
  for (const l of c.longPuts) d += l.n * 100 * D(l, true);
  for (const l of c.soldCalls) d -= l.n * 100 * D(l, false);
  for (const l of c.soldPuts) d -= l.n * 100 * D(l, true);
  return d;
}

/* ── SD on your positions (handoff 2026-11-11-sd-on-positions, round 139a) ──────────────────────────────────────────
   Three short lines for every option leg held: how far its strike is from today in dollars, the same distance in SD by
   the leg's own expiry, and the odds in your favour. Nik, 11 Nov 2026: the leg's own IV (from its price); the Every leg
   table gets a new column; orange ("needs a look", sold legs only) when in the money, within 0.5 SD, or under 70% to
   expire worthless. Prices and odds, not the book's dollars: they stay visible with privacy on. */

/** Years to a leg's expiry the way the calculator counts them: trading days after today through the expiry (weekends
    and `closed` days left out) over 252; on the expiry day, the hours left / (6.5 × 252). `mins`: New York minutes now. */
export function tradingYears(today: string, ex: string, closed: Set<string>, mins: number): number {
  let n = 0;
  const d = new Date(today + 'T12:00:00Z'), end = Date.parse(ex + 'T12:00:00Z');
  for (d.setUTCDate(d.getUTCDate() + 1); d.getTime() <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    const w = d.getUTCDay(), s = d.toISOString().slice(0, 10);
    if (w !== 0 && w !== 6 && !closed.has(s)) n++;
  }
  return n > 0 ? n / 252 : Math.max(0.25, (16 * 60 - mins) / 60) / (6.5 * 252);
}

export interface LegSd { itm: boolean; away: number; sd: number; pItm: number; odds: number; look: boolean; l1: string; l2: string; l3: string }
/** One leg's three lines. `exLabel` is the leg's expiry as its row writes it (`Oct 30`, `Sep ’27`). */
export function legSd(o: { S: number; K: number; put: boolean; sold: boolean; iv: number; T: number; exLabel: string }): LegSd {
  const m = Math.max(1e-6, o.iv * Math.sqrt(Math.max(o.T, 1e-6))), x = Math.log(o.K / o.S);
  const itm = o.put ? o.K > o.S : o.K < o.S;
  const pItm = o.put ? N(x / m) : N(-x / m), sd = Math.abs(x) / m, odds = o.sold ? 1 - pItm : pItm;
  const look = o.sold && (itm || sd < 0.5 || odds < 0.7);
  return { itm, away: Math.abs(o.K - o.S), sd, pItm, odds, look,
    l1: itm ? 'In the money' : `$${f2(Math.abs(o.K - o.S))} away`,
    l2: itm ? '' : `${sd.toFixed(2)} SD by ${o.exLabel}`,
    l3: o.sold ? `${pc(odds)} expires worthless` : `${pc(pItm)} ends in the money` };
}

/** What you hold (Nik 11 Nov): the sold calls and sold puts of one expiry as a pair. Only one side can end in the
    money, so all the premium you took in cushions it. At an expiry price X the pair makes
    sum(n x premium) - sum over calls n x max(0, X - K) - sum over puts n x max(0, K - X); the breakevens are where
    that crosses zero, below and above its peak. `m` is the expiry's IV x sqrt(T). Null when a leg has no sale price
    or the pair never makes money. dn is null when the puts' premium covers a fall to zero. */
export interface Held { up: number; dn: number | null; tot: number; sdUp: number; sdDn: number | null; cop: number }
export function heldPair(calls: Leg[], puts: Leg[], S: number, m: number): Held | null {
  if (!calls.length || !puts.length || [...calls, ...puts].some((l) => l.at == null || !(l.n > 0))) return null;
  const T = [...calls, ...puts].reduce((a, l) => a + l.n * (l.at as number), 0);
  const pl = (X: number) => T - calls.reduce((a, l) => a + l.n * Math.max(0, X - l.K), 0) - puts.reduce((a, l) => a + l.n * Math.max(0, l.K - X), 0);
  const top = [...calls, ...puts].map((l) => l.K).reduce((b, K) => (pl(K) > pl(b) ? K : b));
  if (!(pl(top) > 0)) return null;
  const root = (lo: number, hi: number, up: boolean) => {
    for (let i = 0; i < 200; i++) { const md = (lo + hi) / 2; if ((pl(md) > 0) === up) lo = md; else hi = md; }
    return (lo + hi) / 2;
  };
  let hi = top * 2; while (pl(hi) > 0) hi *= 2;
  const up = root(top, hi, true), dn = pl(0) > 0 ? null : root(0, top, false);
  const mm = Math.max(1e-6, m);
  const sdUp = Math.log(up / S) / mm, sdDn = dn ? Math.log(S / dn) / mm : null;
  const cop = N(Math.log(up / S) / mm) - (dn ? N(Math.log(dn / S) / mm) : 0);
  return { up, dn, tot: T * 100, sdUp, sdDn, cop };
}
