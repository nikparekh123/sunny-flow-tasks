/**
 * Sundial 1.0: the selling engine's rules, pure (no I/O), so the function, a test and any later reader share them.
 * Agreed with Nik on 25 Nov 2026, one rule at a time; the spec and the evidence are docs/SUNDIAL.md. Names: NVDA and
 * SpaceX (SPCX) in book N, same rules. Nik decides what to BUY; Sundial decides what to SELL.
 *
 *   Calls: at 3:45 PM ET (15 minutes before the close) every Monday, Wednesday and Friday, on the expiry a week out.
 *          Strike from the 11 Nov tables (the week's move in weekly SD, the trend, IV rich or cheap; cheap wins when
 *          the 20-day real moves beat the IV). Count: the most that keep the whole book from losing money at any rise
 *          from 0 to +20% at any close in the next 5 trading days (sold legs in full, bought legs only what the move
 *          does to them, not their decay). No calls on an expiry that spans an earnings report. A call worth half or
 *          less of its sale price at 3:45 PM on trading day 1 or 2 after the sale: buy back, leave that expiry empty.
 *          In the money: hold to expiry; then buy back and sell again (shares go only from lots held over a year).
 *   Puts:  2 on each new expiry (1 SD in an earnings week); on a big drop (2 daily SD under yesterday's close, live)
 *          up to the cap on the expiry a week out; never more than 30 sold puts open. In the money: hold; at expiry
 *          take the shares if the strike is under the average cost, else buy back and sell again.
 * No em dashes in any words written here (Nik).
 */

/** expiryCap (25 Nov 2026, from data, Nik: "it needs to be with risk and data, not a personal choice"): no expiry takes
    more than half the calls the +20% test allows a book with no calls sold. NVDA since 2010, 1,500 shares: no cap
    +$284K with a worst week of -$88K; half +$328K, -$61K; a third +$272K, -$55K; a quarter +$229K, -$46K. */
export const RULES = { up: 0.2, horizons: 5, putsNormal: 2, putCap: 30, earlyKept: 0.5, earlyDays: 2, dropSd: 2, expiryCap: 0.5, r: 0.04 };

// ── Black-Scholes (no dividends) ──
export const N = (x: number): number => {
  const t = 1 / (1 + 0.3275911 * Math.abs(x) / Math.SQRT2);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x / 2);
  return x >= 0 ? (1 + y) / 2 : (1 - y) / 2;
};
export function bs(S: number, K: number, T: number, v: number, put: boolean, r = RULES.r): number {
  if (!(T > 1e-9) || !(v > 0)) return Math.max(0, put ? K - S : S - K);
  const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + (r + v * v / 2) * T) / sq, d2 = d1 - sq;
  const c = S * N(d1) - K * Math.exp(-r * T) * N(d2);
  return put ? c - S + K * Math.exp(-r * T) : c;
}
export function ivFrom(px: number, S: number, K: number, T: number, put: boolean): number | null {
  const intr = Math.max(0, put ? K - S : S - K);
  if (!(px > intr + 0.005) || !(T > 0)) return null;
  let lo = 0.01, hi = 5;
  for (let i = 0; i < 70; i++) { const m = (lo + hi) / 2; if (bs(S, K, T, m, put) < px) lo = m; else hi = m; }
  return (lo + hi) / 2;
}

// ── Trading time ──
export const addDays = (d: string, n: number) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
export const isWeekday = (d: string) => { const w = new Date(d + 'T12:00:00Z').getUTCDay(); return w !== 0 && w !== 6; };
/** Trading days after `a` through `b` (weekends and `closed` days left out). */
export function tdays(a: string, b: string, closed: Set<string>): number {
  let n = 0;
  for (let d = addDays(a, 1); d <= b; d = addDays(d, 1)) if (isWeekday(d) && !closed.has(d)) n++;
  return n;
}
/** The next `n` trading days after `a`. */
export function nextTdays(a: string, n: number, closed: Set<string>): string[] {
  const out: string[] = [];
  for (let d = addDays(a, 1); out.length < n; d = addDays(d, 1)) if (isWeekday(d) && !closed.has(d)) out.push(d);
  return out;
}
/** Years for pricing: trading days to the expiry over 252; on the expiry day itself the minutes left of the session. */
export function yrs(from: string, ex: string, closed: Set<string>, minsLeft = 0): number {
  const n = tdays(from, ex, closed);
  return (n + Math.max(0, minsLeft) / 390) / 252;
}

