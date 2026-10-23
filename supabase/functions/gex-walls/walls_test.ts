// The gamma-wall maths on a small fixed chain, checked by hand, with no Theta and no network.
// Run: deno test supabase/functions/gex-walls/walls_test.ts
import { bsGamma, buildStrikes, Chain, Contract, contractGex, findWalls, IncompleteChain, isFresh,
  nearest, summaryLine, target, yearsTo, zeroGamma } from './walls.ts';

function eq(a: unknown, b: unknown, msg = '') {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}
function near(a: number, b: number, tol = 1e-6, msg = '') {
  if (!(Math.abs(a - b) <= tol)) throw new Error(`${msg} expected ${b}, got ${a}`);
}
function throws(f: () => unknown, re: RegExp) {
  try { f(); } catch (e) { if (e instanceof IncompleteChain && re.test(e.message)) return; throw e; }
  throw new Error(`expected IncompleteChain matching ${re}`);
}

const NOW = Date.UTC(2026, 9, 22, 20);        // 22 Oct 2026, 4:00 PM New York
const E1 = '2026-11-20', E2 = '2026-12-18';
// Gamma fixed per strike (and per expiry), so every GEX below is gamma x OI x 100 x 100² x 0.01 = gamma x OI x 10,000.
const G: Record<string, Record<number, number>> = { [E1]: { 90: 0.02, 95: 0.04, 100: 0.05, 105: 0.04, 110: 0.02 }, [E2]: { 100: 0.03, 110: 0.03 } };
const gammaFn = (_S: number, K: number, _T: number, _iv: number, exp: string) => G[exp][K];
const c = (exp: string, k: number, right: 'C' | 'P', oi: number, vol = 0, iv: number | null = 0.3): Contract => ({ exp, k, right, iv, oi, vol });

// strike   call OI  put OI  call vol  put vol
//   90       100     2000      0        50
//   95       300     1500     10       900     <- FRESH: 910 > 900
//  100      1000     1000    100       100
//  105      2500      200   1400         0     <- FRESH: 1400 > 1350
//  110      1800       50     20         0
const base: Contract[] = [
  c(E1, 90, 'C', 100), c(E1, 90, 'P', 2000, 50),
  c(E1, 95, 'C', 300, 10), c(E1, 95, 'P', 1500, 900),
  c(E1, 100, 'C', 1000, 100), c(E1, 100, 'P', 1000, 100),
  c(E1, 105, 'C', 2500, 1400), c(E1, 105, 'P', 200),
  c(E1, 110, 'C', 1800, 20), c(E1, 110, 'P', 50),
];
const one: Chain = { ticker: 'TEST', spot: 100, expiries: [E1], contracts: base };

Deno.test('Black-Scholes gamma matches the closed form', () => {
  // S = K = 100, T = 1, vol 20%, r = q = 0: d1 = 0.1, gamma = phi(0.1) / (100 x 0.2)
  near(bsGamma(100, 100, 1, 0.2, 0, 0), 0.3969525474770118 / 20, 1e-12);
  eq(bsGamma(100, 100, 0, 0.2), 0, 'no time left');
});

Deno.test('years to the 4 PM New York close, across the November clock change', () => {
  // 20 Nov is EST: 4 PM = 21:00 UTC, so 29 days and 1 hour after 22 Oct 20:00 UTC.
  near(yearsTo(E1, NOW), (29 * 24 + 1) / (365 * 24), 1e-12);
  near(yearsTo('2026-10-23', NOW), 1 / 365, 1e-12);
});

Deno.test('per-contract GEX: calls plus, puts minus', () => {
  near(contractGex(0.05, 1000, 100, 'C'), 500_000);
  near(contractGex(0.05, 1000, 100, 'P'), -500_000);
});

