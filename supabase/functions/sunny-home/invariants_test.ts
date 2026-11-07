// README 12 invariants as unit tests (handoff 6 Nov 2026, Pass 2).
// A made-up book (three names, the shapes of the README's sample, nobody's real positions) goes through the
// same path as a real build: buildBrief (the one engine) then buildDoc (New Home), at all eight moments. The
// checker must pass on every page, and must catch each kind of mismatch when a page is broken on purpose.
//
//   deno test --allow-read supabase/functions/sunny-home/invariants_test.ts

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type BriefLeg, buildBrief, type Moment } from './brief.ts';
import { buildDoc, type NameDay } from './doc.ts';
import { checkInvariants } from './invariants.ts';

type Row = Record<string, any>;
const addDays = (d: string, n: number) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const isTrading = (d: string) => { const w = new Date(d + 'T12:00:00Z').getUTCDay(); return w !== 0 && w !== 6; };

// ── The test book: Tue Oct 27 2026, calls and puts sold for Fri Oct 30 ──
const leg = (ticker: string, type: 'call' | 'put', side: 'sold' | 'bought', strike: number, expiry: string, n: number, avg: number, mark: number, iv: number): BriefLeg =>
  ({ ticker, type, side, strike, expiry, n, avg, mark, iv, opened: '2026-10-26' });
const LEGS: BriefLeg[] = [
  leg('NKE', 'call', 'sold', 36, '2026-10-30', 72, 0.32, 0.06, 0.40),
  leg('NKE', 'put', 'sold', 34, '2026-10-30', 30, 0.30, 0.12, 0.45),
  leg('NKE', 'call', 'bought', 38, '2027-09-17', 20, 2.1, 2.3, 0.38),
  leg('NKE', 'put', 'bought', 33, '2027-03-19', 30, 1.9, 1.8, 0.40),
  leg('BABA', 'call', 'sold', 104, '2026-10-30', 10, 1.1, 0.45, 0.42),
  leg('BABA', 'call', 'bought', 100, '2028-01-21', 5, 19, 20.5, 0.38),
  leg('BABA', 'put', 'bought', 95, '2027-01-15', 5, 4, 3.6, 0.40),
  leg('NFLX', 'call', 'sold', 74, '2026-10-30', 26, 1.0, 0.9, 0.35),
];
const SHARES = new Map([['NKE', 6000], ['BABA', 1500], ['NFLX', 2000]]);
const AVG = new Map([['NKE', 41.10], ['BABA', 88.40], ['NFLX', 61.50]]);
const SPOT = new Map([['NKE', 35.28], ['BABA', 99.63], ['NFLX', 73.40]]);
const PREV: Record<string, number> = { NKE: 35.89, BABA: 98.50, NFLX: 72.90 };
const CLOSES = Object.entries(PREV).flatMap(([t, p]) => ['2026-10-22', '2026-10-23', '2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30']
  .map((date, i) => ({ ticker: t, date, close_price: +(p * (1 + (i - 3) * 0.004)).toFixed(2) })).filter((c) => c.date !== '2026-10-27' || true));
const DIVS = [{ ticker: 'NKE', ex_date: '2026-12-01', cash_amount: 0.41, frequency: 4 }];
const ORDERS = [
  { kind: 'sell', t: 'NKE', act: 'Sell 60 Nov 6 36 calls', why: 'one per 100 shares', cost: 1500, credit: true },
  { kind: 'roll', t: 'BABA', act: 'Roll 20 104 calls to Nov 6', why: 'in the money', cost: 400, credit: false },
];
const BASE = 1_000_000;

const WHEN: Record<Moment, [string, string, number]> = {
  futures: ['2026-10-27', 'Tue', 3 * 60 + 30], pre: ['2026-10-27', 'Tue', 8 * 60 + 10], bell: ['2026-10-27', 'Tue', 9 * 60 + 31],
  open: ['2026-10-27', 'Tue', 11 * 60 + 20], last20: ['2026-10-27', 'Tue', 15 * 60 + 41], last5: ['2026-10-27', 'Tue', 15 * 60 + 56],
  post: ['2026-10-27', 'Tue', 17 * 60 + 10], weekend: ['2026-10-31', 'Sat', 10 * 60 + 30],
};

