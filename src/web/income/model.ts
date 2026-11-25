// Income (handoff 2026-11-24 §1 and handoff-2026-11-24-income, SunnyIncome.dc.html): the words and colours of Income
// today and the Income tab, from the Home payload's `income` (sunny-home income.ts). Every figure is the server's:
// each rung (a call or put sold and still open) with its kept %, SD from the strike, where a ready one rolls to and
// for what; each name's price, cadence, delta line and small calendar; the totals; the realized income banner.
// This file only says it the way the design does (SunnyIncome renderVals: ln9 for a rung row, fx9 for the delta line,
// the banner's periods and scale).
//
// Nik's rules: ready to roll at 90% kept, 95% shown too ("or wait for 95%"); in the money is flagged only, never
// advice; no minus signs (red says it); no em dashes; never invent a strike (no chain, "Ready to roll").
import type { J } from '../lib/data';
import { shortDate } from '../lib/clock';

export const W = '#F5F5F7', MU = '#98989D', QT = '#AEAEB2', RED = '#FF6961', GRN = '#65C466', ONW = '#000000', TRK = '#2C2C2E';
/** Calls and puts in the banner (dark): calls #86A8F0, puts #C8946A; a loss in red tones. */
export const CC = '#86A8F0', PC = '#C8946A', CC_LOSS = '#FF6961', PC_LOSS = 'rgba(255,105,97,.5)';
export const ln = (a: number) => `rgba(255,255,255,${a})`;

export interface Next { ex: string; exL: string; K: number | null; pr: number | null; z: number; d: number | null }
export interface Rung {
  k: string; t: string; ty: 'c' | 'p'; K: number; ex: string; exL: string; days: number; td: number; q: number;
  at: number; mk: number | null; kp: number | null; sN: number | null; s0: number | null; itm: boolean; intr: number; be: number;
  books: string[]; st: 'itm' | 'roll' | 'hold'; next: Next | null;
}
export interface Chip { k: 'c' | 'p' | 'n'; q: number; t: string; tone: 'itm' | 'roll' | 'run' | 'next' }
export interface Cell { d: string; lbl: string; today: boolean; past: boolean; closed: boolean; chips: Chip[] }
export interface IncName {
  t: string; co: string; books: string[]; cad: 'ladder' | 'weekly' | 'daily'; px: number; chg: number | null;
  flip: { now: boolean; price: number | null; up: number | null } | null; nextEx: string | null; cal: Cell[];
}
export interface Period { k: string; l: string; c: number; p: number; by: Record<string, [number, number]>; bk: Record<string, [number, number]>; cur: boolean;
  /* weeks */ from?: string | null; to?: string; range?: string; /* months */ long?: string }
export interface Banner { start: string; capital: number; weeks: Period[]; months: Period[];
  shares: Record<string, { sh: number; paid: number | null; avg: number | null; co: string }> }
export interface Income {
  v: number; today: string; rungs: Rung[]; names: IncName[];
  totals: { left: number; kept: number; collected: number; roll: number; itm: number };
  banner: Banner | null;
}

/** The payload's income block, or null when the build has none. */
export function readIncome(payload: J): Income | null {
  const x = payload?.income;
  if (!x || !Array.isArray(x.rungs) || !Array.isArray(x.names)) return null;
  const b = x.banner;
  return {
    v: +x.v || 1, today: String(x.today ?? payload?.today ?? ''), rungs: x.rungs as Rung[], names: x.names as IncName[],
    totals: { left: +x.totals?.left || 0, kept: +x.totals?.kept || 0, collected: +x.totals?.collected || 0, roll: +x.totals?.roll || 0, itm: +x.totals?.itm || 0 },
    banner: b && Array.isArray(b.weeks) && Array.isArray(b.months) ? { start: String(b.start ?? ''), capital: +b.capital || 0, weeks: b.weeks, months: b.months, shares: b.shares ?? {} } : null,
  };
}

/* ── Words ──────────────────────────────────────────────────────────────── */
export const f2 = (x: number) => Math.abs(x).toFixed(2);
/** A strike as the design writes it: 36, 36.5, 167.5. */
export const fk = (x: number) => String(+(+x).toFixed(2));
const side = (r: Rung) => (r.ty === 'c' ? 'call' : 'put');
const daysLeft = (d: number) => (d <= 0 ? 'expires today' : d === 1 ? '1 day left' : `${d} days left`);
const cap1 = (s: string) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);

/** One rung as a row (SunnyIncome ln9, README §1.2): the big kept %, the title with its date, the action with the
    one figure that decides it, and a grey line only when there is something to do. */