Deno.test('one expiry: sums, walls, runner-ups, FRESH', () => {
  const b = buildStrikes(one, { nowMs: NOW, gammaFn });
  const by = Object.fromEntries(b.rows.map((r) => [r.k, r]));
  near(by[90].callGex, 20_000); near(by[90].putGex, -400_000); near(by[90].netGex, -380_000);
  near(by[95].callGex, 120_000); near(by[95].putGex, -600_000);
  near(by[100].netGex, 0);
  near(by[105].callGex, 1_000_000); near(by[105].putGex, -80_000); near(by[105].netGex, 920_000);
  near(by[110].netGex, 350_000);
  near(b.rows.reduce((s, r) => s + r.netGex, 0), 410_000, 1e-6, 'total net');
  const w = findWalls(b.rows, 100);
  eq(w.call.map((r) => r.k), [105, 110], 'call wall, runner-up');
  eq(w.put.map((r) => r.k), [95, 90], 'put wall, runner-up');
  eq(b.rows.filter(isFresh).map((r) => r.k), [95, 105], 'FRESH');
});

Deno.test('two expiries add by strike', () => {
  const two: Chain = { ...one, expiries: [E1, E2], contracts: [...base, c(E2, 100, 'P', 400), c(E2, 110, 'C', 1000)] };
  const b = buildStrikes(two, { nowMs: NOW, gammaFn });
  const by = Object.fromEntries(b.rows.map((r) => [r.k, r]));
  near(by[100].putGex, -620_000); near(by[110].callGex, 660_000);
  near(b.rows.reduce((s, r) => s + r.netGex, 0), 590_000);
  eq(findWalls(b.rows, 100).call.map((r) => r.k), [105, 110]);
});

Deno.test('a strike missing one IV borrows the other side; the out-of-the-money side wins', () => {
  // 105 call has no IV: its put's IV is used, so the GEX is unchanged.
  const cs = base.map((x) => (x.k === 105 && x.right === 'C' ? { ...x, iv: null } : x));
  const seen: number[] = [];
  buildStrikes({ ...one, contracts: cs }, { nowMs: NOW, gammaFn: (S, K, T, iv, e) => { if (K === 105) seen.push(iv); return gammaFn(S, K, T, iv, e); } });
  eq(seen, [0.3]);
  // Both sides present: above spot the call's IV is used, below spot the put's.
  const ivs: Record<number, number> = {};
  const marked = base.map((x) => ({ ...x, iv: x.right === 'C' ? 0.31 : 0.29 }));
  buildStrikes({ ...one, contracts: marked }, { nowMs: NOW, gammaFn: (_S, K, _T, iv) => { ivs[K] = iv; return 0.01; } });
  eq([ivs[90], ivs[95], ivs[100], ivs[105], ivs[110]], [0.29, 0.29, 0.31, 0.31, 0.31]);
});

Deno.test('fails loudly: most open interest near spot unquoted, or an expiry with no quotes', () => {
  // 1 SD here is 100 x 0.3 x sqrt(29/365) = 8.5, so 95, 100 and 105 are near spot: all three unquoted.
  const cs = base.map((x) => ([95, 100, 105].includes(x.k) ? { ...x, iv: null } : x));
  throws(() => buildStrikes({ ...one, contracts: cs }, { nowMs: NOW, gammaFn }), /100% of the open interest within 1 SD of spot has no usable quote/);
  // One near strike unquoted is 1800 of 6500 near open interest (28%): also too much to fill quietly.
  throws(() => buildStrikes({ ...one, contracts: base.map((x) => (x.k === 95 ? { ...x, iv: null } : x)) }, { nowMs: NOW, gammaFn }), /28% of the open interest/);
  throws(() => buildStrikes({ ...one, expiries: [E1, E2] }, { nowMs: NOW, gammaFn }), /2026-12-18 returned no quotes/);
});

