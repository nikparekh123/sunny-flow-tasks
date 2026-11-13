// Intelligence on the web Positions page (handoff 2026-11-13-positions, README §3.9): what the sunny-sd reply holds,
// what the user picked (per book and name, kept for the session), and the pieces every part of the window reads, all
// from positions-engine.ts so the web and the phone say the same numbers.
//
// The reply: sunny-sd (the SD calculator's server, sd-engine.ts calc()). The server builder adds OPTIONAL fields
// (tech, day, closes, events, exps[i].ivK, exps[i].gamma, sold[i].z0 / fill); a lane whose data is absent shows one
// quiet line, never a stand-in. Gamma walls fall back to the walls Home already sends per expiry (gex_walls, the
// same source), without the confidence dots.
// No em dashes in any words here.
import { useCallback, useMemo, useSyncExternalStore } from 'react';
import {
  coverCheck, expiryKind, ivTone, lane, levelState, moveOf, openExpiry, stepOf, theRead,
  type Close, type Day, type Lane, type LevelState, type Levels, type Move, type ShortLeg,
} from '../../../supabase/functions/_shared/positions-engine.ts';
import type { ChainW } from './model';

export interface SdRow { k: number; K: number; pct: number; kA: number; pr: number; be: number; itm: number; est: boolean; liq: boolean; won: number | null }
export interface SdSig { key: string; k: string; v: string; vTone: 'ink' | 'green' | 'red' | 'or'; tag: string; tagTone: 'mu' | 'or'; s: string; fx: [string, string][] }
export interface GammaWall { K: number; kind: 'ceiling' | 'floor' | 'accelerator' | 'unclear'; gex: number; conf: 1 | 2 | 3 | null }
export interface SdExp {
  ex: string; label: string; long: string; td: number; cd: number; T: number; iv: number; m: number; earn: boolean; band: [number, number];
  sug: { kc: number; kp: number; C: SdRow; P: SdRow };
  rows: { c: SdRow[]; p: SdRow[] };
  sig: SdSig[];
  ivK?: [number, number][];
  gamma?: { day: string; flip: number | null; walls: { K: number; kind: GammaWall['kind']; gex: number; conf: 1 | 2 | 3 }[] };
}
export interface SdSold { put: boolean; K: number; n: number; ex: string; be: number | null; got?: number | null; iv?: number | null; z0?: number | null;
  fill?: { S: number; iv: number; td: number; approx: boolean } }
export interface Zone { kind: 'support' | 'resistance'; lo: number; hi: number; mid: number; strength: number }
export interface Tech {
  sma20: number | null; sma50: number | null; sma100: number | null; sma200: number | null; rsi14: number | null; hv20: number | null; ivRank: number | null;
  ivLow52?: number | null; ivHigh52?: number | null; zones: Zone[];
}
export interface SdReply {
  ok: boolean; t: string; name: string; S: number; prev: number; move: number; open: boolean; today: string;
  cfg: { cLo: number; cHi: number; pLo: number; pHi: number };
  counts: { calls: number; puts: number };
  sold: SdSold[]; exps: SdExp[];
  cover?: { shares: number; otm: { ex: string; n: number }[] };
  r?: number; q?: number;
  tech?: Tech; day?: Day; closes?: Close[];
  events?: { earnings?: string | null; exDiv?: string | null; divAmt?: number | null };
}

/* ── What was picked, per book and name (README §3.9.1: calls and puts keep their own level) ── */
export interface Pick { ex: string | null; side: 'c' | 'p'; selC: number | null; selP: number | null; nC: number | null; nP: number | null; why: boolean }
const EMPTY: Pick = { ex: null, side: 'c', selC: null, selP: null, nC: null, nP: null, why: false };
const store = new Map<string, Pick>();
const subs = new Set<() => void>();
const sub = (f: () => void) => { subs.add(f); return () => { subs.delete(f); }; };
const put = (k: string, f: (p: Pick) => Pick) => { store.set(k, f(store.get(k) ?? EMPTY)); subs.forEach((s) => s()); };
/** Open on an expiry from outside (a Sold in SD row tap). */
export const pickExpiry = (book: string, t: string, ex: string) => put(`${book}|${t}`, (p) => ({ ...p, ex, selC: null, selP: null }));
export function usePick(book: string, t: string) {
  const k = `${book}|${t}`;
  const p = useSyncExternalStore(sub, () => store.get(k) ?? EMPTY);
  const set = useCallback((q: Partial<Pick>) => put(k, (x) => ({ ...x, ...q })), [k]);
  return useMemo(() => ({ p, set }), [p, set]);
}

