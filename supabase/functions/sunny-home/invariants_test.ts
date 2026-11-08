// README 12 invariants as unit tests (handoff 6 Nov 2026, Pass 2).
// A made-up book (three names, the shapes of the README's sample, nobody's real positions) goes through the
// same path as a real build: buildBrief (the one engine) then buildDoc (New Home), at all eight moments. The
// checker must pass on every page, and must catch each kind of mismatch when a page is broken on purpose.
//
//   deno test --allow-read supabase/functions/sunny-home/invariants_test.ts

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type BriefLeg, buildBrief, company, type Moment, momentOf } from './brief.ts';
import { buildDoc, type DocIn, type NameDay } from './doc.ts';
import { checkInvariants, checkOverview } from './invariants.ts';
import { buildOverview, comingIn } from './overview.ts';

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

function page(moment: Moment, held = true, divs: Row[] = DIVS, extra: Partial<DocIn> = {}, legsIn: BriefLeg[] = LEGS) {
  const [today, wd, mins] = WHEN[moment];
  const legs = held ? legsIn : [];
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
    history: null, earnings: [], macro: [], divs: held ? divs : [], trades: [], orders, aftershock: null, baseNow: BASE, baseAt: () => BASE, ...extra });
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

// ── Overview across two books (README 12: 2, 3, 4, 5, 9) ──

function bookB() {
  const [today, wd, mins] = WHEN.open;
  const legs: BriefLeg[] = [
    leg('NKE', 'call', 'sold', 36, '2026-10-30', 20, 0.32, 0.06, 0.40),
    leg('NKE', 'put', 'bought', 33, '2027-03-19', 10, 1.9, 1.8, 0.40),
    leg('BABA', 'call', 'sold', 104, '2026-10-30', 5, 1.1, 0.45, 0.42),
  ];
  const { brief, inputs } = buildBrief({ today, wd, mins, isTrading, addDays, cal: [], legs, isLeap: (l) => l.expiry >= '2027-12-01',
    shares: new Map([['NKE', 2000], ['BABA', 500], ['FIS', 1000]]), shareAvg: new Map([['NKE', 39.8], ['BABA', 90], ['FIS', 31]]),
    spot: new Map([...SPOT, ['FIS', 33.6]]), closes: [...CLOSES, ...CLOSES.filter((c) => c.ticker === 'NKE').map((c) => ({ ...c, ticker: 'FIS', close_price: 33.6 }))],
    chain: [], divRows: DIVS, strategies: {} });
  return { brief: { ...(brief as Row), base: 250_000, pace: { week: 0.5, avg4: 0.6 } }, inputs: inputs as Row };
}
function overview() {
  const a = page('open'), b = bookB();
  const sides = [{ id: 'S', name: 'Sunny', brief: { ...a.brief, base: BASE, pace: { week: 0.7, avg4: 0.5 } }, inputs: a.inputs, orders: ORDERS },
    { id: 'N', name: 'Nicolay', brief: b.brief, inputs: b.inputs, orders: [ORDERS[0]] }];
  const o: Row = { ...buildOverview(sides, '2026-10-27', 11 * 60 + 20, company), comingIn: comingIn(sides, DIVS, company) };
  return { o, sides };
}

Deno.test('Overview · both books agree with each book', () => {
  const { o, sides } = overview();
  const fails = checkOverview(o, sides, DIVS);
  assertEquals(fails.length, 0, show(fails));
  assertEquals(o.header, 'Both accounts · Tue Oct 27');
  assertEquals(o.checks.map((c: Row) => c.name), ['Downside', 'Concentration', 'Pace', 'Calls at work', 'Delta', 'To do']);
  assertEquals(o.checks.find((c: Row) => c.name === 'To do').big, '3');
  assert(!/turns? short/.test(JSON.stringify(o)), 'Overview never says "turns short"');
  assert(!/—/.test(JSON.stringify(o)), 'no em dashes');
});
Deno.test('Overview · caught · a Delta chip that disagrees with the book', () => {
  const { o, sides } = overview();
  const d = o.checks.find((c: Row) => c.name === 'Delta');
  d.chips = d.chips.map((c: string) => (c.startsWith('Nicolay') ? 'Nicolay all long' : c));
  caught(checkOverview(o, sides, DIVS), 2);
});
Deno.test('Overview · caught · a To do chip that disagrees with the orders', () => {
  const { o, sides } = overview();
  const d = o.checks.find((c: Row) => c.name === 'To do');
  d.chips = d.chips.map((c: string) => (c.startsWith('Sunny') ? 'Sunny 9' : c));
  caught(checkOverview(o, sides, DIVS), 5);
});
Deno.test('Overview · caught · Coming in that is not shares x per share', () => {
  const { o, sides } = overview();
  o.comingIn.raw[0].amount += 1;
  caught(checkOverview(o, sides, DIVS), 9);
});

