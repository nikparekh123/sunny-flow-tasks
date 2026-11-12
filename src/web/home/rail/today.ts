// The Positions rail on Home (handoff 2026-11-12-positions-rail, Explorations 148a; Nik 12 Nov 2026): today, live, for
// every leg in the book, By ticker or By leg. No payoff, delta, theta, events, strategy or To do.
//
//   Today for a leg = contracts × 100 × (mark now less IBKR's mark at the previous close), from sunny-home's
//   brief_inputs (each leg's `now` and `prev`; a leg opened since the close counts from its fill, R1). Shares: count ×
//   (price now less the price at that close). On the weekend it is This week, from the last close before this week.
//   A leg is never added across strikes or expiries: two sold call strikes are two rows.
//
// By leg follows Nik's grouping (11 and 12 Nov 2026, over the handoff's Shares-and-LEAPS card): Shares the shares;
// Hedges every call bought (LEAPS and OTM calls alike), then every put bought; Income everything sold.
import { NameBook, type Div, type Leg } from '../../../../supabase/functions/_shared/book-engine.ts';
import type { J } from '../../lib/data';
import { count } from '../../lib/format';

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** "Nov 20", or "Jan ’28" past six months (the house expiry label). */
const exLabel = (iso: string, days: number) => {
  const [y, m, d] = iso.split('-').map(Number);
  return days > 183 ? `${MON[m - 1]} ’${String(y).slice(2)}` : `${MON[m - 1]} ${d}`;
};
const kStr = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));

/** One row: what it is, the line under it, today's dollars. */
export interface RailRow { k: string; t: string; l: string; s: string; v: number; ex: string }
export interface RailNameCard { t: string; px: number; mv: number; today: number; rows: RailRow[] }
export interface RailPart { k: string; h: string; total: number; rows: RailRow[] }
export interface RailKind { k: string; h: string; total: number; parts: RailPart[]; heads: boolean }
export interface RailToday { week: boolean; names: RailNameCard[]; kinds: RailKind[]; noSold: string[] }

type Part = 'sh' | 'hc' | 'hp' | 'ic' | 'ip';
/** By ticker row order inside a card: shares, sold calls, sold puts, then calls and puts bought. */
const ORDER: Record<Part, number> = { sh: 0, ic: 1, ip: 2, hc: 3, hp: 4 };
const partOf = (l: Leg): Part => (l.ty === 'S' ? 'sh' : l.q < 0 ? (l.ty === 'C' ? 'ic' : 'ip') : l.ty === 'C' ? 'hc' : 'hp');

/** Every name's rows, in `order` (the rail's session order of tickers). */
export function railToday(p: J, order: string[]): RailToday {
  const inputs: J[] = p?.brief_inputs?.names ?? [];
  const r = Number(p?.brief_inputs?.r ?? 0.04);
  const week = !!p?.brief_inputs?.rail?.week;
  const at = new Map(order.map((t, i) => [t, i]));
  const names: RailNameCard[] = [];
  const byPart = new Map<Part, { row: RailRow; tk: number }[]>();
  for (const n of inputs.slice().sort((a, b) => (at.get(String(a.t)) ?? 99) - (at.get(String(b.t)) ?? 99))) {
    const t = String(n.t), legs: Leg[] = n.legs ?? [], divs: Div[] = n.divs ?? [];
    const S0 = Number(n.S0), P0 = Number(n.P0 ?? n.S0), Pb = Number(n.Pb ?? P0);
    if (!(S0 > 0) || !legs.length) continue;
    const nb = new NameBook({ t, S0, P0, iv: Number(n.iv ?? 0), legs, divs, r, noIv: !!n.noIv });
    // With no IBKR mark at the close (rare: a leg missing from that report), the model at that close, one day (or one
    // week) more to expiry, as the handoff's prototype.
    const back = week ? -7 : -1;
    const per = (l: Leg) => (l.now != null ? l.now : nb.val(l, S0, 0) / (l.q * 100));
    const prev = (l: Leg) => (l.prev != null ? l.prev : nb.val(l, Pb, back) / (l.q * 100));
    const rows: (RailRow & { part: Part })[] = legs.map((l) => {
      const part = partOf(l);
      if (l.ty === 'S') return { k: t + l.k, t, part, l: 'Shares', s: count(l.q) + ' shares', v: l.q * (S0 - Pb), ex: '' };
      const now = per(l), sold = l.q < 0, cp = l.ty === 'C' ? 'calls' : 'puts', n0 = count(Math.abs(l.q)), exL = exLabel(l.ex, l.days);
      let s = `${n0} ${sold ? 'sold' : 'bought'} · ${exL}`;
      if (sold && l.at != null && l.at > 0) {
        const kp = 1 - now / l.at;
        s += ' · ' + (kp >= 0 ? `${Math.round(kp * 100)}% kept` : `costs ${Math.round(-kp * 100)}% more`);
      }
      return { k: t + l.k, t, part, l: `${kStr(l.K)} ${cp} ${sold ? 'sold' : 'bought'}`, s, v: l.q * 100 * (now - prev(l)), ex: l.ex };
    });
    // Inside a part, the soonest expiry first (Nik 12 Nov 2026, as the What if), then by strike.
    rows.sort((a, b) => ORDER[a.part] - ORDER[b.part] || (a.ex < b.ex ? -1 : a.ex > b.ex ? 1 : 0));
    names.push({ t, px: S0, mv: Pb > 0 ? (S0 / Pb - 1) * 100 : 0, today: rows.reduce((a, x) => a + x.v, 0), rows });
    for (const x of rows) {
      const lbl = x.part === 'sh' ? t : `${t} ${x.l.replace(/ (sold|bought)$/, '')}`;
      const list = byPart.get(x.part) ?? [];
      list.push({ row: { ...x, l: lbl }, tk: at.get(t) ?? 99 });
      byPart.set(x.part, list);
    }
  }
  const PARTS: [string, [Part, string][]][] = [['Shares', [['sh', 'Shares']]], ['Hedges', [['hc', 'Calls'], ['hp', 'Puts']]], ['Income', [['ic', 'Calls'], ['ip', 'Puts']]]];
  const kinds: RailKind[] = [];
  for (const [h, subs] of PARTS) {
    const parts: RailPart[] = [];
    for (const [pk, ph] of subs) {
      // Book order of names, then the soonest expiry first inside each name.
      const rows = (byPart.get(pk) ?? []).sort((a, b) => a.tk - b.tk || (a.row.ex < b.row.ex ? -1 : a.row.ex > b.row.ex ? 1 : 0)).map((x) => x.row);
      if (rows.length) parts.push({ k: h + pk, h: ph, total: rows.reduce((a, x) => a + x.v, 0), rows });
    }
    if (parts.length) kinds.push({ k: h, h, total: parts.reduce((a, x) => a + x.total, 0), parts, heads: parts.length > 1 || h !== 'Shares' });
  }
  const noSold = names.filter((n) => !n.rows.some((x) => x.l.endsWith(' sold'))).map((n) => n.t);
  return { week, names, kinds, noSold };
}
