// Overview's numbers (README "3 · Overview"), read from what the server already sends; nothing re-derived.
//
// Allocation is weighted by capital bought: every bought leg at its cost (shares at their average cost, LEAPS,
// OTM calls and insurance puts at what was paid), the legs sunny-home sends in payload.brief_inputs. Sold legs
// add nothing to it. P&L so far is the server's own open P&L per name (payload.allocation: now minus invested,
// shares and options since they were opened), the same figure the phone's Allocation reads.
import type { J } from '../lib/data';

export interface AlRow {
  t: string;
  /** The company as the brief writes it ("Alibaba"). */
  name: string;
  /** Capital bought, at cost. */
  cap: number;
  /** Open P&L on the name, shares and options. */
  pl: number;
  /** The strategy's name ("Rebound"), or '' when the server sends none. */
  strat: string;
}

const STRAT: Record<string, string> = { aftershock: 'Aftershock', rebound: 'Rebound', ladder: 'Ladder' };
const stratName = (s: unknown) => {
  const k = String(s ?? '').trim();
  if (!k) return '';
  return STRAT[k.toLowerCase()] ?? k.charAt(0).toUpperCase() + k.slice(1);
};

/** One row per name the book holds, largest capital first. */
export function allocationRows(payload: J): AlRow[] {
  const names: J[] = payload?.brief_inputs?.names ?? [];
  const brief = new Map<string, J>(((payload?.brief?.names ?? []) as J[]).map((n) => [String(n.t), n]));
  const held = new Map<string, J>(((payload?.allocation?.holdings ?? []) as J[]).map((h) => [String(h.ticker), h]));
  const strategies: Record<string, string> = payload?.strategies ?? {};
  const rows: AlRow[] = [];
  for (const n of names) {
    const t = String(n.t);
    let cap = 0, pl = 0;
    for (const l of (n.legs ?? []) as J[]) {
      const q = Number(l.q ?? 0), sh = l.kind === 'shares', m = sh ? 1 : 100;
      const en = Number(sh ? l.K : l.at) || 0, mk = Number(sh ? n.S0 : l.now) || 0;
      if (q > 0) cap += q * m * en;
      pl += (mk - en) * q * m;
    }
    const h = held.get(t);
    if (h && Number.isFinite(+h.now) && Number.isFinite(+h.invested)) pl = +h.now - +h.invested;
    if (cap > 0) rows.push({ t, name: String(brief.get(t)?.name ?? t), cap, pl, strat: stratName(strategies[t] ?? brief.get(t)?.strategy) });
  }
  return rows.sort((a, b) => b.cap - a.cap);
}

/** A check's value for one book, from the server's chips ("Sunny 82%" → "82%"). */
export function chipFor(check: J, bookName: string): string | null {
  const c = ((check?.chips ?? []) as unknown[]).map(String).find((x) => x.startsWith(bookName + ' '));
  return c ? c.slice(bookName.length + 1) : null;
}

/** The server's sentence, split into the design's thick first sentence and the thin rest. */
export function splitSentence(spans: J): { thick: string; thin: string } {
  const text = (Array.isArray(spans) ? spans.map((s: J) => String(s?.t ?? '')).join('') : String(spans ?? '')).trim();
  const i = text.search(/[.!?] /);
  return i < 0 ? { thick: text, thin: '' } : { thick: text.slice(0, i + 1), thin: text.slice(i + 2).trim() };
}
