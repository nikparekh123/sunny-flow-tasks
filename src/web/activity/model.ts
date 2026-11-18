// Activity (handoff 2026-11-18, round 161a + 161c; SunnyActivity.dc.html): what happened, when, in order. Home keeps
// where things stand. The server (sunny-home activity.ts) sends payload.activity in each book's Home payload:
//   sync    IBKR's last good run and whether it has stopped (two runs missed in market hours)
//   events  the last eight days, newest first: IBKR pickups (every trade inside), expirations and dividends; levels
//           (the 20, 50 and 200-day, this week's walls) and big moves on the names held
//   levels  each held name against its averages (ma: '1' over, '0' under, '-' no data, for 20, 50, 200) and the walls
// Older payloads have no `activity`: no bell and no Levels card then.
// What has been read is kept per book on this computer (localStorage `activity.read.<book>`, the newest 400 keys).
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { BookId, J } from '../lib/data';
import { clock12, ny } from '../lib/clock';
import { clean } from '../lib/format';

export type Kind = 'ibkr' | 'lvl' | 'move';
export interface ActTrade { t: string; what: string; at: string; st: string }
export interface ActEvent { key: string; day: string; at: string; kind: Kind; t: string | null; title: string; body: string; opens: string; trades: ActTrade[] }
export interface ActLevel { t: string; name: string; px: number; mv: number | null; ma: string; wall: 'c' | 'f' | 'b'; wallK: number | null }
export interface Activity { today: string; sync: { at: string | null; stopped: boolean }; events: ActEvent[]; levels: ActLevel[] }

const KINDS = new Set<Kind>(['ibkr', 'lvl', 'move']);
const str = (v: unknown) => (v == null ? '' : String(v));
const num = (v: unknown) => (v != null && v !== '' && Number.isFinite(Number(v)) ? Number(v) : null);

/** payload.activity read safely; null when the payload has none (an older build). */
export function readActivity(p: J): Activity | null {
  const a = p?.activity;
  if (!a || typeof a !== 'object') return null;
  const events: ActEvent[] = ((Array.isArray(a.events) ? a.events : []) as J[])
    .filter((e) => e?.key && /^\d{4}-\d{2}-\d{2}$/.test(str(e.day)) && KINDS.has(e.kind))
    .map((e) => ({
      key: str(e.key), day: str(e.day), at: str(e.at), kind: e.kind as Kind, t: e.t ? str(e.t).toUpperCase() : null,
      title: clean(str(e.title)), body: clean(str(e.body)), opens: clean(str(e.opens)),
      trades: ((Array.isArray(e.data?.trades) ? e.data.trades : []) as J[]).filter((x) => x?.what)
        .map((x) => ({ t: str(x.t).toUpperCase(), what: clean(str(x.what)), at: clean(str(x.at)), st: str(x.st) })),
    }))
    .sort((x, y) => y.at.localeCompare(x.at));
  const levels: ActLevel[] = ((Array.isArray(a.levels) ? a.levels : []) as J[]).filter((l) => l?.t)
    .map((l) => ({ t: str(l.t).toUpperCase(), name: clean(str(l.name || l.t)), px: num(l.px) ?? 0, mv: num(l.mv), ma: str(l.ma).padEnd(3, '-').slice(0, 3),
      wall: l.wall === 'c' || l.wall === 'f' ? l.wall : 'b', wallK: num(l.wallK) }));
  const today = /^\d{4}-\d{2}-\d{2}$/.test(str(p?.today)) ? str(p.today) : ny().date;
  return { today, sync: { at: a.sync?.at ? str(a.sync.at) : null, stopped: !!a.sync?.stopped }, events, levels };
}

/* ── Days ─────────────────────────────────────────────────────────────────── */
const DAY = 864e5;
const utc = (iso: string) => { const [y, m, d] = iso.split('-').map(Number); return Date.UTC(y, m - 1, d); };
const isoOf = (t: number) => new Date(t).toISOString().slice(0, 10);

export type Group = 'today' | 'yday' | 'week' | 'last';
export interface Days { today: string; yday: string; mon: string; label: Record<Group, string> }

/** The day groups from the server's today: Yesterday is the weekday before (Monday counts the previous Friday; on a
    Sunday it reads Friday), Earlier this week runs from Monday, anything before it is Last week. */
