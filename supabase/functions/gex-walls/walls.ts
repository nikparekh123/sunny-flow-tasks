/*
 * walls.ts · the gamma-wall maths (22 Oct 2026), kept apart from Theta and Supabase so the tests can
 * check it on a fixed chain.
 *
 * Per contract GEX = gamma x open interest x 100 x spot² x 0.01 (dollars of delta per 1% move), calls
 * plus, puts minus (the usual convention: dealers long the calls, short the puts). Summed by strike
 * across expiries. The flip is the zero-gamma level (zeroGamma). Gamma is Black-Scholes (Theta's own gamma needs the Pro plan; Nik chose this,
 * 22 Oct 2026), at an IV solved here from each option's mid against the stock price the quotes imply:
 * Theta's own IV is solved against its underlying price, which can be from another moment. A strike's
 * call and put share one IV: the out-of-the-money side's, else the other side's, else one filled from the
 * neighbouring strikes (see buildStrikes for when that fails the run).
 */

export type Right = 'C' | 'P';
export interface Contract {
  exp: string;            // YYYY-MM-DD
  k: number;
  right: Right;
  iv: number | null;      // Theta's implied vol, null when unusable
  oi: number;             // yesterday's open interest (OPRA, ~06:30 ET)
  vol: number;            // today's volume (0 when the contract has not traded)
}
export interface Chain {
  ticker: string;
  spot: number;
  expiries: string[];     // every expiry the run expects quotes for
  contracts: Contract[];
}
export interface StrikeRow { k: number; callGex: number; putGex: number; netGex: number; oi: number; vol: number }
/** One expiry-strike as priced: what the zero-gamma level re-prices at other stock prices. */
export interface Leg { k: number; T: number; iv: number; coi: number; poi: number; exp: string }
export interface Built { rows: StrikeRow[]; warnings: string[]; filledOi: number; totalOi: number; legs: Leg[] }
export interface Walls { call: StrikeRow[]; put: StrikeRow[] }

export class IncompleteChain extends Error {
  constructor(public problems: string[]) { super(`incomplete chain: ${problems.join('; ')}`); }
}

export const MULT = 100;
const SQ2PI = Math.sqrt(2 * Math.PI);

/** Black-Scholes gamma, per share, with a continuous dividend yield q. */
export function bsGamma(S: number, K: number, T: number, sigma: number, r = 0.04, q = 0): number {
  if (!(S > 0 && K > 0 && T > 0 && sigma > 0)) return 0;
  const v = sigma * Math.sqrt(T);
  const d1 = (Math.log(S / K) + (r - q + sigma * sigma / 2) * T) / v;
  return Math.exp(-q * T) * Math.exp(-d1 * d1 / 2) / SQ2PI / (S * v);
}

const ncdf = (x: number) => 0.5 * erfc(-x / Math.SQRT2);
function erfc(x: number): number {
  // Numerical Recipes erfc, |error| < 1.2e-7.
  const z = Math.abs(x), t = 1 / (1 + 0.5 * z);
  const r = t * Math.exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806
    + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
  return x >= 0 ? r : 2 - r;
}

/** Black-Scholes price per share. */
export function bsPrice(S: number, K: number, T: number, sigma: number, call: boolean, r = 0.04, q = 0): number {
  const v = sigma * Math.sqrt(T);
  const d1 = (Math.log(S / K) + (r - q + sigma * sigma / 2) * T) / v, d2 = d1 - v;
  return call ? S * Math.exp(-q * T) * ncdf(d1) - K * Math.exp(-r * T) * ncdf(d2)
    : K * Math.exp(-r * T) * ncdf(-d2) - S * Math.exp(-q * T) * ncdf(-d1);
}

/** The vol that prices `price`, by bisection between 1% and 500%; null when the price is outside that range
    (below intrinsic, or no time value left to read). */
export function solveIv(price: number, S: number, K: number, T: number, call: boolean, r = 0.04, q = 0): number | null {
  if (!(price > 0 && S > 0 && K > 0 && T > 0)) return null;
  let lo = 0.01, hi = 5;
  if (price <= bsPrice(S, K, T, lo, call, r, q) || price >= bsPrice(S, K, T, hi, call, r, q)) return null;
  for (let i = 0; i < 80; i++) {
    const mid = (lo + hi) / 2;
    if (bsPrice(S, K, T, mid, call, r, q) > price) hi = mid; else lo = mid;
  }
  return (lo + hi) / 2;
}

