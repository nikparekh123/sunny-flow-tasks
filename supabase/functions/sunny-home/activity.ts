// ── Activity (handoff 2026-11-18, round 161a + 161c; Nik, 16 Nov 2026): what happened, when, in order. Home keeps where
// things stand. IBKR first (did it pick up my trades?), then levels and moves on the names held.
// This works out the events as of now from what sunny-home already reads; index.ts upserts them into
// public.activity_events (one row per key, updated in place when the same thing changes the same day) and sends the
// last eight days in the payload with the sync state and the Levels card's figures.
//   IBKR: each sync that inserted trades ("3 trades picked up", every trade inside, Added: no To do to match since
//     11 Nov, and no LEAPS-or-hedge question since Nik's rule of 11 Nov: every call bought is a hedge call); the day's
//     expirations after the close; dividends paid on shares held.
//   Levels (held names, during the session): over or under the 20, 50 and 200-day against yesterday's close side, one
//     line per name and average a day that updates if it crosses back; this week's walls (the soonest expiry's call wall
//     is the ceiling, its put wall the floor): near (within 1%), through, back.
//   Moves: past the day's priced move (the name's IV × √(1/252)), and always at 5%.
// No em dashes in any words here.

type Row = Record<string, any>;

export interface ActName {
  t: string; name: string; px: number; prev: number | null; iv: number | null; shares: number;
  sma: { 20: number | null; 50: number | null; 200: number | null };
  ceiling: number | null; floor: number | null;
  /** Contracts sold at each strike this week (calls, puts), for "Your 26 calls sit on it". */
  callsAt: Record<string, number>; putsAt: Record<string, number>;
}
export interface ActIn {
  today: string; mins: number; trading: boolean; closeMins: number; nowISO: string;
  names: ActName[];
  runs: { id: string; started: string; finished: string; inserted: number }[];
  trades: Row[];
  /** Sold contracts that ended by expiry or assignment, by the day IBKR booked it. */
  expired: { d: string; n: number; asg: number }[];
  divsPaid: { t: string; amount: number; shares: number }[];
  /** Today's level lines already written (key -> title): a line that crossed and came back says so ("back under"). */
  seen?: Record<string, string>;
}
export interface ActEvent { key: string; day: string; at: string; kind: 'ibkr' | 'lvl' | 'move'; t: string | null; title: string; body: string; opens: string; data?: Row }

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const money = (v: number) => { const a = Math.abs(v); return a >= 999.5 ? `$${(a / 1000).toFixed(1).replace(/\.0$/, '')}K` : `$${Math.round(a)}`; };
const px2 = (v: number) => `$${v.toFixed(2)}`;
const fk = (k: number) => (k % 1 ? (Math.round(k * 100) % 10 ? k.toFixed(2) : k.toFixed(1)) : String(k));
const n0 = (v: number) => Math.round(v).toLocaleString('en-US');
const nyClock = (iso: string) => {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: '2-digit', hour12: true })
    .formatToParts(new Date(iso)).map((x) => [x.type, x.value]));
  return `${p.hour}:${p.minute} ${String(p.dayPeriod).toUpperCase()}`;
};
const exLabel = (ex: string) => { const [, m, d] = ex.split('-').map(Number); return `${MON[m - 1]} ${d}`; };

