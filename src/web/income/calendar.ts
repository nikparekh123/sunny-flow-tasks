// The Income calendar (handoff 2026-11-24 late §1.3; SunnyIncomeCal.dc.html renderVals, web: head false, Week |
// Month, quiet fold): every rung inside its expiry day. This file only says the server's rungs the way the design
// does; every figure (kept %, in the money by, where a rung rolls to and for what) is the Home payload's `income`.
//
//   Range: Month is the 4 weeks Mon to Fri from this week's Monday (the coming Monday on a weekend); Week is one of
//   them. Market holidays (payload.calendar, each name's cal) read Closed and fade, as past days do.
//   One ticker: a tile a rung on its day (strike ×count, the big % kept, the action; Week adds the why).
//   All: a line a name a day (Roll | N to roll | In the money | the %; Week adds the strike and the action); the
//   names running on their own fold behind one grey line.
//   The day the next rung lands is dashed: the name's nextEx on All, each nearest rung's next.ex on one ticker.
// Never a strike the server did not give (next.K null: no strike), no minus signs (red says it), no em dashes.
import type { J } from '../lib/data';
import { price } from '../lib/format';
import { cadWord, f2, fk, GRN, QT, RED, W, type Income, type IncName, type Next, type Rung } from './model';

export type View = 'w' | 'm';
export type St = 'itm' | 'act' | 'run';

export const DN = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, dd }; };
const addDays = (d: string, n: number) => { const { y, m, dd } = ymd(d); return new Date(Date.UTC(y, m - 1, dd + n)).toISOString().slice(0, 10); };
const wdOf = (d: string) => { const { y, m, dd } = ymd(d); return new Date(Date.UTC(y, m - 1, dd)).getUTCDay(); };
const md = (d: string) => { const { m, dd } = ymd(d); return `${MON[m - 1]} ${dd}`; };
/** "Nov 23 to 27", "Nov 30 to Dec 4". */
const range = (a: string, b: string) => (ymd(a).m === ymd(b).m ? `${md(a)} to ${ymd(b).dd}` : `${md(a)} to ${md(b)}`);
/** "A", "A and B", "A, B and C". */
const and = (a: string[]) => (a.length < 2 ? a.join('') : `${a.slice(0, -1).join(', ')} and ${a[a.length - 1]}`);
const side = (r: Rung) => (r.ty === 'c' ? ' call' : ' put');

export interface Day { d: string; w: number; i: number; dd: number; mo: string; today: boolean; past: boolean; closed: boolean }

/** The 20 weekdays on screen: Mon to Fri, four weeks from this week's Monday (the coming Monday on a weekend). */
export function daysOf(today: string, closed: Set<string>): Day[] {
  const wd = wdOf(today), mon = addDays(today, wd === 6 ? 2 : wd === 0 ? 1 : -(wd - 1));
  const out: Day[] = [];
  for (let w = 0; w < 4; w++) for (let i = 0; i < 5; i++) {
    const d = addDays(mon, 7 * w + i), { m, dd } = ymd(d);
    out.push({ d, w, i, dd, mo: MON[m - 1], today: d === today, past: d < today, closed: closed.has(d) });
  }
  return out;
}

/** The market's closed days: the payload's calendar, and any day a name's own calendar marks closed. */
export function closedDays(payload: J, inc: Income): Set<string> {
  const s = new Set<string>();
  const cal: J[] = Array.isArray(payload?.calendar) ? payload.calendar : [];
  for (const c of cal) if (c?.kind === 'closed' && c.date) s.add(String(c.date).slice(0, 10));
  for (const n of inc.names) for (const c of n.cal ?? []) if (c.closed) s.add(c.d);
  return s;
}

/* ── A rung on its day ───────────────────────────────────────────────────── */
export interface Tile {
  k: string; st: St; rank: number; kp: number; nm: string; big: string; bw: string; bc: string;
  act: string; sub: string; ring: string; word: string; aria: string;
}
export const RING: Record<St, string> = { itm: `inset 0 0 0 1.5px ${RED}`, act: 'inset 0 0 0 1px rgba(101,196,102,.65)', run: 'inset 0 0 0 1px rgba(255,255,255,.06)' };

/** "Roll to Dec 7 157.5 · 7.50"; no strike (and so no premium) when the server has none for that day. */
const rollTo = (nx: Next | null) => (nx ? `Roll to ${nx.exL}${nx.K != null ? ` ${fk(nx.K)}${nx.pr != null ? ` · ${f2(nx.pr)}` : ''}` : ''}` : 'Roll');
/** Why a ready rung rolls (Week): the next one's premium against this one and its SD, or wait for 95%. */
const rollWhy = (r: Rung) => {
  const nx = r.next, g: string[] = [];
  if (nx && nx.K != null) {
    if (nx.d != null) g.push(Math.abs(nx.d) < 0.005 ? 'the same as this one' : `${nx.d > 0 ? '↑' : '↓'} ${f2(nx.d)} vs this one`);
    g.push(`${fk(nx.z)} SD from today`);
  }
  if (r.kp != null && r.kp < 95) g.push('or wait for 95%');
  return g.join(' · ');
};