/* ── The page's open sheets (Intelligence stays open across names, as the design does) ── */
let intelOpen = false;
const openSubs = new Set<() => void>();
export const setIntelOpen = (v: boolean) => { intelOpen = v; openSubs.forEach((s) => s()); };
export const useIntelOpen = () => useSyncExternalStore((f) => { openSubs.add(f); return () => { openSubs.delete(f); }; }, () => intelOpen);
/** A Sold in SD row tap asks the window to come into view once it has opened. */
let scrollSeq = 0;
export const requestIntelScroll = () => { scrollSeq++; openSubs.forEach((s) => s()); };
export const useIntelScroll = () => useSyncExternalStore((f) => { openSubs.add(f); return () => { openSubs.delete(f); }; }, () => scrollSeq);

/* ── The pieces ── */
const same = (a: number, b: number) => Math.abs(a - b) < 1e-9;
/** The engine's ladder for one side (D8): cfg's range in 0.25 SD steps; the rule's row carries the strike it moved to. */
export const ladder = (d: SdReply, e: SdExp, put: boolean): number[] => {
  const lo = put ? d.cfg.pLo : d.cfg.cLo, hi = put ? d.cfg.pHi : d.cfg.cHi, o: number[] = [];
  for (let k = lo; k <= hi + 1e-9; k += 0.25) o.push(Math.round(k * 4) / 4);
  return o.filter((k) => !!rowAt(e, k, put));
};
export const rowAt = (e: SdExp, k: number, put: boolean): SdRow | undefined => {
  if (same(k, put ? e.sug.kp : e.sug.kc)) return put ? e.sug.P : e.sug.C;
  return (put ? e.rows.p : e.rows.c).find((r) => same(r.k, k));
};
/** The chain's mid IV at a strike for this expiry (between its two nearest strikes), else the expiry's at-the-money IV. */
export const ivAtStrike = (e: SdExp, K: number): number => {
  const pts = (e.ivK ?? []).filter(([k, v]) => k > 0 && v > 0).sort((a, b) => a[0] - b[0]);
  if (pts.length < 2 || K < pts[0][0] || K > pts[pts.length - 1][0]) return e.iv;
  let i = 1; while (i < pts.length - 1 && pts[i][0] < K) i++;
  const [k0, v0] = pts[i - 1], [k1, v1] = pts[i];
  return k1 > k0 ? v0 + ((v1 - v0) * (K - k0)) / (k1 - k0) : v0;
};
/** "0.5 SD", "ATM", "ITM". */
export const sdl = (k: number) => (k < 0 ? 'ITM' : k === 0 ? 'ATM' : `${+k.toFixed(2)} SD`);

export interface Levels2 extends Levels {
  flip: number | null;
  /** The gamma walls with their size and how sure (null: not sent). */
  walls: { kind: 'ceiling' | 'floor' | 'accelerator'; K: number; gex: number; conf: 1 | 2 | 3 | null }[];
  zones: Zone[];
}
/** The levels at this expiry: the gamma walls (the reply's, else Home's per-expiry walls), the nearest support under
    the price and resistance over it (their middles), the averages. */
