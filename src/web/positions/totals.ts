// Your book's parts (Nik, 24 Nov 2026: "Move away from Long, Hedge and Income to each leg: Shares, Calls Bought, Calls
// Sold, Puts Bought and Puts Sold. Lets do this everywhere in positions."). sunny-home sends them ready, all time, for
// the whole book and for each name (payload.brief_inputs.parts = { book, names: { TICKER } }, BUILD 2026-11-25.6):
//   sh Shares, hc Calls bought, sc Calls sold, ip Puts bought, sp Puts sold.
//   Bought (sh, hc, ip): value = worth now; all = gain or loss on IBKR's cost; return = all / abase.
//   Sold (sc, sp):       value = premium collected; all = kept so far; now (the cost to buy back) = value less all;
//                        captured = all / value; tv = the time value left.
//   nl = how many legs. tv on every option part, none on shares.
// The same words name each leg everywhere on Positions (legWords), and Every leg's chips read Sold · Bought (sideOf).
import type { J } from '../lib/data';

export type PKey = 'sh' | 'hc' | 'sc' | 'ip' | 'sp';
export interface Part { value: number; all: number; abase: number; nl: number; tv: number | null }
export type Parts = Partial<Record<PKey, Part>>;

/** The order every card reads them in (Nik, 24 Nov 2026). */
export const PARTS: { k: PKey; l: string; sold: boolean }[] = [
  { k: 'sh', l: 'Shares', sold: false },
  { k: 'hc', l: 'Calls bought', sold: false },
  { k: 'sc', l: 'Calls sold', sold: true },
  { k: 'ip', l: 'Puts bought', sold: false },
  { k: 'sp', l: 'Puts sold', sold: true },
];

const num = (v: unknown) => (Number.isFinite(Number(v)) ? Number(v) : 0);
/** One book's or one name's parts: only the parts it holds. */
function readOne(x: J): Parts {
  const out: Parts = {};
  for (const { k } of PARTS) {
    const p = x?.[k];
    if (!p || p.held === false) continue;
    out[k] = { value: num(p.value), all: num(p.all), abase: num(p.abase), nl: num(p.nl), tv: k === 'sh' || p.tv == null ? null : num(p.tv) };
  }
  return out;
}

/** The whole book's parts and each name's (null before the server sends them). */
export function readParts(p: J): { book: Parts; names: Map<string, Parts> } | null {
  const raw = p?.brief_inputs?.parts;
  if (!raw?.book) return null;
  const names = new Map<string, Parts>();
  for (const [t, v] of Object.entries((raw.names ?? {}) as Record<string, J>)) {
    const one = readOne(v);
    if (Object.keys(one).length) names.set(t, one);
  }
  return { book: readOne(raw.book), names };
}

/** How many legs a book or a name holds (every part's nl). */
export const legsIn = (ps: Parts) => PARTS.reduce((a, { k }) => a + (ps[k]?.nl ?? 0), 0);

/** An option's side: sold (q under 0) or bought. Shares have none (they are the Shares chip). */
export const sideOf = (l: { ty: string; q: number }): 'sold' | 'bought' | null => (l.ty === 'S' ? null : l.q < 0 ? 'sold' : 'bought');
/** "Calls sold", "Puts bought" (shares: "Shares"). */
export const legWords = (l: { ty: string; q: number }) => (l.ty === 'S' ? 'Shares' : `${l.ty === 'C' ? 'Calls' : 'Puts'} ${l.q < 0 ? 'sold' : 'bought'}`);
