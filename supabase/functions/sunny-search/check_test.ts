import { assertEquals } from 'jsr:@std/assert@1';
import { checkAnswer, figures } from './check.ts';

const payback = { leaps_base: 225705, made: 40920, pace_last_4_weeks_per_week: 5894 };
const yieldWeek = { calls_sold: 16550, puts_sold: 965, calls_closing: 3111, puts_closing: 1654, hedges: 1339, net: 11411, pct: 5.06 };

Deno.test('figures read from the data pass, rounded as shown', () => {
  const r = checkAnswer('You have $3,804 of time value left; $3.8K in all.', [{ time_value_sold: 3803.42 }]);
  assertEquals(r, { ok: true, checked: 2, unverified: [] });
});

Deno.test('a figure worked out in one step passes, and so does one worked out from it', () => {
  const r = checkAnswer('About $184,785 is left, which takes about 31 weeks at $5,894 a week.', [payback]);
  assertEquals(r.ok, true);
});

Deno.test('sums of two figures and percents pass', () => {
  assertEquals(checkAnswer('$17,515 sold, less $4,765 to close.', [yieldWeek]).ok, true);
  assertEquals(checkAnswer('About 1.8% of its price.', [{ premium: 0.67, price: 37.57 }]).ok, true);
});

Deno.test('a figure that is not in the data and cannot be worked out fails', () => {
  const r = checkAnswer('A 5% drop would cost about $9,250.', [{ net_delta_shares: 4867, pnl_usd: -17441 }], 'What if the market falls 5%?');
  assertEquals(r.ok, false);
  assertEquals(r.unverified, ['$9,250']);
});

Deno.test('dates, years and small counts are left alone', () => {
  assertEquals(figures('Expires 30 Oct and 21 Jan 2028; also 2027-01-15.').length, 0);
  assertEquals(checkAnswer('6 names, 3 days left.', [{}]).ok, true);
});

Deno.test('signs are not held against an answer that words them', () => {
  assertEquals(checkAnswer('You would lose about $17,441.', [{ pnl_usd: -17441 }]).ok, true);
});
