// The tape rules on hand-made prints. Run: deno test supabase/functions/gex-walls/tape_test.ts
import { aggregate, csvPrints, kindOf, medianSize, side, step } from './tape.ts';

function near(a: number, b: number, tol = 1e-9, msg = '') { if (!(Math.abs(a - b) <= tol)) throw new Error(`${msg} expected ${b}, got ${a}`); }
function eq(a: unknown, b: unknown, msg = '') { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); }

Deno.test('print types from the trade condition', () => {
  eq([18, 95, 125, 129, 130, 134, 136, 135, 138, 143, 144, 7].map(kindOf),
    ['single', 'single', 'auction', 'auction', 'multi', 'multi', 'multi', 'tied', 'tied', 'tied', 'multi', 'other']);
});

Deno.test('the customer side: ask bought, bid sold, between in part, mid none', () => {
  near(side(1.10, 1.00, 1.10, 'single'), 1); near(side(1.15, 1.00, 1.10, 'single'), 1, 1e-9, 'over the ask');
  near(side(1.00, 1.00, 1.10, 'single'), -1); near(side(1.05, 1.00, 1.10, 'single'), 0, 1e-9, 'mid');
  near(side(1.075, 1.00, 1.10, 'single'), 0.5);
  near(side(1.075, 1.00, 1.10, 'multi'), 0.5, 1e-9, 'a spread leg at half counts');
  near(side(1.06, 1.00, 1.10, 'multi'), 0, 1e-9, 'a spread leg near the mid is unclassified');
  near(side(1.05, 0, 1.10, 'single'), 0, 1e-9, 'no bid: unclassified');
});

Deno.test('a day of prints per contract and in total', () => {
  const r = aggregate([
    { k: 100, cp: 'C', price: 2.0, bid: 1.9, ask: 2.0, size: 10, cond: 18 },   // bought 10
    { k: 100, cp: 'C', price: 1.9, bid: 1.9, ask: 2.0, size: 4, cond: 18 },    // sold 4
    { k: 100, cp: 'C', price: 1.95, bid: 1.9, ask: 2.0, size: 6, cond: 130 },  // mid spread leg: unclassified
    { k: 90, cp: 'P', price: 0.5, bid: 0.5, ask: 0.6, size: 30, cond: 18 },    // sold 30
    { k: 300, cp: 'P', price: 0.5, bid: 0.4, ask: 0.5, size: 1, cond: 18 },    // out of the band: totals only
  ], [50, 150]);
  eq(r.contracts.map((c) => [c.k, c.cp, c.vol, c.buy, c.sell, c.uncl]), [[100, 'C', 20, 10, 4, 6], [90, 'P', 30, 0, 30, 0]]);
  eq([r.day.vol, r.day.classified, r.day.trades, r.day.small, r.day.callVol, r.day.putVol], [51, 45, 5, 4, 20, 31]);
  eq(r.day.byKind, { single: 45, multi: 6, tied: 0, auction: 0, other: 0 });
  eq(medianSize(r.day.sizes), 6);
});

Deno.test('the running dealer position stays inside open interest', () => {
  near(step(0, { buy: 10, sell: 4 }, 100), -6, 1e-9, 'customers bought 6 net: dealers short 6');
  near(step(-6, { buy: 0, sell: 50 }, 30), 30, 1e-9, 'capped at OI');
  near(step(5, { buy: 0, sell: 0 }, null), 5);
});

Deno.test('Theta CSV, a line at a time', async () => {
  const csv = 'symbol,expiration,strike,right,trade_timestamp,quote_timestamp,sequence,ext_condition1,ext_condition2,ext_condition3,ext_condition4,condition,size,exchange,price,bid_size,bid_exchange,bid,bid_condition,ask_size,ask_exchange,ask,ask_condition\n'
    + '"TSLA","2026-10-30",362.500,"CALL",2026-10-23T09:30:23.418,2026-10-23T09:30:23.417,9693443,255,255,255,255,95,1,7,13.80,1,7,13.75,50,115,65,15.20,50\n'
    + '"TSLA","2026-10-30",360.000,"PUT",2026-10-23T09:31:00.000,2026-10-23T09:31:00.000,9693444,255,255,255,255,18,3,7,9.10,1,7,9.10,50,5,65,9.40,50\n';
  const body = new Blob([csv]).stream();
  const out = []; for await (const p of csvPrints(body)) out.push(p);
  eq(out, [{ k: 362.5, cp: 'C', price: 13.8, bid: 13.75, ask: 15.2, size: 1, cond: 95 }, { k: 360, cp: 'P', price: 9.1, bid: 9.1, ask: 9.4, size: 3, cond: 18 }]);
});
