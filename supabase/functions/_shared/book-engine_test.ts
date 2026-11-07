// The book engine against the design (handoff 6 Nov 2026). Run: deno test supabase/functions/_shared/book-engine_test.ts
//
// With the prototype's settings (no rate, no dividends, one IV per name, this week's sold legs 3 days out)
// the engine must give the numbers the design rendered (engine-notes.md "Expected values"), and the README 12
// invariants must hold. The real book runs the same code with each leg's IV, a 4% rate and dividends.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { fK, fn, holdings, type Leg, NameBook, otmStrike, positionsGrid, type Stop, yourPosition } from './book-engine.ts';

// ── The design's sample book (reference/sunny-web-data.js, Tue Oct 27) ───────
const Q: Record<string, [number, number]> = { BABA: [99.63, 101.77], LULU: [99.05, 104.04], NKE: [35.28, 35.90], NFLX: [73.40, 72.10], UBER: [67.10, 67.85], FIS: [33.60, 33.95], PEP: [141.20, 140.60] };
const IV: Record<string, number> = { BABA: 0.40, LULU: 0.48, NKE: 0.35, NFLX: 0.45, UBER: 0.38, FIS: 0.30, PEP: 0.18 };
const CO: Record<string, string> = { BABA: 'Alibaba', LULU: 'Lululemon', NKE: 'Nike', NFLX: 'Netflix', UBER: 'Uber', FIS: 'FIS', PEP: 'PepsiCo' };
const XD: Record<string, number> = { 'Jan 15': 80, 'Mar 19': 143, 'Jun ’27': 234, 'Sep ’27': 325, 'Jan ’28': 451 };
const BK = ['BABA', 'LULU', 'NKE', 'NFLX', 'UBER', 'FIS', 'PEP'];
type Sold = [number, 'c' | 'p', number, number, number];
type Bought = ['LEAPS' | 'Hedge call' | 'Insurance put', number, number, string, number];
type Book = Record<string, { sh: [number, number]; sold: Sold[]; legs: Bought[] }>;
const BOOK_A: Book = {
  BABA: { sh: [1500, 88.40], sold: [[104, 'c', 20, 0.66, 0.535]], legs: [['LEAPS', 100, 5, 'Jan ’28', 26.40], ['Hedge call', 108, 10, 'Sep ’27', 11.20], ['Insurance put', 95, 5, 'Jan 15', 4.90]] },
  LULU: { sh: [1000, 118.20], sold: [], legs: [['LEAPS', 90, 10, 'Jan ’28', 24.80], ['Hedge call', 105, 6, 'Jun ’27', 12.90], ['Insurance put', 90, 5, 'Jan 15', 4.20]] },
  NKE: { sh: [6000, 41.10], sold: [[36, 'c', 72, 0.32, 0.06], [34, 'p', 30, 0.18, 0.03]], legs: [['Hedge call', 38, 20, 'Sep ’27', 3.60], ['Insurance put', 33, 30, 'Mar 19', 1.45]] },
  NFLX: { sh: [2000, 61.50], sold: [[74, 'c', 26, 0.55, 0.30]], legs: [['LEAPS', 65, 10, 'Jan ’28', 19.20], ['Hedge call', 80, 10, 'Jun ’27', 8.40]] },
  UBER: { sh: [1200, 72.30], sold: [[71, 'c', 12, 0.40, 0.28]], legs: [] },
  FIS: { sh: [2500, 30.90], sold: [[35, 'c', 25, 0.20, 0.09]], legs: [] },
  PEP: { sh: [800, 152.60], sold: [[145, 'c', 8, 0.70, 0.51]], legs: [] },
};
const BOOK_B: Book = {
  BABA: { sh: [500, 92.10], sold: [[104, 'c', 5, 0.66, 0.535]], legs: [['Insurance put', 95, 2, 'Jan 15', 4.90]] },
  LULU: { sh: [400, 112.50], sold: [], legs: [['Hedge call', 105, 2, 'Jun ’27', 12.90]] },
  NKE: { sh: [2000, 39.80], sold: [[36, 'c', 20, 0.32, 0.06]], legs: [['Insurance put', 33, 10, 'Mar 19', 1.45]] },
  NFLX: { sh: [600, 64.00], sold: [[74, 'c', 6, 0.55, 0.30]], legs: [['LEAPS', 65, 3, 'Jan ’28', 19.20], ['Hedge call', 80, 3, 'Jun ’27', 8.40]] },
  UBER: { sh: [500, 70.10], sold: [[71, 'c', 5, 0.40, 0.28]], legs: [] },
  FIS: { sh: [1000, 31.20], sold: [[35, 'c', 10, 0.20, 0.09]], legs: [] },
  PEP: { sh: [300, 150.10], sold: [[145, 'c', 3, 0.70, 0.51]], legs: [] },
};