export function activityEvents(x: ActIn): ActEvent[] {
  const out: ActEvent[] = [], now = x.nowISO, today = x.today;
  // ── IBKR: each sync that picked up trades ──
  for (const r of x.runs.filter((r) => r.inserted > 0)) {
    const a = Date.parse(r.started) - 2000, b = Date.parse(r.finished) + 2000;
    const tr = x.trades.filter((t) => { const c = Date.parse(String(t.created_at)); return c >= a && c <= b; })
      .sort((a, b) => String(a.executed_at ?? '').localeCompare(String(b.executed_at ?? '')));
    if (!tr.length) continue;
    const trades = tr.map((t) => {
      const sold = (t.direction === 'short') === (t.action === 'open');
      const what = `${sold ? 'Sold' : 'Bought'} ${n0(Number(t.contracts))} ${String(t.ticker).toUpperCase()} ${exLabel(String(t.expiry))} ${fk(Number(t.strike))} ${t.option_type === 'call' ? 'calls' : 'puts'}`;
      return { t: String(t.ticker).toUpperCase(), what, at: `${px2(Number(t.premium))}${t.executed_at ? ' · filled ' + nyClock(String(t.executed_at)) : ''}`, st: 'added' };
    });
    out.push({ key: `pickup|${r.id}`, day: nyDay(r.finished), at: r.finished, kind: 'ibkr', t: null,
      title: `${trades.length} ${trades.length === 1 ? 'trade' : 'trades'} picked up`, body: '', opens: 'Positions', data: { trades } });
  }
  // ── IBKR: what sold ended at an expiry (IBKR's lifecycle rows), on the day it was booked ──
  for (const e of x.expired) {
    if (!(e.n > 0)) continue;
    out.push({ key: `exp|${e.d}`, day: e.d, at: new Date(`${e.d}T21:30:00Z`).toISOString(), kind: 'ibkr', t: null,
      title: `${n0(e.n)} ${e.n === 1 ? 'sale' : 'sales'} ${e.asg ? 'ended' : 'expired'}`,
      body: e.asg ? `${n0(e.asg)} assigned; the rest expired out of the money.` : 'All out of the money. They left your book at the close.', opens: 'Positions' });
  }
  // ── IBKR: dividends paid today ──
  for (const d of x.divsPaid) {
    const nm = x.names.find((n) => n.t === d.t)?.name ?? d.t;
    out.push({ key: `div|${d.t}|${today}`, day: today, at: now, kind: 'ibkr', t: d.t, title: `${nm} paid ${money(d.amount * d.shares)}`,
      body: `Dividends on ${n0(d.shares)} shares, kept apart from your results.`, opens: 'Home · Results' });
  }
  // ── Levels and moves: held names, once the session has opened ──
  if (!x.trading || x.mins < 9 * 60 + 30) return out;
  for (const n of x.names) {
    if (!(n.px > 0) || !(n.prev && n.prev > 0)) continue;
    const opens = `Positions · ${n.name}, Price`;
    for (const L of [20, 50, 200] as const) {
      const v = n.sma[L];
      if (!(v && v > 0)) continue;
      const was = n.prev >= v, is = n.px >= v, key = `lvl|${n.t}|sma${L}|${today}`;
      // Same side as yesterday's close: nothing, unless it crossed earlier today (then the line says it came back).
      const back = was === is && !!x.seen?.[key];
      if (was === is && !back) continue;
      const others = ([20, 50, 200] as const).filter((k) => k !== L && n.sma[k]).map((k) => `The ${k}-day is ${px2(n.sma[k]!)}.`)[0] ?? '';
      out.push({ key, day: today, at: now, kind: 'lvl', t: n.t,
        title: `${n.name} ${back ? 'back ' : ''}${is ? 'over' : 'under'} its ${L}-day`, body: `${px2(n.px)} now, the line is ${px2(v)}. ${others}`.trim(), opens });
    }
    for (const [side, K] of [['c', n.ceiling], ['f', n.floor]] as const) {
      if (!(K && K > 0)) continue;
      const word = side === 'c' ? 'ceiling' : 'floor', gap = (n.px / K - 1) * 100;
      const through = side === 'c' ? n.px > K : n.px < K, near = !through && Math.abs(gap) <= 1;
      const wkey = `wall|${n.t}|${side}|${fk(K)}|${today}`, wasThrough = / through /.test(x.seen?.[wkey] ?? '');
      // Through earlier today and back inside the walls: the line says so; near and drifted away: it stays as it was.
      if (!through && !near) {
        if (wasThrough) out.push({ key: wkey, day: today, at: now, kind: 'lvl', t: n.t,
          title: `${n.name} back ${side === 'c' ? 'under' : 'over'} the ${fk(K)} ${word}`,
          body: `${px2(n.px)}, ${Math.abs(gap).toFixed(1)}% ${gap >= 0 ? 'over' : 'under'} this week’s ${side === 'c' ? 'call' : 'put'} wall.`, opens });
        continue;
      }
      const mine = side === 'c' ? n.callsAt[fk(K)] : n.putsAt[fk(K)];
      const sits = mine ? ` Your ${n0(mine)} ${side === 'c' ? 'calls' : 'puts'} sit on it.` : '';
      out.push({ key: wkey, day: today, at: now, kind: 'lvl', t: n.t,
        title: `${n.name} ${through ? 'through' : wasThrough ? 'back near' : 'near'} the ${fk(K)} ${word}`,
        body: `${px2(n.px)}, ${Math.abs(gap).toFixed(1)}% ${gap >= 0 ? 'over' : 'under'} this week’s ${side === 'c' ? 'call' : 'put'} wall.${sits}`, opens });
    }
    const mv = (n.px / n.prev - 1) * 100, priced = n.iv && n.iv > 0 ? n.iv * Math.sqrt(1 / 252) * 100 : null;
    if (Math.abs(mv) >= 5 || (priced != null && Math.abs(mv) > priced)) {
      const dv = n.shares * (n.px - n.prev);
      out.push({ key: `move|${n.t}|${today}`, day: today, at: now, kind: 'move', t: n.t, title: `${n.name} ${mv >= 0 ? 'up' : 'down'} ${Math.abs(mv).toFixed(1)}%`,
        body: (priced != null ? `Past the ${priced.toFixed(1)}% priced for today.` : 'A 5% day.') + (n.shares > 0 ? ` Your ${n0(n.shares)} shares are ${dv >= 0 ? 'up' : 'down'} ${money(dv)}.` : ''), opens });
    }
  }
  return out;
}

/** An instant's New York day. */
function nyDay(iso: string): string { return new Date(iso).toLocaleDateString('en-CA', { timeZone: 'America/New_York' }); }

/** The Levels card (161c): each held name against its averages (over the 20, 50 and 200-day: '1' or '0' each) and this
    week's walls (near a ceiling, near a floor, between). */
export function levelsOf(names: ActName[]): Row[] {
  return names.filter((n) => n.px > 0).map((n) => {
    const ma = ([20, 50, 200] as const).map((k) => (n.sma[k] && n.sma[k]! > 0 ? (n.px >= n.sma[k]! ? '1' : '0') : '-')).join('');
    const nc = n.ceiling && Math.abs(n.px / n.ceiling - 1) <= 0.01, nf = n.floor && Math.abs(n.px / n.floor - 1) <= 0.01;
    return { t: n.t, name: n.name, px: Math.round(n.px * 100) / 100, mv: n.prev ? Math.round((n.px / n.prev - 1) * 1000) / 10 : null, ma,
      wall: nc ? 'c' : nf ? 'f' : 'b', wallK: nc ? n.ceiling : nf ? n.floor : null };
  });
}