// ── The 11 Nov tables, with Sundial's two overrides (cheap wins; earnings = no calls, puts 1 SD) ──
export type Trend = 'up' | 'mid' | 'down';
export interface Signals {
  S: number; z: number; trend: Trend; d52: number | null; iv30: number; hv20: number | null; rank: number;
  rich: boolean; cheap: boolean; freak: boolean; ma50: number | null; ma200: number | null;
}
export interface SigIn {
  S: number; prevClose: number;
  /** Stored closes, oldest first, up to yesterday (today's live price is S). */
  closes: number[];
  /** The 30-day IV today, and on the day 4 sessions back (the base of the week's move), and the saved IV history. */
  iv30: number; iv5: number; ivHist: number[];
}
export function signals(x: SigIn): Signals {
  const c = x.closes, S = x.S, all = [...c, S];
  const S5 = c.length >= 4 ? c[c.length - 4] : c[0];
  const w = x.iv5 * Math.sqrt(5 / 252), z = Math.log(S / S5) / w;
  const avg = (a: number[]) => a.reduce((p, q) => p + q, 0) / a.length;
  const ma50 = c.length >= 50 ? avg(c.slice(-50)) : null, ma200 = c.length >= 200 ? avg(c.slice(-200)) : null;
  const trend: Trend = !ma50 ? 'mid' : S <= ma50 ? 'down' : ma200 && S > ma200 ? 'up' : 'mid';
  let hv20: number | null = null;
  if (all.length >= 21) {
    const r: number[] = []; for (let i = all.length - 20; i < all.length; i++) r.push(Math.log(all[i] / all[i - 1]));
    const mu = avg(r); hv20 = Math.sqrt(r.reduce((a, b) => a + (b - mu) ** 2, 0) / (r.length - 1) * 252);
  }
  const lo52 = Math.min(...c.slice(-252), S);
  const d52 = lo52 > 0 ? Math.log(S / lo52) / (x.iv30 * Math.sqrt(5 / 252)) : null;
  const yr = x.ivHist.length ? x.ivHist : [x.iv30];
  const lo = Math.min(...yr, x.iv30), hi = Math.max(...yr, x.iv30), rank = hi > lo ? (x.iv30 - lo) / (hi - lo) * 100 : 50;
  const ratio = hv20 ? x.iv30 / hv20 : 1;
  // ⚠ CHEAP WINS (Nik, 25 Nov 2026): when the stock moves more than its IV, the options are cheap whatever the rank.
  const cheapWins = hv20 != null && hv20 > x.iv30;
  const rich = !cheapWins && (rank >= 70 || ratio >= 1.3);
  const cheap = cheapWins || (!rich && (rank <= 20 || ratio <= 1.0));
  return { S, z, trend, d52, iv30: x.iv30, hv20, rank, rich, cheap, freak: S / x.prevClose - 1 >= 0.2, ma50, ma200 };
}
/** The call's SD distance, or null in an earnings week (no calls). */
export function callSd(s: Signals, earnings: boolean): number | null {
  if (earnings) return null;
  const z = s.z;
  let k = s.freak ? 0 : z >= 2 ? 0.25 : z >= 1 ? 0.5 : z <= -2 ? 0.5 : z <= -1 ? 0.75 : s.trend === 'up' ? 0.75 : 0.5;
  if (s.rich) k -= 0.25; else if (s.cheap) k += 0.25;
  return Math.round(Math.min(1.25, Math.max(s.freak ? 0 : 0.25, k)) * 4) / 4;
}
/** The put's SD distance (-0.25 = one strike in the money); 1 in an earnings week. */
export function putSd(s: Signals, earnings: boolean): number {
  if (earnings) return 1;
  const z = s.z, t = s.trend;
  let k: number;
  if (z <= -2) k = t === 'up' ? -0.25 : t === 'mid' ? 0 : s.d52 == null ? 0.5 : s.d52 < 1 ? 0 : s.d52 < 2 ? 0.25 : 0.5;
  else if (z <= -1) k = t === 'up' ? 0.5 : t === 'mid' ? 0.75 : 1;
  else if (z >= 1) k = 1;
  else k = t === 'up' ? 0.75 : 1;
  const tab = k;
  if (s.rich) k -= 0.25; else if (s.cheap) k += 0.25;
  return Math.round(Math.min(1, Math.max(tab === -0.25 ? -0.25 : 0, k)) * 4) / 4;
}
/** The strike k SD from S on an expiry whose own IV is `iv` and time T, snapped to the listed strikes when given. */
export function strikeAt(S: number, k: number, iv: number, T: number, put: boolean, listed: number[] = []): number {
  if (put && k < 0) { const up = listed.filter((x) => x > S).sort((a, b) => a - b)[0]; return up ?? Math.ceil(S); }
  const K = S * Math.exp((put ? -k : k) * iv * Math.sqrt(Math.max(T, 1 / 252)));
  return listed.length ? listed.reduce((a, b) => (Math.abs(b - K) < Math.abs(a - K) ? b : a)) : Math.round(K * 2) / 2;
}

