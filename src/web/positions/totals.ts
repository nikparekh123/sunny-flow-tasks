/* eslint-disable @typescript-eslint/no-explicit-any */
// The Positions totals (handoff 2026-11-08-web 2, README 2; Nik 9 and 11 Nov 2026): every group of the book in three
// views, for each name and for the whole book, all from the book engine's holdings(), the numbers Home's brief sends
// the phone, so the web and the app read the same:
//
//   Paid:       what the shares and what was bought cost; the premium taken in for what was sold.
//   Value now:  what it is worth today (for what was sold, the cost to buy it back), with the % change on Paid
//               (for what was sold, the share of the premium kept).
//   Time value: time value left in each option; shares have none ("-").
import { NameBook, holdings, type Div, type Leg } from '../../../supabase/functions/_shared/book-engine.ts';
import type { J } from '../lib/data';

export type GKey = 'sh' | 'lp' | 'oc' | 'ip' | 'sc' | 'sp';
export const GROUPS: { key: GKey; l: string; tvWord: string; sold: boolean }[] = [
  { key: 'sh', l: 'Shares', tvWord: 'gain', sold: false },
  { key: 'lp', l: 'LEAPS', tvWord: 'time value', sold: false },
  { key: 'oc', l: 'OTM calls', tvWord: 'time value', sold: false },
  { key: 'ip', l: 'Insurance', tvWord: 'value', sold: false },
  { key: 'sc', l: 'Calls', tvWord: 'left to earn', sold: true },
  { key: 'sp', l: 'Puts', tvWord: 'left to earn', sold: true },
];

/** One group's numbers: what was paid (or taken in), its value now (or cost to buy back), its time value (null for
    shares). */
export interface Fig { paid: number; now: number; tv: number | null }
/** A group the name holds (its figures), or nothing. */
export type Cell = Fig | null;
export type Row = Record<GKey, Cell>;

/** The change on what was paid: up when what was bought is worth more, or when what was sold costs less to buy back. */
export const gainOf = (f: Fig, sold: boolean) => (sold ? f.paid - f.now : f.now - f.paid);
export const pctOfFig = (f: Fig, sold: boolean) => (f.paid > 0 ? (gainOf(f, sold) / f.paid) * 100 : 0);

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
    // Which groups the name holds: shares, then what was sold, then what was bought (the engine's own keys).
    const has = new Set<GKey>();
    for (const l of legs) {
      if (l.ty === 'S') { if (l.q > 0) has.add('sh'); continue; }
      has.add(l.q < 0 ? (l.kind === 'sp' ? 'sp' : 'sc') : l.kind === 'ins' ? 'ip' : l.kind === 'leaps' ? 'lp' : 'oc');
    }
    const row = {} as Row;
    for (const g of GROUPS) {
      row[g.key] = has.has(g.key) ? { paid: h.paid[g.key], now: h[g.key][0], tv: g.key === 'sh' ? null : h.tv[g.key] } : null;
    }
    out.set(t, row);
  }
  return out;
}

/** The whole book: every name added up (a group no name holds reads None). */
export function bookTotals(names: Map<string, Row>): Row {
  const row = {} as Row;
  for (const g of GROUPS) {
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