export function levelsOf(d: SdReply, e: SdExp, chains: ChainW[]): Levels2 {
  const S = d.S, walls: Levels2['walls'] = [];
  let flip: number | null = null;
  if (e.gamma) {
    flip = e.gamma.flip;
    const pickW = (kind: 'ceiling' | 'floor' | 'accelerator') => e.gamma!.walls.filter((w) => w.kind === kind).sort((a, b) => Math.abs(b.gex) - Math.abs(a.gex))[0];
    for (const kind of ['ceiling', 'floor', 'accelerator'] as const) { const w = pickW(kind); if (w) walls.push({ kind, K: w.K, gex: Math.abs(w.gex), conf: w.conf }); }
  } else {
    const c = chains.find((x) => x.ex === e.ex);
    if (c) {
      flip = c.flip;
      if (c.c) walls.push({ kind: 'ceiling', K: c.c.k, gex: Math.abs(c.c.gex), conf: null });
      if (c.f) walls.push({ kind: 'floor', K: c.f.k, gex: Math.abs(c.f.gex), conf: null });
      if (c.a && !(c.f && c.a.k === c.f.k)) walls.push({ kind: 'accelerator', K: c.a.k, gex: Math.abs(c.a.gex), conf: null });
    }
  }
  const W = (k: string) => walls.find((w) => w.kind === k)?.K ?? null;
  const zones = d.tech?.zones ?? [];
  const sup = zones.filter((z) => z.kind === 'support' && z.mid < S).sort((a, b) => b.mid - a.mid)[0];
  const res = zones.filter((z) => z.kind === 'resistance' && z.mid > S).sort((a, b) => a.mid - b.mid)[0];
  const t = d.tech;
  return {
    ceiling: W('ceiling'), floor: W('floor'), accelerator: W('accelerator'), flip, walls, zones,
    support: sup?.mid ?? null, resistance: res?.mid ?? null,
    sma20: t?.sma20 ?? null, sma50: t?.sma50 ?? null, sma100: t?.sma100 ?? null, sma200: t?.sma200 ?? null,
  };
}

export interface Alert { k: string; name: string; L: number; s: LevelState; lane: 'w' | 't'; text: string }
/** Today's alerts (§3.9.2): closed through first, then touched. */
export function alertsOf(lv: Levels2, day: Day | null | undefined): Alert[] {
  const all: [string, string, number | null | undefined, 'w' | 't'][] = [
    ['ce', 'Ceiling', lv.ceiling, 'w'], ['fl', 'Floor', lv.floor, 'w'], ['fp', 'Flip', lv.flip, 'w'], ['ac', 'Accelerator', lv.accelerator, 'w'],
    ['su', 'Support', lv.support, 't'], ['re', 'Resistance', lv.resistance, 't'],
    ['m20', '20-day', lv.sma20, 't'], ['m50', '50-day', lv.sma50, 't'], ['m100', '100-day', lv.sma100, 't'], ['m200', '200-day', lv.sma200, 't'],
  ];
  const fmt = (k: string, L: number, lane: 'w' | 't') => (lane === 'w' && k !== 'fp' ? String(+L.toFixed(2)) : L.toFixed(2));
  return all.filter((a): a is [string, string, number, 'w' | 't'] => a[2] != null && Number.isFinite(a[2]))
    .map(([k, name, L, ln]) => ({ k, name, L, lane: ln, s: levelState(L, day) }))
    .filter((a) => a.s !== 'idle')
    .sort((p, q) => Number(p.s === 'touch') - Number(q.s === 'touch'))
    .map((a) => {
      const closed = a.s !== 'touch';
      return { ...a, text: `${closed ? (a.s === 'up' ? '↑ ' : '↓ ') : ''}${a.name} ${fmt(a.k, a.L, a.lane)} · ${closed ? (a.s === 'up' ? 'closed above' : 'closed below') : 'touched'}` };
    });
}
export const stateWords: Record<LevelState, string> = { idle: 'not reached today', touch: 'touched today', up: 'closed above today', dn: 'closed below today' };

