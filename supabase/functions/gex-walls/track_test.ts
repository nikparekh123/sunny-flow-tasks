import { assertEquals } from 'jsr:@std/assert';
import { outcome, track } from './gamma.ts';

const bar = (d: string, h: number, l: number, c: number) => ({ d, h, l, c });

Deno.test('a ceiling touched and held, then one broken', () => {
  const bars = [bar('2026-10-01', 101, 99, 100), bar('2026-10-02', 104.8, 101, 103), bar('2026-10-05', 104, 101, 102),
    bar('2026-10-06', 103, 100, 101), bar('2026-10-07', 106, 103, 105.8), bar('2026-10-08', 107, 105, 106)];
  // 105 above a 100 spot: 104.8 is within 0.3%; closes 103, 102, 101 stay away -> held.
  assertEquals(outcome(bars, 1, 105, true), { touch: 1, broke: false, held: true });
  // 105.2: touched on Oct 7 (106), close 105.8 is through 105.2 by 0.5%? 105.2 * 1.005 = 105.73 -> broke.
  assertEquals(outcome(bars, 3, 105.2, true), { touch: 4, broke: true, held: false });
  // Not touched within 5 sessions.
  assertEquals(outcome(bars, 0, 120, true), null);
});

Deno.test('track pools touches and dedupes a wall seen on two days', () => {
  const bars = [bar('2026-10-01', 101, 99, 100), bar('2026-10-02', 104.8, 101, 103), bar('2026-10-05', 104, 101, 102),
    bar('2026-10-06', 103, 100, 101), bar('2026-10-07', 102, 99, 100), bar('2026-10-08', 101, 99, 100)];
  const v = (day: string) => ({ day, spot: 100, walls: [{ side: 'call', k: 105, label: 'ceiling' }] });
  const rows = track([v('2026-09-30'), v('2026-10-01')], bars);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].kind, 'ceiling');
  assertEquals(rows[0].touches, 1);
  assertEquals(rows[0].rate, 100);
});

import { dots } from './gamma.ts';
Deno.test('dots: high needs no weak and three strong; two weak is low; a hard day caps at medium', () => {
  assertEquals(dots({ read: 0.75, one: 0.65, size: 1.6, days: 4 }), 3);
  assertEquals(dots({ read: 0.75, one: 0.65, size: 1.6, days: 4 }, true), 2);
  assertEquals(dots({ read: 0.75, one: 0.2, size: 1.6, days: 4 }), 2);          // one weak
  assertEquals(dots({ read: 0.45, one: 0.2, size: 1.6, days: 4 }), 1);          // two weak
  assertEquals(dots({ read: 0.6, one: 0.4, size: 1.0, days: 2 }), 2);           // all neither
  assertEquals(dots({ read: null, one: null, size: null, days: 1 }), 2);        // only new today weak
});