/** The sample book as engine legs. weekend = this week's sold legs left out (they ended Friday). */
function sampleNames(B: Book, t0: number, weekend: boolean): NameBook[] {
  return BK.filter((t) => B[t]).map((t) => {
    const b = B[t], v = IV[t], legs: Leg[] = [];
    if (!weekend) b.sold.forEach(([K, s, q, at, now], i) => legs.push({ k: 's' + i, kind: s === 'c' ? 'sc' : 'sp', ty: s === 'c' ? 'C' : 'P', K, q: -q, days: 3, iv: v, ex: '2026-10-30', label: '', at, now }));
    legs.push({ k: 'sh', kind: 'shares', ty: 'S', K: b.sh[1], q: b.sh[0], days: 0, iv: 0, ex: '', label: '' });
    b.legs.forEach(([nm, K, q, ex, paid], i) => legs.push({ k: 'l' + i, kind: nm === 'Insurance put' ? 'ins' : nm === 'LEAPS' ? 'leaps' : 'otm', ty: nm === 'Insurance put' ? 'P' : 'C', K, q, days: XD[ex] ?? 300, iv: v, ex, label: '', at: paid }));
    return new NameBook({ t, S0: Q[t][0], P0: Q[t][1], iv: v, legs, t0 });
  });
}
const cover = (B: Book) => BK.reduce((a, t) => { const b = B[t], I = b.legs.find((l) => l[0] === 'Insurance put'); return { shares: a.shares + b.sh[0], covered: a.covered + (I ? Math.min(b.sh[0], I[2] * 100) : 0) }; }, { shares: 0, covered: 0 });
const SUB: Record<string, string> = { pre: 'Before the bell · by Friday’s close', open: 'Now · by Friday’s close', post: 'At the close · by Friday', weekend: 'Calls ended Friday · to next Friday' };
const T0: Record<string, number> = { pre: 0, open: 0.3, post: 0.5, weekend: 4 };
function card(B: Book, moment: 'pre' | 'open' | 'post' | 'weekend') {
  const wk = moment === 'weekend';
  return yourPosition(sampleNames(B, T0[moment], wk), { th: wk ? 9.9 : 2.9, weekend: wk, nextFriday: wk, sub: SUB[moment] }, (t) => CO[t] ?? t, cover(B), []);
}
const text = (s: { t: string }[]) => s.map((x) => x.t).join('');
const row = (yp: ReturnType<typeof card>, t: string) => yp.rows.find((r) => r.id === t)!;

// ── Your position: the design's rendered numbers ─────────────────────────────
Deno.test('Your position · pre · Sunny', () => {
  const yp = card(BOOK_A, 'pre');
  assertEquals(fK(yp.dollarDelta), '$9.3K');
  assertEquals(yp.stats.map((s) => s.v), ['$40K', '$3.8K', '$52K']);
  assertEquals(yp.stats.map((s) => s.c), ['green', 'green', 'red']);
  assertEquals(yp.cover, 'Insurance puts cover 4,000 of your 15,000 shares, 27%. Shares have no floor below that.');
  assertEquals(yp.count, '1 past its best, 2 thin at a priced move');
  assertEquals(yp.rows.map((r) => r.id), ['NKE', 'BABA', 'NFLX', 'FIS', 'PEP', 'UBER', 'LULU']);
  assertEquals(row(yp, 'NKE').right, 'Short 917 Δ');
  assertEquals(row(yp, 'NKE').at, 'at ↑4.9%');
  assertEquals(row(yp, 'BABA').line, 'Thin by Friday, still gains as it rises');
  assertEquals(row(yp, 'FIS').line, 'Keeps making more past ↑12.7%');
  assertEquals(row(yp, 'FIS').right, 'Long 1,134 Δ');
  assertEquals(row(yp, 'PEP').right, 'Long 555 Δ');
  assertEquals(row(yp, 'UBER').right, 'Long 905 Δ');
  assertEquals(row(yp, 'LULU').line, 'Keeps making more past ↑20.3%');
  assertEquals(row(yp, 'LULU').right, 'Long 1,965 Δ');
  // To the cent the design's .05% grid says $36.23; the engine's first cent may sit one or two cents lower.
  const fp = row(yp, 'NKE').fp!;
  assert(fp >= 36.20 && fp <= 36.24, 'Nike turns short near $36.23, got ' + fp);
  assertEquals(text(yp.sentence), `Long now: a 1% rise makes you $9.3K. Your book keeps making more even if the market rises 10% by Friday, but Nike makes the most at $${fp.toFixed(2)}.`);
});

