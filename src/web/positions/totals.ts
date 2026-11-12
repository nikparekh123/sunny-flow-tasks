// The Positions totals (handoff 2026-11-11-sd-whatif-totals, 145b; Nik 11 Nov 2026), for each name and for the whole
// book, all from the book engine's holdings(), the numbers Home's brief sends the phone, so the web and the app read
// the same.
//
// ⚠ NIK'S GROUPING RULE (11 Nov 2026, it overrides the handoff README's Long = shares + LEAPS):
//   Long   = shares only.
//   Hedge  = every call bought (LEAPS and OTM calls alike), then every put bought (insurance).
//   Income = everything sold: calls, then puts.
// The same rule groups the What if legs and the Every leg filter (roleOf, below). A name with LEAPS and no shares
// (UBER, NFLX today) reads None under Long and has its LEAPS under Hedge. That is intended.
import { NameBook, holdings, type Div, type Leg } from '../../../supabase/functions/_shared/book-engine.ts';
import type { J } from '../lib/data';

/** Why a leg is in the book. */
export type Role = 'long' | 'hedge' | 'income';
/** Nik's rule, on any leg with the engine's fields (a held leg, a What if trade). */
export const roleOf = (l: { ty: string; q: number }): Role => (l.ty === 'S' ? 'long' : l.q < 0 ? 'income' : 'hedge');
/** Inside a role: calls first, then puts (shares count as calls). */
export const isPut = (l: { ty: string }) => l.ty === 'P';
export const ROLES: { k: Role; h: string }[] = [{ k: 'long', h: 'Long' }, { k: 'hedge', h: 'Hedge' }, { k: 'income', h: 'Income' }];

/** The bar's pieces: shares; calls and puts bought (hc = the engine's LEAPS + OTM calls); calls and puts sold. */
export type GKey = 'sh' | 'hc' | 'ip' | 'sc' | 'sp';
export const PIECES: { key: GKey; role: Role; l: string }[] = [
  { key: 'sh', role: 'long', l: 'Shares' },
  { key: 'hc', role: 'hedge', l: 'Calls' },
  { key: 'ip', role: 'hedge', l: 'Puts' },
  { key: 'sc', role: 'income', l: 'Calls' },
  { key: 'sp', role: 'income', l: 'Puts' },
];

/** One piece's numbers: what was paid (for what was sold, the premium collected), its value now (for what was sold,
    the cost to buy it back), its time value (null for shares). */
export interface Fig { paid: number; now: number; tv: number | null }
/** A piece the name holds (its figures), or nothing. */
export type Cell = Fig | null;
export type Row = Record<GKey, Cell>;

/** The change line: what was bought, now less paid; what was sold, collected less the cost to close (kept). */
export const gainOf = (f: Fig, sold: boolean) => (sold ? f.paid - f.now : f.now - f.paid);
/** That change as a % of what was paid (or collected). */
export const pctOfFig = (f: Fig, sold: boolean) => (f.paid > 0 ? (gainOf(f, sold) / f.paid) * 100 : 0);

/** The piece an engine leg adds to. */
const pieceOf = (l: Leg): GKey | null =>
  l.ty === 'S' ? (l.q > 0 ? 'sh' : null) : l.q < 0 ? (l.kind === 'sp' ? 'sp' : 'sc') : l.kind === 'ins' ? 'ip' : 'hc';

/** Every name's totals, from its own legs, through the book engine's holdings(). */
export function nameTotals(p: J): Map<string, Row> {
  const out = new Map<string, Row>();
  const r = Number(p?.brief_inputs?.r ?? 0.04);
  for (const n of (p?.brief_inputs?.names ?? []) as J[]) {
    const t = String(n.t), legs: Leg[] = n.legs ?? [], divs: Div[] = n.divs ?? [];
    const S0 = Number(n.S0), P0 = Number(n.P0 ?? n.S0);
    if (!(S0 > 0) || !legs.length) continue;
    const nb = new NameBook({ t, S0, P0, iv: Number(n.iv ?? 0), legs, divs, r, noIv: !!n.noIv });
    const h = holdings(nb);
    const has = new Set(legs.map(pieceOf).filter((k): k is GKey => !!k));
    const fig = (k: 'sh' | 'lp' | 'oc' | 'ip' | 'sc' | 'sp'): Fig => ({ paid: h.paid[k], now: h[k][0], tv: k === 'sh' ? null : h.tv[k] });
    const lp = fig('lp'), oc = fig('oc');
    out.set(t, {
      sh: has.has('sh') ? fig('sh') : null,
      hc: has.has('hc') ? { paid: lp.paid + oc.paid, now: lp.now + oc.now, tv: (lp.tv ?? 0) + (oc.tv ?? 0) } : null,
      ip: has.has('ip') ? fig('ip') : null,
      sc: has.has('sc') ? fig('sc') : null,
      sp: has.has('sp') ? fig('sp') : null,
    });
  }
  return out;
}

/** The whole book: every name added up (a piece no name holds reads None). */
export function bookTotals(names: Map<string, Row>): Row {
  const row = {} as Row;
  for (const g of PIECES) {
    let f: Fig | null = null;
    for (const r of names.values()) {
      const c = r[g.key];
      if (!c) continue;
      f = f ?? { paid: 0, now: 0, tv: g.key === 'sh' ? null : 0 };
      f.paid += c.paid; f.now += c.now;
      if (f.tv != null && c.tv != null) f.tv += c.tv;
    }
    row[g.key] = f;
  }
  return row;
}