/** The stock price the option quotes themselves imply: call mid - put mid + K x e^(-rT) at the strike where
    the two mids are closest (both two-sided). Theta's `underlying_price` can come from another moment
    (after the 22 Oct close it read TSLA 362.53 against quotes implying about 376). */
export function impliedSpot(pairs: { k: number; c: number; p: number }[], T: number, r = 0.04): number | null {
  const best = pairs.filter((x) => x.c > 0 && x.p > 0).sort((a, b) => Math.abs(a.c - a.p) - Math.abs(b.c - b.p))[0];
  return best ? best.c - best.p + best.k * Math.exp(-r * T) : null;
}

/** Years from `nowMs` to 4:00 PM New York on the expiry day (calendar time), at least an hour. */
export function yearsTo(exp: string, nowMs: number): number {
  const [y, m, d] = exp.split('-').map(Number);
  // New York's offset that day: 4 PM EDT is 20:00 UTC, 4 PM EST is 21:00 UTC.
  const noonUtc = new Date(Date.UTC(y, m - 1, d, 12));
  const nyHour = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hourCycle: 'h23' }).format(noonUtc));
  const closeMs = Date.UTC(y, m - 1, d, 16 + (12 - nyHour));
  return Math.max(1 / (365 * 24), (closeMs - nowMs) / (365 * 864e5));
}

/** Dollars of delta per 1% move for one contract line: calls plus, puts minus. */
export function contractGex(gamma: number, oi: number, spot: number, right: Right): number {
  return (right === 'C' ? 1 : -1) * gamma * oi * MULT * spot * spot * 0.01;
}

/** Sum GEX by strike across expiries. `gammaFn` is injectable so tests can fix gamma per strike.
    A strike with no usable IV on either side takes one from its neighbours (linear in strike, flat past
    the last quoted strike) and is counted as filled. The run fails when an expiry has no quotes, or when
    more than FILL_LIMIT of the open interest within 1 SD of spot had to be filled: that is missing data,
    not a quiet far strike (22 Oct 2026: a 2 SD rule stopped NKE over 29 contracts at a $29 put). */