Deno.test('Your position · open · Sunny and Nicolay', () => {
  const a = card(BOOK_A, 'open'), b = card(BOOK_B, 'open');
  assertEquals(fK(a.dollarDelta), '$9.4K');
  assertEquals(a.stats.map((s) => s.v), ['$40K', '$3.4K', '$52K']);
  assertEquals(fK(b.dollarDelta), '$2.8K');
  assertEquals(b.stats.map((s) => s.v), ['$12K', '$863', '$15K']);
  assertEquals(b.cover, 'Insurance puts cover 1,200 of your 5,300 shares, 23%. Shares have no floor below that.');
  assertEquals(b.count, '2 past their best at a priced move');
  assertEquals(b.rows.slice(0, 2).map((r) => r.id), ['NKE', 'BABA']);
  assertEquals(row(b, 'NKE').right, 'Short 262 Δ');
  assertEquals(row(b, 'BABA').right, 'Short 34 Δ');
  const bp = row(b, 'BABA').fp!;
  assert(bp >= 104.85 && bp <= 104.91, 'Alibaba turns short near $104.91, got ' + bp);
  assertEquals(row(b, 'NFLX').line, 'Keeps making more past ↑19.0%');
  assertEquals(row(b, 'NFLX').right, 'Long 383 Δ');
});

Deno.test('Your position · post', () => {
  assertEquals(card(BOOK_A, 'post').stats.map((s) => s.v), ['$40K', '$3.2K', '$53K']);
  assertEquals(fK(card(BOOK_A, 'post').dollarDelta), '$9.5K');
  assertEquals(card(BOOK_B, 'post').stats[1].v, '$799');
});

Deno.test('Your position · weekend', () => {
  const a = card(BOOK_A, 'weekend'), b = card(BOOK_B, 'weekend');
  assertEquals(text(a.sentence), 'This week’s calls ended Friday, so you are long only until Monday’s sales: a 1% rise makes you $11K. Selling again caps how much a rise can make.');
  assertEquals(a.stats.map((s) => s.v), ['$55K', '$1.2K', '$56K']);
  assertEquals(a.stats[1].l, 'flat to next Fri');
  assertEquals(a.count, 'Every name long at a priced move');
  assertEquals(row(a, 'NKE').right, 'Long 6,291 Δ');
  assertEquals(row(a, 'NKE').line, 'Keeps making more past ↑14.8%');
  assertEquals(row(a, 'NFLX').right, 'Long 3,274 Δ');
  assertEquals(b.stats.map((s) => s.v), ['$16K', '$219', '$17K']);
  assertEquals(row(b, 'NKE').right, 'Long 1,742 Δ');
});

// ── Positions: Nike today and at the Oct 30 close ────────────────────────────
const STOPS: Stop[] = [[0, 'Today', 'today', 'Tue Oct 27', false], [1, 'Wed', 'on Wednesday', 'Wed Oct 28', false], [2, 'Thu', 'on Thursday', 'Thu Oct 29', false], [2.9, 'Oct 30', 'at the Oct 30 close', 'Fri Oct 30 close', true]]
  .map(([tt, s, p, l, f]) => ({ tt: tt as number, short: s as string, phrase: p as string, long: l as string, friday: f as boolean }));

Deno.test('Positions · Nike · today and the Friday stop', () => {
  const nke = sampleNames(BOOK_A, 0, false).find((x) => x.t === 'NKE')!;
  const g0 = nke.greeks(nke.S0, 0), g3 = nke.greeks(nke.S0, 2.9);
  assertEquals(f$(nke.pl(nke.S0, 0, { earned: true })), '$2,322');
  assertEquals(fn(g0.d), '4,366'); assertEquals(fn(g0.th), '510'); assertEquals(fn(g0.g), '2,437'); assertEquals(fn(g0.vg), '412');
  assertEquals(f$(nke.pl(nke.S0, 2.9, { earned: true })), '$3,686');
  assertEquals(fn(g3.d), '5,934'); assertEquals(fn(g3.th), '42'); assertEquals(fn(g3.g), '172'); assertEquals(fn(g3.vg), '504');
});

