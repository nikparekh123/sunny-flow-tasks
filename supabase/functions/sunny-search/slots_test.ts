import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { fmt, Slots } from './slots.ts';

Deno.test('numbers are named, small counts stay plain', () => {
  const s = new Slots();
  assertEquals(s.tag({ price: 99.63, n: 15, left: 2822, rows: [{ pct: -2.1 }] }), { price: 'r1=99.63', n: 15, left: 'r2=2822', rows: [{ pct: 'r3=-2.1' }] });
});

Deno.test('small money is named, small counts are not', () => {
  const s = new Slots();
  assertEquals(s.tag({ n: 9, days_left: 3, theta_per_day_usd: -13, strikes: [15, 17.5], captured_pct: 12 }),
    { n: 9, days_left: 3, theta_per_day_usd: 'r1=-13', strikes: ['r2=15', 'r3=17.5'], captured_pct: 'r4=12' });
});

Deno.test('slots are written out in the design formats, signs dropped', () => {
  const s = new Slots();
  s.tag({ a: 99.63, b: -2.1, c: 5550, d: 2731, e: 0.62, f: 46300000000, g: 18.04, h: 104, i: 0.19 });
  const bad: string[] = [];
  assertEquals(s.fill('BABA fell {r:[r2|%]} to {b:[r1|$2]}.', bad), 'BABA fell {r:2.1%} to {b:$99.63}.');
  assertEquals(s.fill('kept [r3-r4|$] of [r3|$]', bad), 'kept $2,819 of $5,550');
  assertEquals(s.fill('Δ [r5|d] · [r6|$k] · [r7|x] · [r8|k] calls · [r9*100|%0]', bad), 'Δ .62 · $46.3B · 18.0x · 104 calls · 19%');
  assertEquals(bad, []);
});

Deno.test('a slot naming nothing, or a figure typed into a slot, is caught', () => {
  const s = new Slots();
  s.tag({ a: 99.63 });
  const bad: string[] = [];
  assertEquals(s.fill('at [r9|$2]', bad), 'at ');
  assertThrows(() => s.value('r1*0+9250'));
  assertEquals(bad.length, 1);
});

Deno.test('short money', () => {
  assertEquals(fmt(3803.4, '$k'), '$3.8K');
  assertEquals(fmt(37.5, 'k'), '37.50');
  assertEquals(fmt(104, 'k'), '104');
  assertEquals(fmt(226010, '$k'), '$226K');
  assertEquals(fmt(56900000, '$k'), '$56.9M');
});