/** One rung (SunnyIncomeCal leg): the big % kept (grey running, green ready to roll, red in the money or at a
    loss), the action only when it needs you, the why only when there is room (Week). */
export function tileOf(n: IncName, r: Rung, why: boolean): Tile {
  const st: St = r.st === 'itm' ? 'itm' : r.st === 'roll' ? 'act' : 'run';
  const kp = r.kp ?? 0, lo = r.kp != null && r.kp < 0, bc = st === 'itm' || lo ? RED : st === 'act' ? GRN : QT;
  const nm = `${fk(r.K)}${side(r)} ×${r.q}`;
  const act = st === 'itm' ? `In the money by ${f2(r.intr)}` : st === 'act' ? rollTo(r.next) : '';
  const sub = st === 'itm' ? `Breakeven ${f2(r.be)} · you decide`
    : !why ? ''
    : st === 'act' ? rollWhy(r)
    : [lo && r.mk != null ? `Down ${f2(r.mk - r.at)} a share` : r.kp != null ? `${90 - r.kp}% to the roll` : '', `sold at ${f2(r.at)}`].filter(Boolean).join(' · ');
  const big = r.kp == null ? '' : `${Math.abs(r.kp)}%`, bw = r.kp == null ? '' : lo ? 'lost' : 'kept';
  return {
    k: r.k, st, rank: st === 'itm' ? 0 : st === 'act' ? 1 : 2, kp, nm, big, bw, bc, act, sub, ring: RING[st],
    word: st === 'itm' ? 'In the money' : st === 'act' ? 'Roll' : big,
    aria: `${n.t} ${nm}${big ? `, ${big} ${bw}` : ''}${act ? `. ${act}` : ''}`,
  };
}

/* ── A day's content ─────────────────────────────────────────────────────── */
export interface Row { k: string; t: string; tc: string; word: string; wc: string; rank: number; kp: number; why: string; aria: string }
export interface Nx { k: string; top: string; main: string }
export interface Content { tiles: Tile[]; rows: Row[]; more: string; nx: Nx[]; empty: boolean }

export interface Cal {
  names: IncName[];
  /** Each name's rungs, by expiry day. */
  by: Map<string, Map<string, Rung[]>>;
}
export function calOf(inc: Income): Cal {
  const by = new Map<string, Map<string, Rung[]>>();
  for (const r of inc.rungs) {
    const m = by.get(r.t) ?? new Map<string, Rung[]>();
    m.set(r.ex, [...(m.get(r.ex) ?? []), r]);
    by.set(r.t, m);
  }
  return { names: inc.names, by };
}

/** A name's rungs on a day: in the money first, then ready to roll, then running; calls before puts, by strike. */
const tilesOn = (c: Cal, n: IncName, d: string, why: boolean) => (c.by.get(n.t)?.get(d) ?? [])
  .slice().sort((a, b) => (a.ty === b.ty ? 0 : a.ty === 'c' ? -1 : 1) || a.K - b.K)
  .map((r) => tileOf(n, r, why)).sort((a, b) => a.rank - b.rank);

/** On one ticker, where its next rungs land: one dashed box a rung on the name's nearest expiry, on its next.ex. */
function nxOne(c: Cal, n: IncName, d: string): Nx[] {
  const m = c.by.get(n.t);
  if (!m || !m.size) return [];
  const e0 = [...m.keys()].sort()[0];
  return (m.get(e0) ?? []).filter((r) => r.next && r.next.ex === d)
    .sort((a, b) => (a.ty === b.ty ? 0 : a.ty === 'c' ? -1 : 1) || a.K - b.K)
    .map((r) => {
      const nx = r.next!;
      const main = nx.K != null ? `${fk(nx.K)}${side(r)}${nx.pr != null ? ` · ${f2(nx.pr)}` : ''}` : (r.ty === 'c' ? 'Call' : 'Put');
      return { k: `nx${r.k}`, top: `Next · from ${r.exL}’s ${fk(r.K)}${side(r)}`, main };
    });
}