// ── Audit 7 · README 9.4: a feed that has stopped hides what it feeds; stale prices are marked ──
const cardsOf = (doc: Row) => (doc.sections as Row[]).flatMap((x) => x.cards as Row[]);
Deno.test('Audit 7 · a stopped dividends feed hides the line, never "None ahead"', () => {
  const live = cardsOf(page('post').full).find((c) => c.type === 'yourResults')!;
  assert(live.bySegment.Today.dividends.line, 'the line shows while the feed runs');
  const { full } = page('post', true, [], { feeds: { stopped: ['dividends'] } });
  const yr = cardsOf(full).find((c) => c.type === 'yourResults')!;
  assertEquals(yr.bySegment.Today.dividends.line, null);
  assert(!JSON.stringify(full).includes('None ahead'), 'claims no dividends without a feed');
});
Deno.test('Audit 7 · a stopped earnings feed hides Earnings ahead', () => {
  const earnings = [{ ticker: 'NKE', date: '2026-10-30', estimated: false, priced_move_pct: 8 }];
  const on = JSON.stringify(page('pre', true, DIVS, { earnings }).full);
  assert(on.includes('Nike reports'), 'shows while the feed runs');
  const off = JSON.stringify(page('pre', true, DIVS, { earnings, feeds: { stopped: ['earnings'] } }).full);
  assert(!off.includes('reports'), 'an earnings row from a stopped feed');
});
Deno.test('Audit 7 · index prices 25 minutes old read "As of", fresh ones "Live"', () => {
  const market = ['SPY', 'QQQ', 'IWM', '^VIX'].map((symbol) => ({ symbol, price: 100, regular_price: 100, regular_change_pct: 0.4 }));
  const foot = (at: string) => (cardsOf(page('open', true, DIVS, { market, feeds: { stopped: [], marketAt: at } }).full).find((c) => c.type === 'indexCards')!).footer;
  assertEquals(foot('2026-10-27T15:10:00Z'), 'Live');            // 11:10 AM New York at 11:20
  assertEquals(foot('2026-10-27T14:55:00Z'), 'As of 10:55 AM');  // 25 minutes old
  assertEquals(foot('2026-10-26T20:00:00Z'), 'As of Mon Oct 26, 4:00 PM');  // yesterday's close at 11:20
});
Deno.test('Audit 7 · an early close moves the last 20, last 5 and post-market to 1:00 PM', () => {
  assertEquals(momentOf('Thu', 12 * 60 + 30, 780), 'open');
  assertEquals(momentOf('Thu', 12 * 60 + 41, 780), 'last20');
  assertEquals(momentOf('Thu', 12 * 60 + 56, 780), 'last5');
  assertEquals(momentOf('Thu', 13 * 60 + 10, 780), 'post');
  assertEquals(momentOf('Fri', 13 * 60 + 5, 780), 'weekend');
  assertEquals(momentOf('Thu', 15 * 60 + 41), 'last20');
});

for (const m of MOMENTS) {
  Deno.test(`Audit 7 · nothing sold this week, shares and bought legs only · ${m}`, () => {
    const bought = LEGS.filter((l) => l.side === 'bought');
    const p = page(m, true, DIVS, { orders: [] }, bought);
    assertEquals(checkInvariants({ ...p, orders: [] }).length, 0, show(checkInvariants({ ...p, orders: [] })));
    const rows = p.brief.position.rows as Row[];
    assert(rows.length > 0, 'Your position still shows the names');
    assert(rows.every((r) => r.st < 2), 'nothing sold, so no name is past its best');
    assert(!JSON.stringify(p.full).includes('NaN') && !JSON.stringify(p.full).includes('undefined'), 'no NaN or undefined on the page');
  });
}