// ── The +20% test ──
export interface Leg { type: 'call' | 'put'; K: number; ex: string; n: number; side: 1 | -1; iv: number }
export interface TestOut { ok: boolean; worst: number; at: number; day: string }
/** The whole book (shares + every leg) at every rise from 0 to +20% at the close of each of the next 5 trading days,
    against now. Sold legs count in full (from today's value: their premium is the cushion); bought legs only what the
    move does to them (their value at the risen price less their value at today's price, both on that day). */
export function test20(S0: number, shares: number, legs: Leg[], today: string, closed: Set<string>, minsLeft: number, up = RULES.up): TestOut {
  let worst = Infinity, at = 0, day = today;
  const hs = nextTdays(today, RULES.horizons, closed);
  const now = legs.map((l) => (l.side < 0 ? bs(S0, l.K, yrs(today, l.ex, closed, minsLeft), l.iv, l.type === 'put') : 0));
  for (const h of hs) {
    const T = legs.map((l) => (l.ex < h ? 0 : yrs(h, l.ex, closed)));
    const base = legs.map((l, i) => (l.side > 0 ? bs(S0, l.K, T[i], l.iv, l.type === 'put') : 0));
    // 21 steps from 0 to the test size (RULES.up: +20% for NVDA and SPCX; a name's own size elsewhere). At +20% these are
    // the same 1% steps as before, so NVDA and SPCX answer exactly as they did.
    for (let p = 0; p <= 20; p++) {
      const S = S0 * (1 + up * p / 20);
      let v = shares * (S - S0);
      legs.forEach((l, i) => {
        const x = bs(S, l.K, T[i], l.iv, l.type === 'put');
        v += l.side < 0 ? l.n * 100 * (now[i] - x) : l.n * 100 * (x - base[i]);
      });
      if (v < worst) { worst = v; at = p; day = h; }
    }
  }
  return { ok: worst >= 0, worst, at, day };
}
/** The most calls at K on `ex` that still pass. */
export function room(S0: number, shares: number, legs: Leg[], K: number, ex: string, iv: number, today: string, closed: Set<string>, minsLeft: number, max = 150, up = RULES.up): { n: number; test: TestOut } {
  let n = 0, test = test20(S0, shares, legs, today, closed, minsLeft, up);
  if (!test.ok) return { n: 0, test };
  // Grow by doubling, then halve back: the test is monotone in the count.
  let lo = 0, hi = 1;
  const pass = (k: number) => test20(S0, shares, [...legs, { type: 'call', K, ex, n: k, side: -1, iv }], today, closed, minsLeft, up);
  while (hi <= max && pass(hi).ok) { lo = hi; hi *= 2; }
  hi = Math.min(hi, max + 1);
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (pass(m).ok) lo = m; else hi = m; }
  n = lo; test = pass(n);
  return { n, test };
}

/** The big-drop line: yesterday's close less 2 daily SD (daily SD = yesterday's 30-day IV / square root of 252). */
export const dropLine = (prevClose: number, ivPrev: number) => prevClose * (1 - RULES.dropSd * ivPrev / Math.sqrt(252));