Deno.test('an unquoted strike away from spot takes its vol from the neighbours and is reported', () => {
  // 110 is 1.2 SD out: filled flat from 105's call (the last quoted strike above). 200 too.
  const cs = [...base.map((x) => (x.k === 110 ? { ...x, iv: null } : x.k === 105 && x.right === 'C' ? { ...x, iv: 0.25 } : x)),
    c(E1, 200, 'C', 5000, 0, null), c(E1, 200, 'P', 0, 0, null)];
  const ivs: Record<number, number> = {};
  const b = buildStrikes({ ...one, contracts: cs }, { nowMs: NOW, gammaFn: (_S, K, _T, iv) => { ivs[K] = iv; return 0.01; } });
  eq([ivs[110], ivs[200]], [0.25, 0.25]);
  eq(b.filledOi, 1850 + 5000);
  // Between two quoted strikes it is linear: 90 at 40%, 100 at 20%, so an unquoted 95 sits at 30%.
  const mid = base.map((x) => (x.k === 95 ? { ...x, iv: null, oi: 1 } : x.k === 90 ? { ...x, iv: 0.4 } : x.k === 100 ? { ...x, iv: 0.2 } : x));
  buildStrikes({ ...one, contracts: mid }, { nowMs: NOW, gammaFn: (_S, K, _T, iv) => { ivs[K] = iv; return 0.01; } });
  near(ivs[95], 0.3, 1e-12);
});

Deno.test('target strikes against the walls', () => {
  const b = buildStrikes(one, { nowMs: NOW, gammaFn }), w = findWalls(b.rows, 100);
  eq(target(b.rows, 100, 5, w), { call: { k: 105, wall: 105, vs: 'on' }, put: { k: 95, wall: 95, vs: 'on' } });
  eq(target(b.rows, 100, 8, w), { call: { k: 110, wall: 105, vs: 'above' }, put: { k: 90, wall: 95, vs: 'below' } });
  eq(target(b.rows, 100, 2, w), { call: { k: 105, wall: 105, vs: 'on' }, put: { k: 95, wall: 95, vs: 'on' } });
});

Deno.test('the 15 nearest strikes, ascending, and the summary line', () => {
  const b = buildStrikes(one, { nowMs: NOW, gammaFn });
  eq(nearest(b.rows, 101, 3).map((r) => r.k), [95, 100, 105]);
  const w = findWalls(b.rows, 100);
  eq(summaryLine('2026-10-22', 'TEST', 100, 410_000, 95, w),
    '2026-10-22 TEST spot 100.00 · net GEX +$410K · flip 95.00 · call wall 105 (2nd 110) · put wall 95 (2nd 90)');
});

Deno.test('implied vol round-trips through the Black-Scholes price', async () => {
  const { bsPrice, solveIv } = await import('./walls.ts');
  for (const [S, K, T, v, call] of [[100, 100, 30 / 365, 0.3, true], [100, 90, 30 / 365, 0.45, false], [376, 362.5, 0.72 / 365, 0.6, false]] as const) {
    near(solveIv(bsPrice(S, K, T, v, call), S, K, T, call)!, v, 1e-6, `${S}/${K}/${call ? 'C' : 'P'}`);
  }
  eq(solveIv(5, 100, 90, 30 / 365, true), null, 'below intrinsic');
});

Deno.test('the stock price the quotes imply: call - put + K e^(-rT) at the closest pair', async () => {
  const { bsPrice, impliedSpot } = await import('./walls.ts');
  const T = 7 / 365, S = 376;
  const pairs = [360, 375, 380].map((k) => ({ k, c: bsPrice(S, k, T, 0.5, true), p: bsPrice(S, k, T, 0.5, false) }));
  near(impliedSpot(pairs, T)!, S, 1e-6);
  eq(impliedSpot([{ k: 375, c: 3, p: 0 }], T), null, 'needs both sides');
});

Deno.test('the flip: where the re-priced chain nets to zero', () => {
  // A tent-shaped gamma (1 at the strike, 0 twenty dollars away): 1000 calls at 100 and 1000 puts at 90
  // net to zero where both tents are equal, at 95. S² multiplies both sides, so it does not move it.
  const tent = (S: number, K: number) => Math.max(0, 1 - Math.abs(S - K) / 20);
  const legs = [{ k: 100, T: 0.1, iv: 0.3, coi: 1000, poi: 0, exp: E1 }, { k: 90, T: 0.1, iv: 0.3, coi: 0, poi: 1000, exp: E1 }];
  // Interpolated between 0.25% price steps, so within a cent, not exact.
  near(zeroGamma(legs, 97, { gammaFn: (S, K) => tent(S, K) })!, 95, 0.01);
  eq(zeroGamma([legs[0]], 97, { gammaFn: (S, K) => tent(S, K) }), null, 'all calls: never crosses');
});
