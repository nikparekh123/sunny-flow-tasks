// ── Overview, both books together (handoff 2026-11-18 §4, App Explorations 165a; Nik, 17 Nov 2026: "the Overview
// should read like Sunny and Nicolay combined, no scores") ──
// Each book's build writes its own `side` (sideOf, in index.ts): its value by day, its parts (Your book's figures,
// leg by leg), its realized P&L and dividends by month, and what is coming up for it. Book S's build reads N's latest
// side and puts the two together here. Nothing is computed twice: Today is each book's Home today split by leg
// (the parts add up to it), Unrealized is each leg against what it cost or what it was sold for, realized is each
// book's own ledger since its start (S 31 Aug 2026, N 29 Oct 2026), dividends kept apart.
//
// Groups follow Nik's rule of 11 Nov 2026 (he kept it over the handoff on 18 Nov): What you sold = Calls sold, Puts
// sold; What you own = Shares, Hedges (every call bought, LEAPS too, and every put bought).
// No em dashes in any words here.

type Row = Record<string, any>;

/** One leg of one book (index.ts legParts): kind sc | sp | sh | hc | ip. */
export interface SideLeg { key: string; t: string; k: string; label: string; ex: string | null; n: number; today: number; all: number; value: number; base: number }
export interface SideEvent { d: string; kind: 'earnings' | 'exdiv' | 'expiry' | 'macro' | 'market'; t?: string; title?: string; time?: string | null;
  shares?: number; amount?: number | null; calls?: number; puts?: number }
export interface Side {
  id: string; name: string; start: string;
  /** IBKR's value at each day's close: [day, nav, deposits that day]. */
  nav: [string, number, number][];
  /** The value now (Home's account value) and today's change (Home's today). */
  live: { d: string; v: number; today: number } | null;
  legs: SideLeg[];
  /** Realized P&L and dividends by month since the book's start: [YYYY-MM, amount]. */
  realized: [string, number][];
  dividends: [string, number][];
  events: SideEvent[];
  /** The day the parts were built for (a side older than a day is still read; the app shows `built`). */
  built: string;
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd, wd: new Date(Date.UTC(y, m - 1, dd)).getUTCDay() }; };
const md = (d: string) => `${MON[ymd(d).m - 1]} ${ymd(d).d}`;
const addDays = (iso: string, n: number) => new Date(Date.parse(iso + 'T12:00:00Z') + n * 864e5).toISOString().slice(0, 10);
const r2 = (v: number) => Math.round(v * 100) / 100;

