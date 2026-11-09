// The Positions rail's numbers (README 1b), one row per name held, all from the Home payload the phone reads:
//   brief_inputs.names   each name's legs, IV, dividends and price: the book model's inputs (sunny-home brief.ts),
//                        the same ones sunny-positions prices the Positions grid on
//   brief.names          status at the priced move (st: 2 short, 1 thin), strategy, size of the position
//   brief.position.rows  the read ("Makes the most at $40.07 by Friday") and its colour (Your position, By name)
//   brief.doc            the move Home reads for each name (Your names map: the day, pre-market move before the bell,
//                        the week on the weekend; sunny-home doc.ts, build review item 11)
//   writes.names, deck.earnings, chart.dividends.next   the next earnings or ex-dividend
//   this_week            the owners' To do (laid over for an owner only; a viewer never carries an order)
// The payoff is the name's legs at THIS Friday's close (brief.th days on, as the phone's Your position), across
// ±10% of today's price, 41 points, P&L from now: book-engine NameBook, never re-derived here.
import { NameBook, type Div, type Leg } from '../../../../supabase/functions/_shared/book-engine.ts';
import type { J } from '../../lib/data';

export interface RailName {
  t: string;
  company: string;
  /** "Rebound · 3,000 shares · 70 calls" */
  sub: string;
  px: number;
  /** Today's move in % (signed). */
  mv: number;
  /** 2 short, 1 thin, 0 long, at the priced move by Friday. */
  st: number;
  read: string;
  readColor: 'red' | 'orange' | 'ink';
  delta: number;
  theta: number;
  /** Sold calls: % of the premium kept and what is left; null when none are sold. */
  kept: { pct: number; left: number } | null;
  soFar: number;
  next: string;
  todo: string;
  /** P&L by Friday's close at 41 prices from ↓10% to ↑10%. */
  pay: number[];
  size: number;
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** "2026-12-01" → "Tue Dec 1" */
export const dayLabel = (d: string) => {
  const [y, m, dd] = d.split('-').map(Number);
  return `${DOW[new Date(Date.UTC(y, m - 1, dd)).getUTCDay()]} ${MON[m - 1]} ${dd}`;
};
const n0 = (x: number) => Math.round(Math.abs(x)).toLocaleString('en-US');
const STRAT: Record<string, string> = { aftershock: 'Aftershock', rebound: 'Rebound', ladder: 'Ladder' };
const stratName = (s: string | null | undefined) => (!s ? '' : STRAT[s] ?? s.charAt(0).toUpperCase() + s.slice(1));

/** The move Home reads for each name: the Your names map in the brief (sunny-home doc.ts yourNames). */
function docMoves(doc: J): Map<string, number> {
  const out = new Map<string, number>();
  for (const s of doc?.sections ?? []) for (const c of s?.cards ?? []) {
    if (c?.type !== 'yourNames') continue;
    const pg = (c.pages ?? []).find((p: J) => p?.kind === 'yourNames');
    for (const x of pg?.tiles ?? []) if (x?.ticker && Number.isFinite(+x.move)) out.set(String(x.ticker), +x.move);
  }
  return out;
}

/** The next earnings or ex-dividend still ahead: "Earnings Tue Nov 24", "Ex-div Mon Dec 14". */
function nextEvent(t: string, p: J): string {
  const today = String(p?.today ?? '');
  const w = (p?.writes?.names ?? []).find((n: J) => n?.ticker === t);
  const inp = w?.thesis?.reads?.inputs ?? {};
  const deck = (p?.deck?.earnings ?? []).find((e: J) => e?.ticker === t);
  const earn = inp.next_earnings ?? w?.next_earnings?.date ?? deck?.date ?? null;
  const dv = p?.chart?.dividends?.next;
  const exd = inp.ex_div ?? (dv?.ticker === t ? dv.ex_date : null);
  const c: [string, string][] = [];
  if (earn && String(earn) >= today) c.push([String(earn), 'Earnings ' + dayLabel(String(earn))]);
  if (exd && String(exd) >= today) c.push([String(exd), 'Ex-div ' + dayLabel(String(exd))]);
  c.sort((a, b) => a[0].localeCompare(b[0]));
  return c[0]?.[1] ?? '';
}

/** The name's first To do from the owners' list (calls to sell first, then the rest as the phone's cards order them:
    sales and rolls before buys), in the design's short form: "Sell 17 $64 calls" → "To do: sell 17 calls". The verb
    is the order's kind (sunny-home this_week: roll · buy · sell · put), so a roll's buy-back reads "roll 21 calls",
    the same word as Ready to roll, and fits the footer beside the next event. */
const VERB: Record<string, string> = { sell: 'sell', put: 'sell', roll: 'roll', buy: 'buy' };
function todoOf(t: string, p: J): string {
  const rows = ((p?.this_week ?? []) as J[]).filter((r) => r?.t === t);
  if (!rows.length) return '';
  const r = rows.find((x) => x.kind === 'sell') ?? rows.find((x) => x.kind !== 'buy') ?? rows[0];
  const act = String(r.act ?? r.action ?? '').split(' · ')[0];
  const m = /^(.*?)\s*(\d[\d,]*)\s.*?\b(calls?|puts?|shares?)\b/i.exec(act);
  if (m) return `To do: ${VERB[r.kind] ?? m[1].trim().toLowerCase()} ${m[2]} ${m[3].toLowerCase()}`.replace(/\s+/g, ' ');
  return act ? 'To do: ' + act.charAt(0).toLowerCase() + act.slice(1) : '';
}

/** Every name in the book, unordered. Empty when the book holds nothing. */
export function railNames(p: J): RailName[] {
  const brief = p?.brief ?? {};
  const inputs: J[] = p?.brief_inputs?.names ?? [];
  const r = Number(p?.brief_inputs?.r ?? 0.04);
  const bn = new Map<string, J>((brief.names ?? []).map((n: J) => [String(n.t), n]));
  const rows = new Map<string, J>((brief.position?.rows ?? []).map((x: J) => [String(x.id), x]));
  const moves = docMoves(brief.doc);
  const th0 = Number(brief.th);
  const out: RailName[] = [];
  for (const n of inputs) {
    const t = String(n.t), b = bn.get(t) ?? {}, row = rows.get(t);
    const legs: Leg[] = n.legs ?? [], divs: Div[] = n.divs ?? [];
    const S0 = Number(n.S0), P0 = Number(n.P0 ?? n.S0);
    if (!(S0 > 0) || !legs.length) continue;
    const nb = new NameBook({ t, S0, P0, iv: Number(n.iv ?? 0), legs, divs, r, noIv: !!n.noIv });
    const th = Number.isFinite(th0) ? th0 : Number(n.stops?.[n.fridayStop ?? 0]?.tt ?? 0);
    const g = nb.greeks(S0, 0);
    const pay = Array.from({ length: 41 }, (_, i) => nb.pl(S0 * (0.9 + 0.2 * i / 40), th));

    const shares = legs.filter((l) => l.kind === 'shares').reduce((a, l) => a + l.q, 0);
    const leaps = legs.filter((l) => l.kind === 'leaps').reduce((a, l) => a + l.q, 0);
    const sc = legs.filter((l) => l.kind === 'sc');
    const nCalls = sc.reduce((a, l) => a + Math.abs(l.q), 0);
    const per = (l: Leg) => (l.now != null ? l.now : nb.val(l, S0, 0) / (l.q * 100));
    const got = sc.reduce((a, l) => a + (l.at ?? 0) * Math.abs(l.q) * 100, 0);
    const left = sc.reduce((a, l) => a + per(l) * Math.abs(l.q) * 100, 0);
    let soFar = 0;
    for (const l of legs) {
      if (l.ty === 'S') { if (l.K > 0) soFar += l.q * (S0 - l.K); continue; }
      if (l.at != null) soFar += l.q * 100 * (per(l) - l.at);
    }
    const hold = [shares > 0 ? n0(shares) + ' shares' : leaps > 0 ? n0(leaps) + ' LEAPS' : '', nCalls ? n0(nCalls) + ' calls' : ''].filter(Boolean);
    const lc = row?.lineColor;
    out.push({
      t, company: String(b.name ?? t),
      sub: [stratName(b.strategy ?? p?.strategies?.[t]), ...hold].filter(Boolean).join(' · '),
      px: S0, mv: moves.get(t) ?? (P0 > 0 ? (S0 / P0 - 1) * 100 : 0),
      st: Number(b.st ?? row?.st ?? 0),
      read: String(row?.line ?? ''), readColor: lc === 'red' ? 'red' : lc === 'orange' ? 'orange' : 'ink',
      delta: g.d, theta: g.th,
      kept: sc.length && got > 0 ? { pct: (1 - left / got) * 100, left } : null,
      soFar, next: nextEvent(t, p), todo: todoOf(t, p), pay,
      size: Number(b.size ?? 0),
    });
  }
  return out;
}

/** Short first, then thin, then the rest; the biggest position first in each group (Nik, D2). */
export const railRank = (a: RailName, b: RailName) => b.st - a.st || b.size - a.size || a.t.localeCompare(b.t);

/** The order a book's names took the first time they were drawn this session: they never re-sort as prices move. */
const ORDER = new Map<string, string[]>();
export function inSessionOrder(book: string, names: RailName[]): RailName[] {
  const ranked = names.slice().sort(railRank);
  const seen = ORDER.get(book) ?? [];
  const known = new Set(seen);
  const order = seen.concat(ranked.filter((n) => !known.has(n.t)).map((n) => n.t));
  ORDER.set(book, order);
  const at = new Map(order.map((t, i) => [t, i]));
  return names.slice().sort((a, b) => (at.get(a.t) ?? 0) - (at.get(b.t) ?? 0));
}

/* ── The Time value sheet and the rail's button row (brief.timeValue, sunny-home brief.ts: every sold leg still open) ── */
export interface TvLeg { t: string; name: string; K: number; q: number; put: boolean; col: number; tvLeft: number; tvPer: number;
  intr: number; itm: boolean; cap: number; ready: boolean }

export function tvLegs(p: J): TvLeg[] {
  return ((p?.brief?.timeValue?.legs ?? []) as J[]).map((l) => ({
    t: String(l.t), name: String(l.name ?? l.t), K: Number(l.K), q: Number(l.q), put: !!l.put, col: Number(l.col ?? 0),
    tvLeft: Number(l.tvLeft ?? 0), tvPer: Number(l.tvPer ?? 0), intr: Number(l.intr ?? 0), itm: !!l.itm, cap: Number(l.cap ?? 0),
    ready: !!l.ready,
  }));
}
/** Ready to roll (the server's rule: under $0.05 a share left, 90% captured, or in the money): in the money first
    (assignment risk), then the most captured. */
export const readyToRoll = (legs: TvLeg[]) =>
  legs.filter((l) => l.ready).sort((a, b) => (a.itm !== b.itm ? (a.itm ? -1 : 1) : a.itm ? 0 : b.cap - a.cap));
/** "109" or "36.5": a strike as the design writes it in a leg. */
export const strike = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));