export interface Line {
  k: string; big: string; bigC: string; title: string; titleC: string; date: string; act: string; actC: string; grey: string | null; aria: string;
}
export function lineOf(r: Rung, withTicker: boolean): Line {
  const itm = r.st === 'itm', roll = r.st === 'roll', kp = r.kp, loss = kp != null && kp < 0;
  const kk = `${withTicker ? r.t + ' ' : ''}${fk(r.K)} ${side(r)} ×${r.q}`;
  const big = kp == null ? '-' : `${Math.abs(kp)}%`;
  // Red when in the money or at a loss, green when ready to roll, grey otherwise; the action wears the same colour.
  const bigC = itm || loss ? RED : roll ? GRN : QT;
  const nx = r.next;
  let act = '';
  if (itm) act = `In the money by ${f2(r.intr)}`;
  else if (roll) act = nx && nx.K != null ? `to ${nx.exL} ${fk(nx.K)}${nx.pr != null ? ` for ${f2(nx.pr)}` : ''}` : 'Ready to roll';
  else if (loss && r.mk != null) act = `Down ${f2(r.mk - r.at)} a share`;
  else if (kp != null) act = `${90 - kp}% to the roll`;
  let grey: string | null = null;
  if (itm) grey = `Breakeven ${f2(r.be)} · ${daysLeft(r.days)} · flagged, you decide`;
  else if (roll) {
    const g: string[] = [];
    if (nx && nx.K != null) {
      if (nx.d != null) g.push(Math.abs(nx.d) < 0.005 ? 'the same as this one' : `${nx.d > 0 ? '↑' : '↓'} ${f2(nx.d)} vs this one`);
      g.push(`${fk(nx.z)} SD from today`);
    } else if (nx) g.push(`no strikes listed for ${nx.exL} yet`);
    if (kp != null && kp < 95) g.push('or wait for 95%');
    grey = g.length ? cap1(g.join(' · ')) : null;
  }
  const title = (itm ? '' : roll ? 'Roll ' : 'Hold ') + kk;
  const state = itm ? 'in the money' : roll ? 'ready to roll' : loss ? 'lost' : 'kept';
  return {
    k: r.k, big, bigC, title, titleC: itm || roll ? W : QT, date: r.exL, act, actC: bigC, grey,
    aria: `${title}, ${r.exL}, ${big} ${state}${act ? ', ' + act : ''}${grey ? '. ' + grey : ''}`,
  };
}

/** The delta line for a name that sells on several Fridays (fx9): how far the stock can rise before the name's book
    turns short, red inside 3%. */
export interface Flip { big: string; bigC: string; a: string; b: string }
export function flipOf(n: IncName): Flip | null {
  if (n.cad !== 'ladder' || !n.flip) return null;
  const f = n.flip;
  // Already short at today's price (book-engine turnsShort `now`): a state the design does not draw; said plainly.
  if (f.now) return { big: 'Now', bigC: RED, a: `${n.t} is short at today’s price`, b: '' };
  if (f.price == null || f.up == null) return { big: '↑40%+', bigC: QT, a: `${n.t} stays long`, b: '' };
  return { big: `↑${Math.abs(f.up).toFixed(1)}%`, bigC: f.up < 3 ? RED : QT, a: `until ${n.t} turns short, at ${f2(f.price)}`,
    b: '' };
}

/** Income today's groups (README §1.3): in the money first (deepest first), then ready to roll (most kept first);
    the rest run on their own, behind one line. */
export function todayGroups(inc: Income) {
  const itm = inc.rungs.filter((r) => r.st === 'itm').sort((a, b) => (a.sN ?? 0) - (b.sN ?? 0));
  const roll = inc.rungs.filter((r) => r.st === 'roll').sort((a, b) => (b.kp ?? 0) - (a.kp ?? 0));
  const quiet = inc.rungs.filter((r) => r.st === 'hold');
  const near = quiet.filter((r) => r.kp != null && r.kp >= 0).sort((a, b) => (b.kp ?? 0) - (a.kp ?? 0))[0];
  const need = itm.length + roll.length;
  const groups = [
    ...(itm.length ? [{ k: 'itm', t: `In the money · you decide · ${itm.length}`, c: RED, rows: itm }] : []),
    ...(roll.length ? [{ k: 'roll', t: `Ready to roll · ${roll.length}`, c: GRN, rows: roll }] : []),
  ];
  const foot = quiet.length
    ? `${quiet.length} more ${quiet.length === 1 ? 'rung runs' : 'rungs run'} on their own` +
      (near ? ` · nearest to a roll: ${near.t} ${fk(near.K)} ${side(near)} ${near.exL} at ${near.kp}%` : '') + '.'
    : inc.rungs.length ? 'Every rung is in the list above.' : null;
  return {
    groups, need, foot,
    needT: need ? `${need} ${need === 1 ? 'needs' : 'need'} you` : 'All quiet',
    needC: itm.length ? RED : need ? GRN : MU,
  };
}

/** The cadence word (the calendar's status line on one ticker): "ladder" (three or more expiries sold; Nicolay sells
    Mon, Wed and Fri expiries, so the design's "three Fridays" would be wrong; the same word as the phone), else
    "weekly" (or "daily"). */
export const cadWord = (n: IncName) => (n.cad === 'ladder' ? 'ladder' : n.cad === 'daily' ? 'daily' : 'weekly');