// ── Weekday market holidays (Nik, 8 Nov 2026): the weekend's "markets closed" page, the Holiday card on top ──
function holidayPage(today: string, wd: string, mins: number, closed: string[], early: string | null, legsIn: BriefLeg[] = LEGS) {
  const cal: Row[] = [...closed.map((d) => ({ date: d, kind: 'closed', name: 'Test Holiday' })), ...(early ? [{ date: early, kind: 'early_close', closes: '13:00:00', name: 'Early close' }] : [])];
  const trading = (d: string) => isTrading(d) && !closed.includes(d);
  const { brief } = buildBrief({ today, wd, mins, isTrading: trading, addDays, cal, legs: legsIn, isLeap: (l) => l.expiry >= '2027-12-01',
    shares: SHARES, shareAvg: AVG, spot: SPOT, closes: CLOSES, chain: [], divRows: DIVS, strategies: { NKE: 'rebound' } });
  const names: NameDay[] = (brief.names as Row[]).map((b) => ({ t: b.t, shares: SHARES.get(b.t) ?? 0, leaps: 0, S0: b.S0, P0: b.P0,
    weekBase: b.P0 * 0.98, ext: 0, today: { sh: b.h.sh[1], lp: b.h.lp[1], oc: b.h.oc[1], ip: b.h.ip[1], sc: 0, sp: 0 },
    soldCalls: legsIn.filter((l) => l.ticker === b.t && l.side === 'sold' && l.type === 'call').map((l) => ({ K: l.strike, n: l.n, ex: l.expiry })) }));
  const { full, open } = buildDoc({ moment: brief.moment as Moment, today, mins, isTrading: trading, addDays, cal, brief, names, market: [], sectors: [], futures: [], watch: [],
    chart: null, yieldWeeks: [{ week: '2026-10-26', fri: '2026-10-30', calls_sold: 3000, calls_back: 800, puts_sold: 900, puts_back: 100 }],
    payback: null, history: null, earnings: [], macro: [], divs: DIVS, trades: [], orders: ORDERS, aftershock: null, baseNow: BASE, baseAt: () => BASE });
  return { brief: brief as Row, full, open, fails: checkInvariants({ brief, full, open, inputs: {}, orders: ORDERS }) };
}
const words = (x: unknown) => JSON.stringify(x);