function page(moment: Moment, held = true, divs: Row[] = DIVS) {
  const [today, wd, mins] = WHEN[moment];
  const legs = held ? LEGS : [];
  const { brief, inputs } = buildBrief({ today, wd, mins, isTrading, addDays, cal: [], legs, isLeap: (l) => l.expiry >= '2027-12-01',
    shares: held ? SHARES : new Map(), shareAvg: AVG, spot: SPOT, closes: CLOSES, chain: [], divRows: divs, strategies: { NKE: 'rebound' } });
  assertEquals(brief.moment, moment);
  const names: NameDay[] = (brief.names as Row[]).map((b) => ({ t: b.t, shares: SHARES.get(b.t) ?? 0, leaps: b.t === 'BABA' ? 5 : 0, S0: b.S0, P0: b.P0,
    weekBase: b.P0 * 0.98, ext: b.t === 'NKE' ? -1.2 : 0.6, today: { sh: b.h.sh[1], lp: b.h.lp[1], oc: b.h.oc[1], ip: b.h.ip[1], sc: 150, sp: 20 },
    soldCalls: legs.filter((l) => l.ticker === b.t && l.side === 'sold' && l.type === 'call').map((l) => ({ K: l.strike, n: l.n, ex: l.expiry })) }));
  const orders = held ? ORDERS : [];
  const { full, open } = buildDoc({ moment, today, mins, isTrading, addDays, cal: [], brief, names, market: [], sectors: [], futures: [], watch: [],
    chart: null, yieldWeeks: [{ week: '2026-10-26', fri: '2026-10-30', calls_sold: 3000, calls_back: 800, puts_sold: 900, puts_back: 100 }],
    payback: { made: 12000, series2: [['2026-08-31', 0, 0], ['2026-09-30', 0, 5000], ['2026-10-30', 0, 12000]], pace_recent: 1500, pace_start: 1200 },
    history: null, earnings: [], macro: [], divs: held ? divs : [], trades: [], orders, aftershock: null, baseNow: BASE, baseAt: () => BASE });
  return { brief: brief as Row, inputs: inputs as Row, full, open, orders };
}

const MOMENTS: Moment[] = ['futures', 'pre', 'bell', 'open', 'last20', 'last5', 'post', 'weekend'];
const show = (fs: { id: number; detail: string }[]) => fs.map((f) => `#${f.id} ${f.detail}`).join('\n');
const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x));

for (const m of MOMENTS) {
  Deno.test(`Invariants hold · ${m}`, () => {
    const p = page(m);
    const fails = checkInvariants(p);
    assertEquals(fails.length, 0, show(fails));
  });
  Deno.test(`Invariants hold · ${m} · nothing held`, () => {
    const p = page(m, false);
    assertEquals(checkInvariants(p).length, 0, show(checkInvariants(p)));
  });
}

Deno.test('The test book has a name past its best, so invariant 1 is exercised', () => {
  const p = page('open');
  const nke = (p.brief.position.rows as Row[]).find((r) => r.id === 'NKE')!;
  assertEquals(nke.st, 2);
  assert(nke.fp > 35.28 && nke.fp < 37, `Nike makes the most near $36, got ${nke.fp}`);
  assert(nke.line.startsWith('Makes the most at $'), nke.line);
  const baba = (p.brief.position.rows as Row[]).find((r) => r.id === 'BABA')!;
  assert(baba.st < 2, `Alibaba keeps making more in the test book: ${baba.line}`);
});

Deno.test('Privacy · an ex-dividend first in Coming up keeps its dollars out of the headline', () => {
  const p = page('pre', true, [{ ticker: 'NKE', ex_date: '2026-10-28', cash_amount: 0.41, frequency: 4 }]);
  const h = p.full.sections.find((s: Row) => s.kicker === 'Coming up')?.headline?.map((x: Row) => x.t).join('') ?? '';
  assert(/ex-dividend/.test(h), `the headline should lead with the dividend: ${h}`);
  assertEquals(checkInvariants(p).filter((f) => f.id === 11), []);
});

// ── The checker catches each kind of mismatch ──
const caught = (fails: { id: number }[], id: number) => assert(fails.some((f) => f.id === id), `invariant ${id} not caught: ${JSON.stringify(fails)}`);

