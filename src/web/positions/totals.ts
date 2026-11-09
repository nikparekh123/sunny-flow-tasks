/* eslint-disable @typescript-eslint/no-explicit-any */
// The Positions totals (handoff 2026-11-08-web 2, README 2, Nik 9 Nov 2026): every group of the book in three views,
// for each name and for the whole book. One engine for both, so the names always add up to the book: each name's
// legs (Home's brief_inputs, the legs the server priced on) through the book engine's holdings, the same engine the
// rail, the payoff and the phone use.
//
//   Time value: time value on LEAPS and OTM calls, value on insurance, what is left to earn on sold calls and puts,
//               and the gain on cost for shares (shares have no time value).
//   $ change:   gain on cost for what you bought; premium kept for what you sold.
//   % change:   that over its base: cost for what you bought, premium collected for what you sold (kept ÷ collected).
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

/** One group's numbers: the Time value view's figure, the $ change, and the base the % is taken on. */
export interface Fig { tv: number; usd: number; base: number }
/** A group the name holds (its figures), one it does not hold but has a sale still to place ('todo'), or nothing. */
export type Cell = Fig | 'todo' | null;
export type Row = Record<GKey, Cell>;

export const pctOfFig = (f: Fig) => (f.base > 0 ? (f.usd / f.base) * 100 : 0);

/** Every name's totals, from its own legs. */
export function nameTotals(p: J): Map<string, Row> {
  const out = new Map<string, Row>();
  const r = Number(p?.brief_inputs?.r ?? 0.04);
  const todo = (t: string, kind: string) => ((p?.this_week ?? []) as J[]).some((x) => x?.t === t && x?.kind === kind);
  for (const n of (p?.brief_inputs?.names ?? []) as J[]) {
    const t = String(n.t), legs: Leg[] = n.legs ?? [], divs: Div[] = n.divs ?? [];
    const S0 = Number(n.S0), P0 = Number(n.P0 ?? n.S0);
    if (!(S0 > 0) || !legs.length) continue;
    const nb = new NameBook({ t, S0, P0, iv: Number(n.iv ?? 0), legs, divs, r, noIv: !!n.noIv });
    const h = holdings(nb);
    const per = (l: Leg) => (l.now != null ? l.now : nb.val(l, S0, 0) / (l.q * 100));
    const acc: Record<GKey, Fig | null> = { sh: null, lp: null, oc: null, ip: null, sc: null, sp: null };
    const add = (k: GKey, tv: number, usd: number, base: number) => {
      const f = acc[k] ?? (acc[k] = { tv: 0, usd: 0, base: 0 });
      f.tv += tv; f.usd += usd; f.base += base;
    };
    for (const l of legs) {
      if (l.ty === 'S') {
        if (!(l.q > 0)) continue;
        const gain = l.K > 0 ? l.q * (S0 - l.K) : 0;
        add('sh', gain, gain, l.K > 0 ? l.q * l.K : 0);
        continue;
      }
      const now = Math.abs(l.q) * 100 * per(l), paid = Math.abs(l.q) * 100 * (l.at ?? per(l));
      if (l.q < 0) add(l.kind === 'sp' ? 'sp' : 'sc', now, paid - now, paid);
      else add(l.kind === 'ins' ? 'ip' : l.kind === 'leaps' ? 'lp' : 'oc', 0, now - paid, paid);
    }
    // The Time value view's figures for what was bought: the engine's time value on LEAPS and OTM calls, the value of
    // the insurance (as the book row has always read).
    if (acc.lp) acc.lp.tv = h.tv.lp;
    if (acc.oc) acc.oc.tv = h.tv.oc;
    if (acc.ip) acc.ip.tv = h.ip[0];
    const row = {} as Row;
    for (const g of GROUPS) {
      row[g.key] = acc[g.key] ?? (g.key === 'sc' && todo(t, 'sell') ? 'todo' : g.key === 'sp' && todo(t, 'put') ? 'todo' : null);
    }
    out.set(t, row);
  }
  return out;
}

/** The whole book: every name added up (a group no name holds reads None). */
export function bookTotals(names: Map<string, Row>): Row {
  const row = {} as Row;
  for (const g of GROUPS) {
    let f: Fig | null = null, todo = false;
    for (const r of names.values()) {
      const c = r[g.key];
      if (c === 'todo') { todo = true; continue; }
      if (!c) continue;
      f = f ?? { tv: 0, usd: 0, base: 0 };
      f.tv += c.tv; f.usd += c.usd; f.base += c.base;
    }
    row[g.key] = f ?? (todo ? 'todo' : null);
  }
  return row;
}