export function daysOf(today: string): Days {
  const t0 = utc(today), wd = new Date(t0).getUTCDay();
  let y = t0 - DAY;
  while ([0, 6].includes(new Date(y).getUTCDay())) y -= DAY;
  return { today, yday: isoOf(y), mon: isoOf(t0 - ((wd + 6) % 7) * DAY),
    label: { today: 'Today', yday: wd === 0 ? 'Friday' : 'Yesterday', week: 'Earlier this week', last: 'Last week' } };
}
export function groupOf(day: string, d: Days): Group {
  if (day === d.today) return 'today';
  if (day === d.yday) return 'yday';
  return day >= d.mon && day < d.today ? 'week' : 'last';
}

/** An instant as New York time: "2:08 PM", with the weekday ("Mon 2:08 PM") when `wd`. */
export function nyTime(iso: string, wd = false): string {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return '';
  const n = ny(new Date(t));
  return (wd ? n.wd + ' ' : '') + clock12(n);
}
/** An event's time: the clock alone today and yesterday, the weekday too before that. */
export const eventTime = (e: ActEvent, g: Group) => nyTime(e.at, g === 'week' || g === 'last');

/** The sync line: "IBKR synced 12:30 PM" (the weekday too when the last run was another day), or the stop. */
export function syncWords(a: Activity): { title: string; sub: string; dot: 'g' | 'r' | 'q' } {
  const at = a.sync.at, other = !!at && ny(new Date(at)).date !== a.today, tm = at ? nyTime(at, other) : '';
  if (a.sync.stopped) return { title: `No data from IBKR since ${tm || 'the open'}`, sub: 'New trades come in when it reconnects.', dot: 'r' };
  if (!at) return { title: 'No IBKR sync this week', sub: 'Trades show here once IBKR sends them.', dot: 'q' };
  const wd = new Date(utc(a.today)).getUTCDay();
  const n = a.events.filter((e) => e.day === a.today && e.kind === 'ibkr').reduce((s, e) => s + e.trades.length, 0);
  const sub = wd === 0 || wd === 6 ? 'Markets closed' : n ? `${n} ${n === 1 ? 'trade' : 'trades'} picked up today` : 'No trades yet today';
  return { title: `IBKR synced ${tm}`, sub, dot: 'g' };
}

/* ── Read state (per book, this computer) ─────────────────────────────────── */
const CAP = 400;
const storeKey = (b: BookId) => `activity.read.${b}`;
// A private window may refuse storage: what is read then lasts for this visit.
const mem = new Map<BookId, string[]>();
function load(b: BookId | null | undefined): string[] {
  if (!b) return [];
  try {
    const raw = localStorage.getItem(storeKey(b));
    if (raw != null) {
      const v = JSON.parse(raw);
      if (Array.isArray(v)) return v.filter((x): x is string => typeof x === 'string');
    }
  } catch { /* fall back to this visit's list */ }
  return mem.get(b) ?? [];
}
function save(b: BookId, keys: string[]) {
  mem.set(b, keys);
  try { localStorage.setItem(storeKey(b), JSON.stringify(keys)); } catch { /* kept in memory */ }
}

/** The keys read in this book, and a way to mark more. */
export function useReadKeys(book: BookId | null | undefined) {
  const [rev, setRev] = useState(0);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const read = useMemo(() => new Set(load(book)), [book, rev]);
  // Another tab marking lines read moves the count here too.
  useEffect(() => {
    if (!book) return;
    const f = (e: StorageEvent) => { if (e.key === storeKey(book)) setRev((r) => r + 1); };
    window.addEventListener('storage', f);
    return () => window.removeEventListener('storage', f);
  }, [book]);
  const mark = useCallback((keys: string[]) => {
    if (!book || !keys.length) return;
    const cur = load(book), have = new Set(cur), add = keys.filter((k) => !have.has(k));
    if (!add.length) return;
    save(book, [...cur, ...add].slice(-CAP));
    setRev((r) => r + 1);
  }, [book]);
  return { read, mark };
}

/** Today's events not yet read: the bell's count. */
export const unreadToday = (a: Activity | null, read: Set<string>) => (a ? a.events.filter((e) => e.day === a.today && !read.has(e.key)) : []);
