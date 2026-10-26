/*
 * gamma.ts · dealer gamma from the tape (handoff 32, 25 Oct 2026). The walls the Gamma page shows, weighted
 * by what dealers actually hold (tape.ts) rather than the open-interest model's guess, with a label and a
 * confidence for each. Kept apart from Theta and Supabase so it can be tested.
 *
 * Per contract: dealer gamma in dollars per 1% move = gamma x dealer position x 100 x spot² x 0.01; long
 * (dealers own it) is positive. Summed by strike. A wall is one of the three strikes with the most dealer
 * gamma either way on its side of the price.
 *   Ceiling      above the price, dealers long gamma: they sell into a rally, so it tends to stall.
 *   Floor        below the price, dealers long gamma: they buy a drop, so it tends to stall.
 *   Accelerator  either side, dealers short gamma: they chase the move, so it speeds up through.
 *   Unclear      gamma too small for the name (under 15% of its biggest wall), or too little of the
 *                strike's own volume classified (under 40%). The day's coverage is shown, not gated (26 Oct).
 * The open-interest model reads every wall above the price as a Ceiling and every one below as an
 * Accelerator; the page says so only where it disagrees.
 * Confidence 1 to 3: see dealerWalls (four factors since 26 Oct 2026). Before, three parts: the share of the strike's position the tape
 * explains (rather than the open-interest seed), the wall's size against the biggest, and how many sessions
 * the label has held. 5 or 6 points high, 3 or 4 medium, otherwise low.
 */
import { bsGamma, MULT, zeroGamma } from './walls.ts';

export type Label = 'ceiling' | 'floor' | 'accelerator' | 'unclear';
export interface DContract {
  exp: string; k: number; cp: 'C' | 'P'; T: number; iv: number;
  pos: number; oi: number; seed: number; tapeVol: number; classifiedVol: number;
  /** Customers' readable buys and sells since tracking began (contracts, weighted by how clear each print was). */
  buy?: number; sell?: number;
}
export interface DStrike {
  k: number; gex: number; oiGex: number; explained: number; classified: number | null; byExp: Record<string, number>;
  /** Readable volume, open interest, and the readable buys and sells, summed over the strike. */
  readable?: number; oi?: number; buy?: number; sell?: number;
}
export interface DWall {
  side: 'call' | 'put'; rank: number; k: number; gex: number; oiGex: number; label: Label; conf: 1 | 2 | 3;
  oiLabel: 'ceiling' | 'accelerator'; explained: number; held: number; byExp: Record<string, number>;
  /** The four confidence factors (26 Oct 2026): readable share, one-sidedness, size against a normal wall, days held. */
  f?: { read: number | null; one: number | null; size: number | null; days: number };
}

const gammaOf = (S: number, c: DContract, r = 0.04) => bsGamma(S, c.k, c.T, c.iv, r, 0);

/** Dealer and open-interest gamma by strike at `spot`. */
export function dealerStrikes(cs: DContract[], spot: number): DStrike[] {
  const by = new Map<number, DStrike & { tape: number; cls: number; seed: number }>();
  for (const c of cs) {
    const g = gammaOf(spot, c) * MULT * spot * spot * 0.01;
    const row = by.get(c.k) ?? { k: c.k, gex: 0, oiGex: 0, explained: 0, classified: null, byExp: {}, tape: 0, cls: 0, seed: 0, oi: 0, buy: 0, sell: 0 };
    const dg = g * c.pos;
    row.gex += dg;
    row.oiGex += g * (c.cp === 'C' ? c.oi : -c.oi);
    row.byExp[c.exp] = (row.byExp[c.exp] ?? 0) + dg;
    row.tape += c.tapeVol; row.cls += c.classifiedVol; row.seed += Math.abs(c.seed);
    row.oi = (row.oi ?? 0) + c.oi; row.buy = (row.buy ?? 0) + (c.buy ?? 0); row.sell = (row.sell ?? 0) + (c.sell ?? 0);
    by.set(c.k, row);
  }
  return [...by.values()].map(({ tape, cls, seed, ...r }) => ({ ...r, readable: cls,
    explained: tape + seed > 0 ? cls / (tape + seed) : 0, classified: tape > 0 ? cls / tape : null }))
    .sort((a, b) => a.k - b.k);
}

/** Up to three walls each side of the price, labelled, with a confidence of 1 to 3 dots.
    LABEL (Nik, 26 Oct 2026): each wall is judged on its own strike. Unclear when the wall is small (under 15% of
    the view's biggest), when under 40% of the strike's own trading could be read, or when what was read since
    tracking began is under 10% of the strike's open interest (a few clear trades on a big strike mean nothing).
    DOTS from four factors, each strong, neither, or weak:
      readable share   strong 70%+          weak under 50%
      one-sidedness    strong 60%+ one way  weak under 30%   (|sold - bought| / (sold + bought), readable trades)
      size             strong 1.5x+         weak under 0.75x (against a normal wall for the name: `normal`)
      days held        strong 3+            weak new today
    High: no weak and at least three strong. Low: two or more weak. Medium otherwise. A day with under 50%
    coverage caps every wall at Medium (the screen says the day was hard to read). */