Deno.test('Positions grid · legs add up to the engine', () => {
  const nke = sampleNames(BOOK_A, 0, false).find((x) => x.t === 'NKE')!;
  const G = positionsGrid(nke, STOPS, { K: otmStrike(nke.S0), ex: '2027-09-17', days: 325, label: 'Sep ’27' });
  const mid = (G.S.length - 1) / 2, fri = 3;
  assertEquals(G.S[mid], nke.S0);
  const plSum = G.legs.reduce((a, l) => a + l.pl[fri][mid] + l.earned, 0);
  assert(Math.abs(plSum - nke.pl(nke.S0, 2.9, { earned: true })) < G.legs.length, 'grid P&L adds up');
  const dSum = G.legs.reduce((a, l) => a + l.d[fri][mid], 0);
  assert(Math.abs(dSum - nke.delta(nke.S0, 2.9)) < 0.1 * G.legs.length, 'grid delta adds up');
  assertEquals(otmStrike(35.28), 38);
  // A leg switched off leaves every total (m45 OFF): the 36 calls off makes Nike longer.
  const off = new Set(['s0']);
  assert(nke.delta(nke.S0, 2.9, { off }) > nke.delta(nke.S0, 2.9));
});

// ── Invariants (README 12) ───────────────────────────────────────────────────
Deno.test('Invariant 1 · turns-short price is one number on Home and Positions', () => {
  for (const B of [BOOK_A, BOOK_B]) {
    const yp = card(B, 'open');
    for (const nb of sampleNames(B, 0.3, false)) {
      const r = yp.rows.find((x) => x.id === nb.t)!;
      if (r.fp == null) continue;
      const G = positionsGrid(nb, STOPS, null);
      assertEquals(G.turnsShort[3], r.fp, nb.t + ': Positions at the Friday stop says the Home price');
      assert(r.line.includes('$' + r.fp.toFixed(2)) || r.line.startsWith('Already past'));
    }
  }
});

Deno.test('Invariant 2 · short names are the Positions dots', () => {
  for (const B of [BOOK_A, BOOK_B]) {
    const yp = card(B, 'open');
    for (const nb of sampleNames(B, 0.3, false)) {
      const dot = nb.delta(nb.S0 * (1 + nb.sd / 100), 2.9) < 0;
      assertEquals(dot, yp.rows.find((x) => x.id === nb.t)!.st === 2, nb.t);
    }
  }
});

Deno.test('Invariant 10 · the other account never leaks in', () => {
  const a = card(BOOK_A, 'open'), b = card(BOOK_B, 'open');
  assert(a.stats[1].v !== b.stats[1].v);
  assertEquals(row(a, 'NKE').right, 'Short 917 Δ');
  assertEquals(row(b, 'NKE').right, 'Short 262 Δ');
});

// ── Real-book pricing: rate and dividends move the numbers the right way ─────
Deno.test('Rate and dividends', () => {
  const leg: Leg = { k: 'l0', kind: 'leaps', ty: 'C', K: 40, q: 1, days: 400, iv: 0.4, ex: '', label: '' };
  const plain = new NameBook({ t: 'X', S0: 38, iv: 0.4, legs: [leg] });
  const rated = new NameBook({ t: 'X', S0: 38, iv: 0.4, legs: [leg], r: 0.04 });
  const paid = new NameBook({ t: 'X', S0: 38, iv: 0.4, legs: [leg], r: 0.04, divs: [{ days: 30, amt: 0.41 }, { days: 120, amt: 0.41 }, { days: 210, amt: 0.41 }, { days: 300, amt: 0.41 }] });
  assert(rated.dl(leg, 38, 0) > plain.dl(leg, 38, 0), 'a rate raises a call delta');
  assert(paid.dl(leg, 38, 0) < rated.dl(leg, 38, 0), 'dividends lower a call delta');
  const h = holdings(paid);
  assert(h.lp[0] > 0);
});

const f$ = (x: number) => '$' + Math.round(Math.abs(x)).toLocaleString('en-US');
