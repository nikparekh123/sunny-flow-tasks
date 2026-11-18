// The Home rail as pills (handoff 2026-11-18, README "Web Home rail: SunnyRail layout=pills"; CHANGES Nov 17 "The rail
// as pills" and "The rail's row style"): one row a strike or name, one coloured pill a row with the figure Display
// data picks. The legs and their figures come from the Home payload, never re-derived where the server has them:
//   side.legs                 each leg of the book (key, t, k sc|sp|sh|hc|ip, label, ex, n, today, all, value, base),
//                             sunny-home's Your book pieces: today adds up to Home's today, all is against IBKR's cost
//                             (or, sold, what was collected less the cost to close), base what all is measured on
//   brief.timeValue.legs      tvLeft, the time value still in each sold leg (Left to capture)
//   legs                      each option's mark (Last price); brief_inputs.names S0 the share price
//   side.events               earnings dates (orange under a row)
// A payload built before `side` existed falls back to brief_inputs' legs: today from IBKR's mark at the last close,
// since opened from the fill, as the old rail read them.
// Groups follow Nik's rule of 11 Nov 2026 (kept on 18 Nov): Calls sold, Puts sold, Shares, Hedges (every call bought,
// LEAPS too, and every put bought).
import type { J } from '../../lib/data';
import { count, money, pct, price } from '../../lib/format';
import { dayLabel, strike } from './model';

export type Kind = 'sc' | 'sp' | 'sh' | 'hc' | 'ip';
export type Show = 'td' | 'tr' | 'tp' | 'lc' | 'lp';
export const SHOWS: [Show, string][] = [['td', 'Today’s return'], ['tr', 'Total return'], ['tp', 'Total percent change'], ['lc', 'Left to capture'], ['lp', 'Last price']];
export const showLabel = (s: Show) => SHOWS.find((x) => x[0] === s)![1];

export interface PillLeg {
  key: string; t: string; k: Kind; sold: boolean;
  /** "NKE 36.5 puts", "NKE shares", "NKE 42.5 Hedge calls" */
  l: string;
  /** "10 sold · Fri Nov 27", "3,000 at $39.41", "15 bought · Jan 15" */
  q: string;
  /** "Earnings Thu Nov 19" when it lands before a sold leg expires, or within two weeks for what you own. */
  ev: string;
  today: number; all: number; base: number;
  /** Left to capture: the time value still in a sold leg; null for what you own or when unknown. */
  left: number | null;
  /** Last price: the share price or the option's mark; null when unknown. */
  last: number | null;
  /** The first order: a sold leg by what it would cost to close now, what you own by the size of its result. */
  rank: number;
}

interface Raw { key: string; t: string; k: Kind; label: string; ex: string | null; n: number; today: number; all: number; base: number }

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** The house expiry label: "Nov 20", or "Jan ’28" past six months. */
const exLabel = (ex: string, today: string) => {
  const [y, m, d] = ex.split('-').map(Number);
  return (Date.parse(ex) - Date.parse(today)) / 864e5 > 183 ? `${MON[m - 1]} ’${String(y).slice(2)}` : `${MON[m - 1]} ${d}`;
};

/** The legs from brief_inputs, for a payload with no `side` (built before 18 Nov 2026). */
function fromInputs(p: J): Raw[] {
  const today = String(p?.today ?? '');
  const out: Raw[] = [];
  for (const n of (p?.brief_inputs?.names ?? []) as J[]) {
    const t = String(n.t), S0 = Number(n.S0), Pb = Number(n.Pb ?? n.P0 ?? n.S0);
    if (!(S0 > 0)) continue;
    for (const l of (n.legs ?? []) as J[]) {
      const q = Number(l.q);
      if (!q) continue;
      if (l.ty === 'S') {
        const K = Number(l.K) > 0 ? Number(l.K) : null;
        out.push({ key: `${t}|sh`, t, k: 'sh', label: 'shares', ex: null, n: q, today: q * (S0 - Pb), all: K ? q * (S0 - K) : 0, base: K ? q * K : 0 });
        continue;
      }
      if (l.now == null) continue;
      const sold = q < 0, call = l.ty === 'C', n0 = Math.abs(q), now = Number(l.now), prev = l.prev != null ? Number(l.prev) : now;
      const at = l.at != null ? Number(l.at) : null, ex = String(l.ex);
      const k: Kind = sold ? (call ? 'sc' : 'sp') : (call ? 'hc' : 'ip');
      out.push({ key: `${t}|${k}|${Number(l.K)}|${ex}`, t, k, label: `${strike(Number(l.K))} ${call ? 'calls' : 'puts'} · ${exLabel(ex, today)}`, ex, n: n0,
        today: q * 100 * (now - prev), all: at == null ? 0 : (sold ? n0 * 100 * (at - now) : n0 * 100 * (now - at)), base: at == null ? 0 : n0 * 100 * at });
    }
  }
  return out;
}