/** What one day holds, for one ticker or for All (SunnyIncomeCal content). */
export function contentOf(c: Cal, scope: IncName[], one: IncName | null, x: Day, why: boolean, fold: boolean): Content {
  if (x.closed) return { tiles: [], rows: [], more: '', nx: [], empty: true };
  if (one) {
    const tiles = tilesOn(c, one, x.d, why), nx = nxOne(c, one, x.d);
    return { tiles, rows: [], more: '', nx, empty: !tiles.length && !nx.length };
  }
  const rs: Row[] = [];
  for (const n of scope) {
    const l = tilesOn(c, n, x.d, false);
    if (!l.length) continue;
    const t0 = l[0], nN = l.filter((z) => z.rank < 2).length;
    const word = t0.st === 'act' && nN > 1 ? `${nN} to roll` : t0.word;
    const same = l.every((z) => z.bw === t0.bw);
    const wy = t0.st !== 'run' ? `${t0.nm} · ${t0.act}`
      : l.length === 1 ? `${t0.nm} · ${t0.big} ${t0.bw}`
      : `${l.length} legs · ${same ? `${l.map((z) => z.big).join(' and ')} ${t0.bw}` : l.map((z) => `${z.big} ${z.bw}`).join(' and ')}`;
    rs.push({ k: n.t, t: n.t, tc: t0.st === 'run' ? QT : W, word, wc: t0.bc, rank: t0.rank, kp: t0.kp, why: why ? wy : '',
      aria: `Open ${n.t}: ${l.map((z) => z.aria).join('; ')}` });
  }
  rs.sort((a, b) => a.rank - b.rank || b.kp - a.kp);
  const rows = fold ? rs.filter((r) => r.rank < 2) : rs, q9 = rs.filter((r) => r.rank === 2);
  const more = fold && q9.length ? (why ? `${q9.length}${rows.length ? ' more' : ''} running on their own · ${and(q9.map((r) => r.t))}` : `+${q9.length} running`) : '';
  const lnd = scope.filter((n) => n.nextEx === x.d);
  const nx: Nx[] = lnd.length ? [{ k: 'nxA', top: 'Next rungs', main: and(lnd.map((n) => n.t)) }] : [];
  return { tiles: [], rows, more, nx, empty: !rows.length && !more && !nx.length };
}

/** The day's label: "Nov 23" on the first day and the first day of a month (every day on Week), else the date. */
export const dayLabel = (x: Day, days: Day[], week: boolean) => {
  const prev = days[x.w * 5 + x.i - 1];
  return week || (x.w === 0 && x.i === 0) || (prev && prev.mo !== x.mo) ? `${x.mo} ${x.dd}` : String(x.dd);
};

/** The day for a screen reader: what is on it, or that nothing expires. */
export function dayAria(x: Day, ct: Content): string {
  const said = [...ct.tiles.map((l) => l.aria), ...ct.rows.map((r) => `${r.t} ${r.word}`), ...(ct.more ? [ct.more] : []), ...ct.nx.map((z) => `${z.top} ${z.main}`)];
  return `${DN[x.i]} ${x.mo} ${x.dd}${x.today ? ', today' : ''}${x.closed ? ', market closed' : said.length ? `: ${said.join('; ')}` : ', nothing expires'}`;
}

/* ── The status line: one big count of what needs you ────────────────────── */
export interface Status { big: number; c: string; w: string; wc: string; sub: string }
export function statusOf(inc: Income, scope: IncName[], one: IncName | null): Status {
  const ts = new Set(scope.map((n) => n.t)), sold = inc.rungs.filter((r) => ts.has(r.t));
  const itmN = sold.filter((r) => r.st === 'itm').length, rollN = sold.filter((r) => r.st === 'roll').length, need = itmN + rollN;
  const near = sold.filter((r) => r.st === 'hold' && r.kp != null && r.kp >= 0 && r.kp < 90).sort((a, b) => (b.kp ?? 0) - (a.kp ?? 0))[0];
  const sub = need ? [itmN ? `${itmN} in the money` : '', rollN ? `${rollN} to roll` : ''].filter(Boolean).join(' · ')
    : near ? `Nearest roll · ${one ? '' : near.t + ' '}${fk(near.K)}${side(near)} at ${near.kp}%`
    : sold.length ? `${sold.length} running` : 'Nothing sold';
  return { big: need, c: itmN ? RED : GRN, w: need ? (need === 1 ? 'needs you' : 'need you') : 'All quiet', wc: need ? W : QT, sub };
}

/** Under the name: price, today's move, whose (Together) and the cadence; on All, how many names. */
export function ctxSub(n: IncName | null, scope: IncName[], together: boolean): string {
  if (!n) return `${scope.length} ${scope.length === 1 ? 'name' : 'names'}${together ? ' · Sunny and Nicolay' : ''}`;
  const chg = n.chg != null ? `${n.chg < 0 ? '↓' : '↑'}${Math.abs(n.chg).toFixed(1)}% today` : '';
  return [price(n.px), chg, together && n.books.length ? n.books.join(' and ') : '', cadWord(n)].filter(Boolean).join(' · ');
}

/** The range line: "Nov 23 to 27" over "This week · today Tue Nov 24"; Month "Nov 23 to Dec 18" over "4 weeks". */
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
export function rangeOf(days: Day[], view: View, wk: number, today: string): { t: string; s: string } {
  const wd = wdOf(today), td = `today ${WD[wd]} ${md(today)}`;
  if (view === 'm') return { t: range(days[0].d, days[19].d), s: `4 weeks · ${td}` };
  const ws = days.filter((x) => x.w === wk);
  // Weeks from today's own week: 0 this week, 1 next week (on a weekend the grid starts on next week).
  const off = wk + (wd === 0 || wd === 6 ? 1 : 0);
  const lbl = off === 0 ? 'This week' : off === 1 ? 'Next week' : `In ${off} weeks`;
  return { t: range(ws[0].d, ws[4].d), s: `${lbl}${ws.some((x) => x.today) ? ` · ${td}` : ''}` };
}