export function dealerWalls(rows: DStrike[], spot: number,
  o: { coverage: number | null; held?: (k: number, label: Label) => number; normal?: number | null }): DWall[] {
  const pick = (above: boolean) => rows.filter((r) => (above ? r.k > spot : r.k < spot) && r.gex !== 0)
    .sort((a, b) => Math.abs(b.gex) - Math.abs(a.gex)).slice(0, 3);
  const up = pick(true), dn = pick(false);
  const big = Math.max(0, ...[...up, ...dn].map((r) => Math.abs(r.gex)));
  const normal = o.normal && o.normal > 0 ? o.normal : median([...up, ...dn].map((r) => Math.abs(r.gex)));
  const hardDay = o.coverage != null && o.coverage < 0.5;
  const wall = (r: DStrike, above: boolean, rank: number): DWall => {
    const size = big > 0 ? Math.abs(r.gex) / big : 0;
    const thin = r.classified != null && r.classified < 0.4;
    const tooLittle = r.oi != null && r.readable != null && r.oi > 0 && r.readable < 0.1 * r.oi;
    const label: Label = size < 0.15 || thin || tooLittle ? 'unclear' : r.gex > 0 ? (above ? 'ceiling' : 'floor') : 'accelerator';
    const held = o.held ? o.held(r.k, label) : 1;
    const gross = (r.buy ?? 0) + (r.sell ?? 0);
    const f = { read: r.classified, one: gross > 0 ? Math.abs((r.sell ?? 0) - (r.buy ?? 0)) / gross : null,
      size: normal > 0 ? Math.abs(r.gex) / normal : null, days: held };
    const conf = dots(f, hardDay);
    return { side: above ? 'call' : 'put', rank, k: r.k, gex: Math.round(r.gex), oiGex: Math.round(r.oiGex), label,
      conf, oiLabel: above ? 'ceiling' : 'accelerator', explained: +r.explained.toFixed(3), held,
      f: { read: f.read == null ? null : +f.read.toFixed(2), one: f.one == null ? null : +f.one.toFixed(2),
        size: f.size == null ? null : +f.size.toFixed(2), days: f.days },
      byExp: Object.fromEntries(Object.entries(r.byExp).map(([e, v]) => [e, Math.round(v)])) };
  };
  return [...up.map((r, i) => wall(r, true, i + 1)), ...dn.map((r, i) => wall(r, false, i + 1))];
}

/** The dots from the four factors (see dealerWalls). A factor with no data counts as neither. */
export function dots(f: { read: number | null; one: number | null; size: number | null; days: number }, hardDay = false): 1 | 2 | 3 {
  const grade = (v: number | null, strong: number, weak: number) => v == null ? 0 : v >= strong ? 1 : v < weak ? -1 : 0;
  const g = [grade(f.read, 0.7, 0.5), grade(f.one, 0.6, 0.3), grade(f.size, 1.5, 0.75), f.days >= 3 ? 1 : f.days <= 1 ? -1 : 0];
  const strong = g.filter((x) => x > 0).length, weak = g.filter((x) => x < 0).length;
  const c = weak >= 2 ? 1 : weak === 0 && strong >= 3 ? 3 : 2;
  return (hardDay && c === 3 ? 2 : c) as 1 | 2 | 3;
}

export function median(xs: number[]): number {
  const a = xs.filter((x) => x > 0).sort((p, q) => p - q);
  return a.length ? (a.length % 2 ? a[(a.length - 1) / 2] : (a[a.length / 2 - 1] + a[a.length / 2]) / 2) : 0;
}

/** Where net dealer gamma, every contract re-priced, crosses zero (walls.ts zeroGamma with dealer weights). */
export function dealerFlip(cs: DContract[], spot: number): number | null {
  return zeroGamma(cs.map((c) => ({ k: c.k, T: c.T, iv: c.iv, exp: c.exp, coi: c.cp === 'C' ? c.pos : 0, poi: c.cp === 'P' ? -c.pos : 0 })), spot);
}

/** Net dealer gamma at a price (every contract re-priced there), dollars per 1% move. */
export function netAt(cs: DContract[], S: number): number {
  return cs.reduce((a, c) => a + gammaOf(S, c) * c.pos, 0) * MULT * S * S * 0.01;
}