/* ── The banner: realized income by week or by month ─────────────────────── */
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const addDays = (d: string, n: number) => { const [y, m, dd] = d.split('-').map(Number); const x = new Date(Date.UTC(y, m - 1, dd + n)); return x.toISOString().slice(0, 10); };
const monOf = (d: string) => { const [y, m, dd] = d.split('-').map(Number); const w = new Date(Date.UTC(y, m - 1, dd)).getUTCDay(); return addDays(d, w === 0 ? -6 : -(w - 1)); };
const md = (d: string) => { const [, m, dd] = d.split('-').map(Number); return `${MON[m - 1]} ${dd}`; };

export interface Bar { k: string; l: string; cap: string; pl: string; c: number; p: number; t: number; by: Record<string, [number, number]>; bk: Record<string, [number, number]>; part: boolean }

/** The bars for a view: the last 12 weeks (8 narrow), or every month, from the first one with income; and which one
    opens picked (Weekly on last week, since the weekly names realize on Friday; Monthly on this month so far). */
export function barsOf(b: Banner, vw: 'w' | 'm', today: string, narrow: boolean): { bars: Bar[]; def: number } {
  const m0 = monOf(today), prev = addDays(m0, -7);
  let bars: Bar[] = vw === 'w'
    ? b.weeks.slice(narrow ? -8 : -12).map((w) => {
      const range = w.range ?? `${md(w.k)} to ${md(addDays(w.k, 4))}`;
      const thisWk = w.k === m0;
      return { k: w.k, l: thisWk && !narrow ? 'This week' : w.l, c: +w.c || 0, p: +w.p || 0, t: (+w.c || 0) + (+w.p || 0), by: w.by ?? {}, bk: w.bk ?? {}, part: !!w.cur,
        // Short (Nik, 25 Nov 2026: "This week so far · to Tue Nov 24 is too long"; the same in Monthly): no dates on this
        // week or last week; an older week is "Week of Nov 2 to 6", as SunnyIncome's caption.
        cap: w.cur ? 'This week so far' : thisWk ? 'This week' : w.k === prev ? 'Last week' : `Week of ${range}`,
        pl: w.cur || thisWk ? 'This week' : `Week of ${md(w.k)}` };
    })
    : b.months.map((m) => ({ k: m.k, l: m.l, c: +m.c || 0, p: +m.p || 0, t: (+m.c || 0) + (+m.p || 0), by: m.by ?? {}, bk: m.bk ?? {}, part: !!m.cur,
      // "Nov so far" (README §1.2: the month abbreviated, no dates); a finished month in full ("October"), the first
      // one with the day the book starts ("August · from Aug 31", SunnyIncome's "June · from Jun 15").
      cap: m.cur ? `${m.l} so far` : m.from ? `${m.long ?? m.l} · from ${m.from}` : String(m.long ?? m.l), pl: String(m.long ?? m.l) }));
  const first = bars.findIndex((x) => Math.abs(x.c) >= 0.5 || Math.abs(x.p) >= 0.5);
  bars = first < 0 ? bars.slice(-1) : bars.slice(first);
  const last = bars.length - 1;
  const def = vw === 'w' && bars[last]?.part && last > 0 ? last - 1 : last;
  return { bars, def: Math.max(0, def) };
}

/** A round step for the value scale (1, 2, 2.5 or 5 times a power of ten). */
const nice = (x: number) => { if (!(x > 0)) return 1; const p = Math.pow(10, Math.floor(Math.log10(x))), m = x / p; return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * p; };
/** The scale: room above the baseline for the biggest gain, below it for the biggest loss, on round steps. */
export function scaleOf(bars: Bar[]) {
  let hi = 0, lo = 0;
  for (const x of bars) { hi = Math.max(hi, Math.max(0, x.c) + Math.max(0, x.p)); lo = Math.min(lo, Math.min(0, x.c) + Math.min(0, x.p)); }
  const st = nice((hi - lo) / 4 || 1), top = hi > 0 ? st * Math.ceil(hi / st) : lo < 0 ? 0 : st, bot = lo < 0 ? st * Math.ceil(-lo / st) : 0;
  const lines: number[] = [];
  for (let v = st; v <= top + 1e-6; v += st) lines.push(v);
  for (let v = -st; v >= -bot - 1e-6; v -= st) lines.push(v);
  return { top, bot, lines };
}

/** Yield on a period (the banner's grey line): its income over what the shares cost; a full week or month carries
    "about N% a year", one still running "so far". */
export function yieldOf(t: number, capital: number, part: boolean, vw: 'w' | 'm'): { v: string; a: string } | null {
  if (!(capital > 0) || !(t > 0)) return null;
  const y = (t / capital) * 100;
  return { v: y.toFixed(y < 1 ? 2 : 1) + '%', a: part ? 'so far' : `about ${Math.round(y * (vw === 'w' ? 52 : 12))}% a year` };
}