export const FILL_LIMIT = 0.10;
export function buildStrikes(chain: Chain, opts: { nowMs: number; r?: number; q?: number;
  gammaFn?: (S: number, K: number, T: number, iv: number, exp: string) => number }): Built {
  const { spot } = chain;
  const g = opts.gammaFn ?? ((S, K, T, iv) => bsGamma(S, K, T, iv, opts.r ?? 0.04, opts.q ?? 0));
  const problems: string[] = [], warnings: string[] = [];
  const by = new Map<number, StrikeRow>();
  let filledOi = 0, totalOi = 0;
  const legs: Leg[] = [];
  for (const exp of chain.expiries) {
    const cs = chain.contracts.filter((c) => c.exp === exp);
    if (!cs.length) { problems.push(`${exp} returned no quotes`); continue; }
    if (!cs.some((c) => c.oi > 0)) warnings.push(`${exp} has no open interest yet`);
    const T = yearsTo(exp, opts.nowMs);
    const strikes = new Map<number, { C?: Contract; P?: Contract }>();
    for (const c of cs) { const s = strikes.get(c.k) ?? {}; s[c.right] = c; strikes.set(c.k, s); }
    const ivAt = (k: number, s: { C?: Contract; P?: Contract }) => {
      const otm = k >= spot ? s.C : s.P, itm = k >= spot ? s.P : s.C;
      return otm?.iv ?? itm?.iv ?? null;
    };
    const ks = [...strikes.keys()].sort((a, b) => a - b);
    const known = ks.map((k) => ({ k, iv: ivAt(k, strikes.get(k)!) })).filter((x): x is { k: number; iv: number } => x.iv != null);
    if (!known.length) { problems.push(`${exp} has no usable implied vol at any strike`); continue; }
    const fill = (k: number) => {
      const lo = [...known].reverse().find((x) => x.k < k), hi = known.find((x) => x.k > k);
      return lo && hi ? lo.iv + (hi.iv - lo.iv) * (k - lo.k) / (hi.k - lo.k) : (lo ?? hi)!.iv;
    };
    // 1 SD for this expiry, at the IV of the quoted strike nearest spot.
    const atm = [...known].sort((a, b) => Math.abs(a.k - spot) - Math.abs(b.k - spot))[0];
    const sd = spot * atm.iv * Math.sqrt(T);
    let nearOi = 0, filledNear = 0;
    for (const k of ks) {
      const s = strikes.get(k)!, iv0 = ivAt(k, s), iv = iv0 ?? fill(k), oi = (s.C?.oi ?? 0) + (s.P?.oi ?? 0);
      totalOi += oi;
      if (iv0 == null) filledOi += oi;
      if (Math.abs(k - spot) <= sd) { nearOi += oi; if (iv0 == null) filledNear += oi; }
      const row = by.get(k) ?? { k, callGex: 0, putGex: 0, netGex: 0, oi: 0, vol: 0 };
      row.oi += oi; row.vol += (s.C?.vol ?? 0) + (s.P?.vol ?? 0);
      const gm = g(spot, k, T, iv, exp);
      legs.push({ k, T, iv, coi: s.C?.oi ?? 0, poi: s.P?.oi ?? 0, exp });
      if (s.C) row.callGex += contractGex(gm, s.C.oi, spot, 'C');
      if (s.P) row.putGex += contractGex(gm, s.P.oi, spot, 'P');
      row.netGex = row.callGex + row.putGex;
      by.set(k, row);
    }
    if (filledNear > FILL_LIMIT * nearOi) {
      problems.push(`${exp}: ${(filledNear / nearOi * 100).toFixed(0)}% of the open interest within 1 SD of spot has no usable quote`);
    }
  }
  if (problems.length) throw new IncompleteChain(problems);
  return { rows: [...by.values()].sort((a, b) => a.k - b.k), warnings, filledOi, totalOi, legs };
}

/** Call wall: the strike above spot with the largest call GEX; put wall: below spot, most negative put GEX. Runner-up second. */
export function findWalls(rows: StrikeRow[], spot: number): Walls {
  return {
    call: rows.filter((r) => r.k > spot && r.callGex > 0).sort((a, b) => b.callGex - a.callGex).slice(0, 2),
    put: rows.filter((r) => r.k < spot && r.putGex < 0).sort((a, b) => a.putGex - b.putGex).slice(0, 2),
  };
}

/** The flip: the stock price at which the whole chain's net GEX, every contract re-priced at that price
    (same IV, same time left), crosses zero. Searched from 85% to 115% of spot in 0.25% steps, interpolated,
    the crossing nearest spot. Above it hedging leans against moves, below it with them. Replaces the spec's
    cumulative-by-strike crossing (Nik, 22 Oct 2026), which read BABA 40.69 at a $101.80 price. */
export function zeroGamma(legs: Leg[], spot: number, opts: { r?: number; q?: number;
  gammaFn?: (S: number, K: number, T: number, iv: number, exp: string) => number } = {}): number | null {
  const g = opts.gammaFn ?? ((S, K, T, iv) => bsGamma(S, K, T, iv, opts.r ?? 0.04, opts.q ?? 0));
  const net = (S: number) => legs.reduce((a, l) => a + g(S, l.k, l.T, l.iv, l.exp) * (l.coi - l.poi), 0) * MULT * S * S * 0.01;
  const xs: number[] = [];
  let pS = 0, pV = 0;
  for (let i = 0; i <= 120; i++) {
    const S = spot * (0.85 + i * 0.0025), v = net(S);
    if (i > 0 && ((pV < 0 && v >= 0) || (pV > 0 && v <= 0)) && v !== pV) xs.push(pS + (0 - pV) / (v - pV) * (S - pS));
    pS = S; pV = v;
  }
  return xs.length ? xs.sort((a, b) => Math.abs(a - spot) - Math.abs(b - spot))[0] : null;
}

/** Today's volume above half the open interest: new positions went on today. */
export const isFresh = (r: StrikeRow) => r.vol > 0.5 * r.oi;