/** Calmer while dealers are long gamma at the price; otherwise the side where they are short decides. */
export function regime(cs: DContract[], spot: number): 'calmer' | 'upside amplified' | 'downside amplified' {
  if (netAt(cs, spot) >= 0) return 'calmer';
  return netAt(cs, spot * 1.02) < 0 ? 'upside amplified' : 'downside amplified';
}

/** The weighted centre of the walls (gamma-weighted strike), for the drift score. */
export function centre(walls: { k: number; gex: number }[]): number | null {
  const w = walls.reduce((a, x) => a + Math.abs(x.gex), 0);
  return w > 0 ? walls.reduce((a, x) => a + x.k * Math.abs(x.gex), 0) / w : null;
}

/* ── How labels held (handoff 32, brief 15; Nik's rule 7: show it once there are 45 sessions) ──
   For each label, how often price respected or broke the wall when it got close, against strikes the same
   distance away on every other session (no wall needed). A wall from a session's view is touched when a high
   (a wall above) or a low (below) in the next 5 sessions comes within 0.3% of it. From the touch day on, a close
   through it by 0.5% within 2 more sessions is a BREAK; otherwise a close back away (beyond the 0.3% band) is a
   RESPECT; neither, it is left out. A wall seen again on later days counts once per touch day. Ceilings and
   Floors score how often they held; Accelerators how often they broke. Unclear walls are not scored. */
export interface TrackView { day: string; spot: number; walls: { side: string; k: number; label: string }[] }
export interface Bar { d: string; h: number; l: number; c: number }
export interface TrackRow { kind: 'ceiling' | 'floor' | 'accelerator'; label: string; rate: number; base: number; touches: number }

const TOUCH = 0.003, THROUGH = 0.005, AHEAD = 5, AFTER = 2;

/** One level from a session: touched within 5 sessions, and then broke or held. null when not touched, or when
    too few sessions follow to tell. */
export function outcome(bars: Bar[], from: number, k: number, above: boolean): { touch: number; broke: boolean; held: boolean } | null {
  for (let j = from; j < Math.min(bars.length, from + AHEAD); j++) {
    const b = bars[j];
    if (!(above ? b.h >= k * (1 - TOUCH) : b.l <= k * (1 + TOUCH))) continue;
    // A break counts the day it happens; a hold needs the 2 sessions after the touch to have closed.
    const cs = bars.slice(j, j + AFTER + 1).map((x) => x.c);
    const broke = cs.some((c) => (above ? c >= k * (1 + THROUGH) : c <= k * (1 - THROUGH)));
    if (!broke && j + AFTER >= bars.length) return null;
    const held = !broke && cs.some((c) => (above ? c < k * (1 - TOUCH) : c > k * (1 + TOUCH)));
    return { touch: j, broke, held };
  }
  return null;
}

export function track(views: TrackView[], bars: Bar[]): TrackRow[] {
  const at = (day: string) => bars.findIndex((b) => b.d > day);
  const groups: Record<TrackRow['kind'], { n: number; hit: number; bn: number; bhit: number }> = {
    ceiling: { n: 0, hit: 0, bn: 0, bhit: 0 }, floor: { n: 0, hit: 0, bn: 0, bhit: 0 }, accelerator: { n: 0, hit: 0, bn: 0, bhit: 0 } };
  const seen = new Set<string>();
  for (const v of views) {
    const from = at(v.day);
    if (from < 0 || !(v.spot > 0)) continue;
    for (const w of v.walls) {
      if (w.label !== 'ceiling' && w.label !== 'floor' && w.label !== 'accelerator') continue;
      const above = w.k > v.spot, o = outcome(bars, from, w.k, above);
      if (!o || (!o.broke && !o.held)) continue;
      const key = `${w.label}|${w.k}|${o.touch}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const g = groups[w.label as TrackRow['kind']], scoreBreak = w.label === 'accelerator';
      g.n += 1; if (scoreBreak ? o.broke : o.held) g.hit += 1;
      // The baseline: the same distance from the price on every session.
      const dist = w.k / v.spot - 1;
      for (const u of views) {
        const f2 = at(u.day);
        if (f2 < 0 || !(u.spot > 0)) continue;
        const k2 = u.spot * (1 + dist), o2 = outcome(bars, f2, k2, dist > 0);
        if (!o2 || (!o2.broke && !o2.held)) continue;
        g.bn += 1; if (scoreBreak ? o2.broke : o2.held) g.bhit += 1;
      }
    }
  }
  const names = { ceiling: 'Ceilings held', floor: 'Floors held', accelerator: 'Accelerators broke' } as const;
  return (['ceiling', 'floor', 'accelerator'] as const).filter((k) => groups[k].n > 0).map((k) => ({
    kind: k, label: names[k], rate: Math.round(groups[k].hit / groups[k].n * 100),
    base: groups[k].bn ? Math.round(groups[k].bhit / groups[k].bn * 100) : 0, touches: groups[k].n }));
}