Deno.test('Caught · 1 · a To decide price a cent off', () => {
  const p = page('open'), full = clone(p.full);
  const td = full.sections.flatMap((s: Row) => s.cards).find((c: Row) => c.type === 'toDecide' && /makes the most/.test(c.subtitle));
  assert(td, 'the test book should have a To decide on Nike');
  td.subtitle = td.subtitle.replace(/\$([\d.]+)/, (_: string, v: string) => `$${(Number(v) + 0.01).toFixed(2)}`);
  caught(checkInvariants({ ...p, full }), 1);
});
Deno.test('Caught · 1 · Positions at the Friday stop disagrees with Home', () => {
  const p = page('open'), inputs = clone(p.inputs);
  const n = inputs.names.find((x: Row) => x.t === 'NKE');
  n.legs = n.legs.filter((l: Row) => l.kind !== 'otm');   // Positions priced without the OTM calls
  caught(checkInvariants({ ...p, inputs }), 1);
});
Deno.test('Caught · 2 · a strip dot that By name does not have', () => {
  const p = page('open'), brief = clone(p.brief);
  const long = brief.names.find((n: Row) => !n.short);
  assert(long, 'the test book should have a name that keeps making more');
  long.short = true;
  caught(checkInvariants({ ...p, brief }), 2);
});
Deno.test('Caught · 3 · a put cover line that does not add up', () => {
  const p = page('open'), brief = clone(p.brief);
  brief.position.cover = brief.position.cover.replace(/\d+%/, '99%');
  caught(checkInvariants({ ...p, brief }), 3);
});
Deno.test('Caught · 5 · Tomorrow says three orders, the card has two', () => {
  const p = page('post'), full = clone(p.full);
  full.sections.find((s: Row) => s.kicker === 'Tomorrow').headline = [{ t: 'Three orders to place at the open.', b: true }];
  caught(checkInvariants({ ...p, full }), 5);
});
Deno.test('Caught · 6 · the lede and the Your book headline disagree', () => {
  const p = page('open'), full = clone(p.full);
  const s = full.sections.find((x: Row) => x.kicker === 'Your book');
  s.headline = s.headline.map((x: Row) => (/^\$/.test(x.t) ? { ...x, t: '$1' } : x));
  caught(checkInvariants({ ...p, full }), 6);
});
Deno.test('Caught · 7 · the weekend lede yield and the Results card disagree', () => {
  const p = page('weekend'), full = clone(p.full);
  full.lede = full.lede.map((x: Row) => ({ ...x, t: x.t.replace(/^A [\d.]+% week/, 'A 9.99% week') }));
  caught(checkInvariants({ ...p, full }), 7);
});
Deno.test('Caught · 8 · the payback headline and card disagree', () => {
  const p = page('weekend'), full = clone(p.full);
  const pb = full.sections.flatMap((s: Row) => s.cards).find((c: Row) => c.type === 'payback');
  assert(pb, 'the weekend page should carry Payback');
  pb.big = '9.9%';
  caught(checkInvariants({ ...p, full }), 8);
});
Deno.test('Caught · 9 · two amounts for one dividend', () => {
  const p = page('pre'), full = clone(p.full);
  full.sections.push({ kicker: 'Test', headline: [], cards: [{ type: 'yourResults', bySegment: { Today: { dividends: { title: 'Dividends', line: [{ t: 'Next: Nike, ex Tue Dec 1, $9,999 · kept out of Made' }] } } } }] });
  caught(checkInvariants({ ...p, full }), 9);
});
Deno.test('Caught · 10 · a name from the other book', () => {
  const p = page('open'), full = clone(p.full);
  const wm = full.sections.flatMap((s: Row) => s.cards).find((c: Row) => c.type === 'whatsMoving');
  wm.rows.push({ ticker: 'UBER', move: '↑ 1.0%' });
  caught(checkInvariants({ ...p, full }), 10);
});
Deno.test('Caught · 11 · book money in the privacy lede', () => {
  const p = page('open'), full = clone(p.full);
  full.privacy.lede = [...full.privacy.lede, { t: ' You made $2,322.' }];
  caught(checkInvariants({ ...p, full }), 11);
});
Deno.test('Caught · 12 · an order in the copy without orders', () => {
  const p = page('post'), open = clone(p.open);
  open.sections[0].cards.push({ type: 'tomorrowOrders', rows: [] });
  caught(checkInvariants({ ...p, open }), 12);
});