/** The n strikes nearest spot, ascending. */
export function nearest(rows: StrikeRow[], spot: number, n = 15): StrikeRow[] {
  return [...rows].sort((a, b) => Math.abs(a.k - spot) - Math.abs(b.k - spot)).slice(0, n).sort((a, b) => a.k - b.k);
}

export interface TargetSide { k: number; wall: number | null; vs: 'on' | 'below' | 'above' | 'no wall' }
/** The strike nearest `pct`% out of the money on each side, and where it sits against that side's wall. */
export function target(rows: StrikeRow[], spot: number, pct: number, w: Walls): { call: TargetSide | null; put: TargetSide | null } {
  const pick = (want: number, side: (r: StrikeRow) => boolean) =>
    rows.filter(side).sort((a, b) => Math.abs(a.k - want) - Math.abs(b.k - want))[0]?.k ?? null;
  const vs = (k: number, wall: number | null): TargetSide['vs'] => wall == null ? 'no wall' : k === wall ? 'on' : k < wall ? 'below' : 'above';
  const ck = pick(spot * (1 + pct / 100), (r) => r.k > spot), pk = pick(spot * (1 - pct / 100), (r) => r.k < spot);
  const cw = w.call[0]?.k ?? null, pw = w.put[0]?.k ?? null;
  return { call: ck == null ? null : { k: ck, wall: cw, vs: vs(ck, cw) }, put: pk == null ? null : { k: pk, wall: pw, vs: vs(pk, pw) } };
}

// ── Text ──

/** $1.2B · $340M · $56K, with the sign. */
export function money(v: number): string {
  const a = Math.abs(v), s = v < 0 ? '-' : '+';
  if (a >= 1e9) return `${s}$${(a / 1e9).toFixed(2)}B`;
  if (a >= 1e6) return `${s}$${(a / 1e6).toFixed(1)}M`;
  if (a >= 1e3) return `${s}$${(a / 1e3).toFixed(0)}K`;
  return `${s}$${a.toFixed(0)}`;
}
const num = (k: number) => (Math.abs(k - Math.round(k)) < 1e-9 ? String(Math.round(k)) : String(+k.toFixed(2)));

export function summaryLine(day: string, ticker: string, spot: number, net: number, flip: number | null, w: Walls): string {
  const wall = (xs: StrikeRow[]) => xs.length ? num(xs[0].k) + (xs[1] ? ` (2nd ${num(xs[1].k)})` : '') : 'none';
  return `${day} ${ticker} spot ${spot.toFixed(2)} · net GEX ${money(net)} · flip ${flip == null ? 'none' : flip.toFixed(2)} · call wall ${wall(w.call)} · put wall ${wall(w.put)}`;
}

export function renderTable(rows: StrikeRow[], spot: number, w: Walls): string {
  const tag = (r: StrikeRow) => [
    w.call[0]?.k === r.k ? 'CALL WALL' : w.call[1]?.k === r.k ? 'call 2nd' : '',
    w.put[0]?.k === r.k ? 'PUT WALL' : w.put[1]?.k === r.k ? 'put 2nd' : '',
    isFresh(r) ? 'FRESH' : '',
  ].filter(Boolean).join(' ');
  const head = ['strike', 'call GEX', 'put GEX', 'net GEX', 'OI', 'volume', 'flags'];
  const lines = rows.map((r) => [num(r.k), money(r.callGex), money(r.putGex), money(r.netGex), String(r.oi), String(r.vol), tag(r)]);
  const wid = head.map((h, i) => Math.max(h.length, ...lines.map((l) => l[i].length)));
  const fmt = (l: string[]) => l.map((c, i) => (i === l.length - 1 ? c : c.padStart(wid[i]))).join('  ');
  const out = [fmt(head)];
  let marked = false;
  for (let i = 0; i < rows.length; i++) {
    if (!marked && rows[i].k > spot) { out.push(`${'-'.repeat(wid[0])}  spot ${spot.toFixed(2)}`); marked = true; }
    out.push(fmt(lines[i]));
  }
  if (!marked) out.push(`${'-'.repeat(wid[0])}  spot ${spot.toFixed(2)}`);
  return out.join('\n');
}