/** Every leg held, with what each pill can show. */
export function pillLegs(p: J): PillLeg[] {
  const today = String(p?.today ?? '');
  const side: J[] | null = Array.isArray(p?.side?.legs) ? p.side.legs : null;
  const raw: Raw[] = side
    ? side.filter((l) => Number(l.n) > 0 && ['sc', 'sp', 'sh', 'hc', 'ip'].includes(String(l.k))).map((l) => ({
      key: String(l.key), t: String(l.t), k: String(l.k) as Kind, label: String(l.label ?? ''), ex: l.ex ? String(l.ex) : null,
      n: Number(l.n), today: Number(l.today ?? 0), all: Number(l.all ?? 0), base: Number(l.base ?? 0) }))
    : fromInputs(p);

  // Left to capture, by contract.
  const tv = new Map<string, number>();
  for (const l of (p?.brief?.timeValue?.legs ?? []) as J[]) tv.set(`${l.t}|${l.put ? 'P' : 'C'}|${Number(l.K)}|${l.ex}`, Number(l.tvLeft ?? 0));
  // Last price: each option's mark, each share's price.
  const marks = new Map<string, number>();
  for (const l of (p?.legs ?? []) as J[]) {
    if (l?.mark == null) continue;
    marks.set(`${String(l.ticker).toUpperCase()}|${l.side === 'sold' ? 's' : 'b'}|${l.type === 'put' ? 'P' : 'C'}|${Number(l.strike)}|${l.expiry}`, Number(l.mark));
  }
  const px = new Map<string, number>();
  for (const n of (p?.brief?.names ?? []) as J[]) if (Number(n?.S0) > 0) px.set(String(n.t), Number(n.S0));
  for (const n of (p?.brief_inputs?.names ?? []) as J[]) if (Number(n?.S0) > 0) px.set(String(n.t), Number(n.S0));
  const inputMark = new Map<string, number>();
  for (const n of (p?.brief_inputs?.names ?? []) as J[]) for (const l of (n.legs ?? []) as J[]) {
    if (l.ty === 'S' || l.now == null) continue;
    inputMark.set(`${n.t}|${Number(l.q) < 0 ? 's' : 'b'}|${l.ty}|${Number(l.K)}|${l.ex}`, Number(l.now));
  }
  // The next earnings of each name still ahead.
  const earn = new Map<string, string>();
  for (const e of ((p?.side?.events ?? []) as J[]).filter((x) => x?.kind === 'earnings' && x?.t && String(x.d) >= today).sort((a, b) => String(a.d).localeCompare(String(b.d)))) {
    if (!earn.has(String(e.t))) earn.set(String(e.t), String(e.d));
  }
  const in14 = (() => { const [y, m, d] = today.split('-').map(Number); return y ? new Date(Date.UTC(y, m - 1, d + 14)).toISOString().slice(0, 10) : ''; })();

  return raw.map((x) => {
    const sold = x.k === 'sc' || x.k === 'sp', put = x.k === 'sp' || x.k === 'ip';
    const K = x.k === 'sh' ? NaN : Number(x.key.split('|')[2]);
    const exL = x.label.split(' · ')[1] ?? (x.ex ? exLabel(x.ex, today) : '');
    const what = put ? 'puts' : 'calls';
    const l = x.k === 'sh' ? `${x.t} shares` : `${x.t} ${strike(K)} ${x.k === 'hc' || x.k === 'ip' ? (put ? 'Hedge puts' : 'Hedge calls') : what}`;
    const q = x.k === 'sh' ? (x.base > 0 ? `${count(x.n)} at ${price(x.base / x.n)}` : `${count(x.n)} shares`)
      : sold ? `${count(x.n)} sold · ${x.ex ? dayLabel(x.ex) : exL}` : `${count(x.n)} bought · ${exL}`;
    const e = earn.get(x.t);
    const ev = e && (sold ? !!x.ex && e <= x.ex : e <= in14) ? `Earnings ${dayLabel(e)}` : '';
    const ck = `${x.t}|${put ? 'P' : 'C'}|${K}|${x.ex}`;
    const mk = `${x.t}|${sold ? 's' : 'b'}|${put ? 'P' : 'C'}|${K}|${x.ex}`;
    const last = x.k === 'sh' ? px.get(x.t) ?? null : marks.get(mk) ?? inputMark.get(mk) ?? null;
    return { key: x.key, t: x.t, k: x.k, sold, l, q, ev, today: x.today, all: x.all, base: x.base,
      left: sold ? tv.get(ck) ?? null : null, last, rank: sold ? x.base - x.all : Math.abs(x.all) };
  });
}