export function buildTogether(sides: Side[], today: string, company: (t: string) => string): Row {
  const ids = sides.map((s) => s.id);
  // ── 1 · The value line: both books' closes added day by day, then now. Deposits are kept so a range's change
  //    can leave them out (book N's $49K on 29 Oct is money in, not a gain). ──
  const days = [...new Set(sides.flatMap((s) => s.nav.map((x) => x[0])))].sort();
  const navOf = sides.map((s) => new Map(s.nav.map((x) => [x[0], x])));
  const line: Row[] = [];
  const last = sides.map(() => 0 as number | null);
  const seen = sides.map(() => false);
  for (const d of days) {
    const vals: (number | null)[] = [], deps: number[] = [];
    sides.forEach((s, i) => {
      const x = navOf[i].get(d);
      if (x) last[i] = x[1];
      const v = d < s.start ? null : (x ? x[1] : last[i]);
      vals.push(v);
      /* A book's first day in the line is money in: its whole value that day counts as a deposit (not that day's
         IBKR deposits, which are inside it), so the line drawn less deposits never jumps when a book starts. */
      if (v != null && !seen[i]) { seen[i] = true; deps.push(days[0] === d ? 0 : v); return; }
      deps.push(x ? x[2] : 0);
    });
    line.push({ d, v: vals.map((v) => (v == null ? null : r2(v))), dep: r2(deps.reduce((a, b) => a + b, 0)) });
  }
  const live = sides.every((s) => s.live) ? { d: today, v: sides.map((s) => r2(s.live!.v)), today: r2(sides.reduce((a, s) => a + s.live!.today, 0)),
    todays: sides.map((s) => r2(s.live!.today)) } : null;

  // ── 2 · Your positions: by what is held, both books added; a row opens its legs with each book's part ──
  const KINDS: { k: string; l: string; of: string[]; sold: boolean }[] = [
    { k: 'cs', l: 'Calls sold', of: ['sc'], sold: true }, { k: 'ps', l: 'Puts sold', of: ['sp'], sold: true },
    { k: 'sh', l: 'Shares', of: ['sh'], sold: false }, { k: 'hg', l: 'Hedges', of: ['hc', 'ip'], sold: false }];
  const rows = KINDS.map((K) => {
    const items = new Map<string, Row>();
    for (const [i, s] of sides.entries()) {
      for (const l of s.legs.filter((x) => K.of.includes(x.k))) {
        const it = items.get(l.key) ?? items.set(l.key, { key: l.key, t: l.t, name: company(l.t), label: l.label, ex: l.ex, k: l.k,
          n: 0, parts: sides.map(() => null) as (Row | null)[], today: 0, all: 0, value: 0, base: 0 }).get(l.key)!;
        it.n += l.n; it.today += l.today; it.all += l.all; it.value += l.value; it.base += l.base;
        it.parts[i] = { n: l.n, today: r2(l.today), all: r2(l.all) };
      }
    }
    const list: Row[] = [...items.values()].map((it: Row): Row => ({ ...it, today: r2(it.today), all: r2(it.all), value: r2(it.value), base: r2(it.base) }))
      .sort((a, b) => Math.abs(b.all) - Math.abs(a.all) || a.label.localeCompare(b.label));
    if (!list.length) return null;
    const sum = (f: 'today' | 'all' | 'value' | 'base' | 'n') => r2(list.reduce((a, x) => a + Number(x[f]), 0));
    const names = [...new Set(list.map((x) => x.t))];
    const calls = list.filter((x) => x.k === 'hc').reduce((a, x) => a + x.n, 0), puts = list.filter((x) => x.k === 'ip').reduce((a, x) => a + x.n, 0);
    return { k: K.k, l: K.l, sold: K.sold, today: sum('today'), all: sum('all'), value: sum('value'), base: sum('base'), n: sum('n'),
      names: names.length, only: names.length === 1 ? company(names[0]) : null, hedgeCalls: calls, hedgePuts: puts, items: list };
  }).filter(Boolean) as Row[];
  const positions = [
    { k: 'sold', l: 'What you sold', rows: rows.filter((r) => r.sold) },
    { k: 'own', l: 'What you own', rows: rows.filter((r) => !r.sold) },
  ].filter((g) => g.rows.length);

  // ── 3 · Coming up across both books: this week to Friday, then later (45 days) ──
  const wd = ymd(today).wd, friday = addDays(today, (5 - wd + 7) % 7 || (wd === 5 ? 0 : 7));
  const ev = new Map<string, Row>();
  for (const [i, s] of sides.entries()) {
    for (const e of s.events) {
      if (e.d < today || e.d > addDays(today, 45)) continue;
      const key = e.kind === 'earnings' || e.kind === 'exdiv' ? `${e.d}|${e.kind}|${e.t}` : e.kind === 'expiry' ? `${e.d}|expiry` : `${e.d}|${e.kind}|${e.title}`;
      const x = ev.get(key) ?? ev.set(key, { d: e.d, kind: e.kind, t: e.t ?? null, title: e.title ?? null, time: e.time ?? null,
        amount: e.amount ?? null, per: sides.map(() => null) as (Row | null)[] }).get(key)!;
      x.per[i] = { shares: e.shares ?? 0, calls: e.calls ?? 0, puts: e.puts ?? 0 };
    }
  }
  const n0 = (x: number) => Math.round(x).toLocaleString('en-US');
  const events = [...ev.values()].sort((a, b) => a.d.localeCompare(b.d) || a.kind.localeCompare(b.kind)).map((e) => {
    const who = (f: (p: Row) => string) => e.per.map((p: Row | null, i: number) => (p ? f(p) : '') ? `${sides[i].name} ${f(p!)}` : '').filter(Boolean).join(' · ');
    let title = '', sub = '';
    if (e.kind === 'earnings') { title = `${company(e.t)} earnings`; sub = who((p) => (p.shares ? `${n0(p.shares)} shares` : 'options')); }
    else if (e.kind === 'exdiv') {
      const sh = e.per.reduce((a: number, p: Row | null) => a + (p?.shares ?? 0), 0);
      title = `${company(e.t)} ex-dividend`;
      sub = e.amount ? `$${Number(e.amount).toFixed(2)} a share, $${n0(Number(e.amount) * sh)} to ${sides.length > 1 && e.per.filter(Boolean).length > 1 ? 'both' : 'you'}` : who((p) => `${n0(p.shares)} shares`);
    } else if (e.kind === 'expiry') {
      title = e.d === today ? 'Options expire today' : e.d === friday ? 'This week’s options expire' : `Options expire ${DOW[ymd(e.d).wd]}`;
      sub = who((p) => [p.calls ? `${n0(p.calls)} calls` : '', p.puts ? `${n0(p.puts)} puts` : ''].filter(Boolean).join(' and '));
    } else if (e.kind === 'macro') { title = String(e.title); sub = `${e.time ? clock(String(e.time)) + ' · ' : ''}moves every name`; }
    else { title = String(e.title); sub = 'Markets closed'; }
    return { d: e.d, wd: DOW[ymd(e.d).wd], md: md(e.d), week: e.d <= friday, kind: e.kind, t: e.t, title, sub };
  });

  // ── 4 · Realized P&L: this month, the year, and by month since the first book started, with a straight-line trend ──
  const ym = today.slice(0, 7), yr = today.slice(0, 4);
  const months = [...new Set(sides.flatMap((s) => s.realized.map((x) => x[0])))].filter((m) => m <= ym).sort();
  const mOf = (s: Side, m: string) => s.realized.find((x) => x[0] === m)?.[1] ?? 0;
  const byMonth = months.map((m) => {
    const [y, mm] = m.split('-').map(Number);
    const per = sides.map((s) => (`${m}-31` < s.start ? null : r2(mOf(s, m))));
    return { m, l: MONTH[mm - 1], s: MON[mm - 1], y, per, total: r2(per.reduce((a: number, v) => a + (v ?? 0), 0)), part: m === ym };
  });
  const tot = byMonth.map((x) => x.total), nM = tot.length;
  let trend: Row | null = null;
  if (nM >= 2) {
    const xb = (nM - 1) / 2, yb = tot.reduce((a, b) => a + b, 0) / nM;
    const den = tot.reduce((a, _y, i) => a + (i - xb) * (i - xb), 0);
    const slope = den ? tot.reduce((a, y, i) => a + (i - xb) * (y - yb), 0) / den : 0;
    trend = { slope: r2(slope), fit: tot.map((_y, i) => r2(yb + slope * (i - xb))), since: byMonth[0].l };
  }
  const sumWhere = (s: Side, f: (m: string) => boolean) => r2(s.realized.filter((x) => f(x[0])).reduce((a, x) => a + x[1], 0));
  const realized = {
    month: { per: sides.map((s) => sumWhere(s, (m) => m === ym)) },
    year: { per: sides.map((s) => sumWhere(s, (m) => m.startsWith(yr))) },
    byMonth, trend,
    starts: sides.map((s) => ({ name: s.name, start: s.start, md: md(s.start) })),
    dividends: { year: sides.map((s) => r2(s.dividends.filter((x) => x[0].startsWith(yr)).reduce((a, x) => a + x[1], 0))) },
  };
  return { v: 1, ids, names: sides.map((s) => s.name), today, built: sides.map((s) => s.built), line, live, positions, events, realized };
}

/** "14:00:00" → "2:00 PM". */
function clock(t: string): string {
  const [h, m] = t.split(':').map(Number);
  if (!Number.isFinite(h)) return t;
  return `${((h + 11) % 12) + 1}:${String(m ?? 0).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}