Deno.test('Holiday · the clock: a closed weekday is a day off; futures only the evening before a session', () => {
  assertEquals(momentOf('Thu', 11 * 60 + 20, 960, true, true), 'weekend');
  assertEquals(momentOf('Thu', 19 * 60, 960, true, true), 'futures');
  assertEquals(momentOf('Wed', 21 * 60, 960, false, false), 'weekend');   // the night before Thanksgiving
  assertEquals(momentOf('Sun', 19 * 60, 960, false, false), 'weekend');   // Sunday before a Monday holiday
});
Deno.test('Holiday · mid-week (Thanksgiving): markets closed, Friday still live, "so far", opens Friday', () => {
  const p = holidayPage('2026-10-29', 'Thu', 11 * 60 + 20, ['2026-10-29'], '2026-10-30');
  assertEquals(p.brief.moment, 'weekend');
  assertEquals(p.brief.friday, '2026-10-30');
  assertEquals(p.brief.weekend, false);
  assertEquals(p.brief.position.subtitle, 'Closed today · by Friday’s close');
  assertEquals(p.full.dayCaption.text, 'Markets closed · Opens Friday at 9:30 AM');
  assertEquals(p.full.alert?.kind, 'holiday');
  assert(p.full.alert?.today, 'the Holiday card is about today');
  assert(!words(p.full).includes('Monday'), 'nothing says Monday mid-week');
  assert((p.full.sections as Row[]).some((s) => s.kicker === 'Coming up') && !(p.full.sections as Row[]).some((s) => s.kicker === 'Next week'));
  assertEquals(p.fails.length, 0, show(p.fails));
});
Deno.test('Holiday · Monday: last week in review, sales come Tuesday', () => {
  const p = holidayPage('2026-10-26', 'Mon', 11 * 60 + 20, ['2026-10-26'], null);
  assertEquals(p.brief.moment, 'weekend');
  assertEquals(p.brief.friday, '2026-10-30');
  assertEquals(p.full.dayCaption.text, 'Markets closed · Opens Tuesday at 9:30 AM');
  assert(!words(p.full.lede).includes('Monday'), words(p.full.lede));
  assertEquals(p.fails.length, 0, show(p.fails));
});
Deno.test('Holiday · Good Friday: the week ended Thursday, the card is about next Friday', () => {
  const thu = LEGS.map((l) => (l.expiry === '2026-10-30' ? { ...l, expiry: '2026-10-29' } : l));
  const p = holidayPage('2026-10-30', 'Fri', 11 * 60 + 20, ['2026-10-30'], null, thu);
  assertEquals(p.brief.moment, 'weekend');
  assertEquals(p.brief.nextFriday, true);
  assertEquals(p.brief.friday, '2026-11-06');
  assert(String(p.brief.position.subtitle).startsWith('Calls ended Thursday'), p.brief.position.subtitle);
  assert(p.full.alert?.kind === 'holiday' && p.full.alert?.today, 'today’s Holiday card');
  assertEquals(p.full.dayCaption.text, 'Markets closed · Opens Monday at 9:30 AM');
  assertEquals(p.fails.length, 0, show(p.fails));
});

// ── No IV anywhere (Nik, 8 Nov 2026): never a made-up priced move ──
function ivBook(extraLegs: BriefLeg[], extraShares: [string, number][]) {
  const shares = new Map([...SHARES, ...extraShares]), spot = new Map([...SPOT, ['PEP', 141.2]]), avg = new Map([...AVG, ['PEP', 150]]);
  const closes = [...CLOSES, ...['2026-10-23', '2026-10-26'].map((date) => ({ ticker: 'PEP', date, close_price: 140.6 }))];
  const { brief } = buildBrief({ today: '2026-10-27', wd: 'Tue', mins: 680, isTrading, addDays, cal: [], legs: [...LEGS, ...extraLegs],
    isLeap: (l) => l.expiry >= '2027-12-01', shares, shareAvg: avg, spot, closes, chain: [], divRows: DIVS, strategies: {} });
  return brief as Row;
}
const pepRow = (b: Row) => (b.position.rows as Row[]).find((r) => r.id === 'PEP')!;
Deno.test('No IV · shares only: "No option prices yet", no priced move, never short or thin', () => {
  const b = ivBook([], [['PEP', 800]]);
  const r = pepRow(b);
  assertEquals(r.line, 'No option prices yet');
  assertEquals(r.at, '');
  assertEquals(r.st, 0);
  assert(String(r.right).startsWith('Long 800'), r.right);
  assert(String(b.position.count).includes('past') || String(b.position.count).includes('long'), 'count still reads');
});
Deno.test('No IV · an option with an IBKR mark: the IV its price implies, a normal row', () => {
  const b = ivBook([leg('PEP', 'call', 'sold', 145, '2026-10-30', 8, 0.7, 0.51, NaN)], [['PEP', 800]]);
  const r = pepRow(b);
  assert(r.line !== 'No option prices yet', r.line);
  assert(String(r.at).startsWith('at ↑'), r.at);
});
Deno.test('No IV · an option with no IV and no mark: no makes-the-most line for the book', () => {
  const b = ivBook([{ ...leg('PEP', 'call', 'sold', 145, '2026-10-30', 8, 0.7, 0, NaN), mark: null as unknown as number }], [['PEP', 800]]);
  assertEquals(pepRow(b).line, 'No option prices yet');
  const s = (b.position.sentence as Row[]).map((x) => x.t).join('');
  assert(!/makes the most/.test(s), s);
  assertEquals(b.position.shortAt ?? null, null);
});