/** A pill: its words and colour (green made, red lost, grey neither or not a result). */
export interface Pill { v: string; tone: 'g' | 'r' | 'n'; money: boolean }
const toneOf = (v: number): Pill['tone'] => (v > 0 ? 'g' : v < 0 ? 'r' : 'n');
export function pillOf(x: PillLeg, s: Show): Pill {
  if (s === 'td') { const v = Math.round(x.today); return { v: money(v), tone: toneOf(v), money: true }; }
  if (s === 'tr') { const v = Math.round(x.all); return { v: money(v), tone: toneOf(v), money: true }; }
  if (s === 'tp') { const f = x.base > 0 ? (x.all / x.base) * 100 : 0; return { v: pct(f), tone: Math.abs(f) < 0.005 ? 'n' : toneOf(f), money: false }; }
  if (s === 'lc') return { v: x.left != null ? money(x.left) : '-', tone: 'n', money: true };
  return { v: x.last != null ? price(x.last) : '-', tone: 'n', money: false };
}

/** A section's figure beside its title: the sum (Total percent change: the sums divided); Left to capture the sold
    legs' time value "to come"; nothing for Last price. Colour: 'g', 'r' or 'n'. */
export function totalOf(xs: PillLeg[], s: Show): { v: string; tone: Pill['tone'] } {
  if (s === 'lp') return { v: '', tone: 'n' };
  if (s === 'lc') {
    const so = xs.filter((x) => x.sold && x.left != null);
    return so.length ? { v: `${money(so.reduce((a, x) => a + (x.left ?? 0), 0))} to come`, tone: 'n' } : { v: '', tone: 'n' };
  }
  if (s === 'tp') {
    const all = xs.reduce((a, x) => a + x.all, 0), base = xs.reduce((a, x) => a + x.base, 0), f = base > 0 ? (all / base) * 100 : 0;
    return { v: pct(f), tone: Math.abs(f) < 0.005 ? 'n' : toneOf(f) };
  }
  const v = Math.round(xs.reduce((a, x) => a + (s === 'td' ? x.today : x.all), 0));
  return { v: money(v), tone: toneOf(v) };
}

export interface PillSection { k: string; h: string; px?: number; mv?: number; rows: PillLeg[] }
const GROUPS: [string, string, Kind[]][] = [['cs', 'Calls sold', ['sc']], ['ps', 'Puts sold', ['sp']], ['sh', 'Shares', ['sh']], ['hg', 'Hedges', ['hc', 'ip']]];
const KIND_ORDER: Record<Kind, number> = { sc: 0, sp: 0, sh: 1, hc: 2, ip: 2 };

/** The order rows took the first time they were drawn this session (Nik: numbers tick, rows never move under the
    eye); new rows join at the end in their ranked place. */
const SEEN = new Map<string, string[]>();
function stable(id: string, ranked: PillLeg[]): PillLeg[] {
  const by = new Map(ranked.map((x) => [x.key, x]));
  const keys = (SEEN.get(id) ?? []).filter((k) => by.has(k));
  for (const x of ranked) if (!keys.includes(x.key)) keys.push(x.key);
  SEEN.set(id, keys);
  return keys.map((k) => by.get(k)!);
}

/** What you hold: Calls sold, Puts sold, Shares, Hedges, the empty ones left out. Sold legs the dearest to close
    first; what you own the biggest result first. */
export function byHold(book: string, legs: PillLeg[]): PillSection[] {
  return GROUPS.map(([k, h, ks]) => {
    const rows = legs.filter((x) => ks.includes(x.k)).sort((a, b) => b.rank - a.rank);
    return { k, h, rows: stable(`${book}|hold|${k}`, rows) };
  }).filter((s) => s.rows.length > 0);
}

/** By name, in the rail's order of names: what was sold first, then shares, then hedges. */
export function byName(book: string, legs: PillLeg[], names: { t: string; px: number; mv: number }[]): PillSection[] {
  const seen = new Set(names.map((n) => n.t));
  const list = [...names, ...[...new Set(legs.map((x) => x.t))].filter((t) => !seen.has(t)).map((t) => ({ t, px: NaN, mv: NaN }))];
  return list.map((n) => {
    const rows = legs.filter((x) => x.t === n.t).sort((a, b) => KIND_ORDER[a.k] - KIND_ORDER[b.k] || b.rank - a.rank);
    return { k: n.t, h: n.t, px: n.px, mv: n.mv, rows: stable(`${book}|name|${n.t}`, rows) };
  }).filter((s) => s.rows.length > 0);
}