/** Everything the window reads for one name, one expiry and one pick. */
export interface IntelModel {
  e: SdExp; ei: number; S: number; m: number;
  side: 'c' | 'p'; picked: boolean;
  kc: number; kp: number; ruleC: number; ruleP: number;
  rc: SdRow; rp: SdRow;
  nC: number; nP: number;
  lv: Levels2; alerts: Alert[];
  held: ShortLeg[]; nw: ShortLeg[];
  LH: Lane; LN: Lane; LB: Lane;
  move: Move | null;
  iv: ReturnType<typeof ivTone>;
  cov: ReturnType<typeof coverCheck> | null;
  read: { lead: string; rest: string };
  kind: string; earnIn: boolean; exDivIn: boolean;
}
export function intelModel(d: SdReply, p: Pick, friday: string, chains: ChainW[]): IntelModel | null {
  if (!d?.ok || !d.exps?.length) return null;
  const ex = p.ex && d.exps.some((x) => x.ex === p.ex) ? p.ex : openExpiry(d.exps, friday, String(d.today ?? '').slice(0, 10));
  const ei = Math.max(0, d.exps.findIndex((x) => x.ex === ex)), e = d.exps[ei], S = d.S, m = e.m;
  const inC = (k: number | null) => k != null && ladder(d, e, false).some((x) => same(x, k));
  const inP = (k: number | null) => k != null && ladder(d, e, true).some((x) => same(x, k));
  const selC = inC(p.selC) ? p.selC : null, selP = inP(p.selP) ? p.selP : null;
  const kc = selC ?? e.sug.kc, kp = selP ?? e.sug.kp;
  const rc = rowAt(e, kc, false) ?? e.sug.C, rp = rowAt(e, kp, true) ?? e.sug.P;
  // Counts: calls, the rest of what shares and OTM calls cover after the calls still open at this expiry; puts, the
  // reply's (the ones sold, else 5).
  const heldC = d.sold.filter((l) => !l.put && l.ex >= e.ex).reduce((a, l) => a + l.n, 0);
  const cap = d.cover ? Math.floor(d.cover.shares / 100) + d.cover.otm.filter((o) => o.ex >= e.ex).reduce((a, o) => a + o.n, 0) : d.counts.calls;
  const nC = Math.max(0, Math.min(999, p.nC ?? Math.max(0, cap - heldC))), nP = Math.max(0, Math.min(999, p.nP ?? d.counts.puts));
  const held: ShortLeg[] = d.sold.filter((l) => l.ex === e.ex && l.got != null && l.n > 0).map((l) => ({ put: l.put, K: l.K, n: l.n, p: l.got! }));
  const nw: ShortLeg[] = [...(nC > 0 ? [{ put: false, K: rc.K, n: nC, p: rc.pr }] : []), ...(nP > 0 ? [{ put: true, K: rp.K, n: nP, p: rp.pr }] : [])];
  const LH = lane(held, S, m), LN = lane(nw, S, m), LB = lane([...held, ...nw], S, m);
  const lv = levelsOf(d, e, chains);
  const alerts = alertsOf(lv, d.day);
  const move = d.closes?.length ? moveOf(d.closes, S, d.today, e.iv, e.td, m) : null;
  // One verdict on premiums for the whole window: the engine's own (calc(): the 30-day IV's rank over a year and its
  // ratio to HV20), as its Why list shows it; the rank is the server's. The expiry's IV alone against a year of 30-day
  // IVs would call every short weekly rich.
  const sigIv = e.sig.find((g) => g.key === 'iv')?.v;
  const tone = sigIv === 'Rich' ? 'rich' as const : sigIv === 'Cheap' ? 'cheap' as const : sigIv === 'None' ? 'fair' as const : ivTone(e.iv, d.tech).tone;
  const iv = { rank: d.tech?.ivRank != null ? Math.round(d.tech.ivRank) : null, ratio: null as number | null, tone };
  const cov = d.cover ? coverCheck({ shares: d.cover.shares, held: d.sold.filter((l) => !l.put), otm: d.cover.otm, sale: nC > 0 ? { K: rc.K, n: nC } : null, ex: e.ex }) : null;
  const exDiv = d.events?.exDiv ?? null, exDivIn = !!exDiv && exDiv >= d.today && exDiv <= e.ex;
  // The read (D4): the sale being picked; a side at 0 contracts is left out, unless both are (then both, no odds).
  const both0 = nC === 0 && nP === 0;
  const read = theRead({
    S0: S, step: stepOf(S),
    call: nC > 0 || both0 ? { K: rc.K, k: kc } : null, put: nP > 0 || both0 ? { K: rp.K, k: kp } : null,
    levels: lv, uncovered: cov?.uncovered ?? 0, newCalls: nC,
    earnings: !!e.earn, dividend: exDivIn,
    pace: move?.pace && !move.pace.flat ? move.pace.to : null,
    odds: LN.has ? LN.cp : null, tone: iv.tone,
  });
  return {
    e, ei, S, m, side: p.side, picked: selC != null || selP != null, kc, kp, ruleC: e.sug.kc, ruleP: e.sug.kp, rc, rp, nC, nP,
    lv, alerts, held, nw, LH, LN, LB, move, iv, cov, read, kind: expiryKind(e.ex, !!e.earn), earnIn: !!e.earn, exDivIn,
  };
}
