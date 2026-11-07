// ── Overview (block 32, handoff 6 Nov 2026, Pass 2): the coach's report on both books ──
// Rates, not dollars, so a book a third the size compares fairly. Built in book S's build from S's fresh brief
// and N's latest one (both from the one engine), written to the owners' part only (it counts the trades to
// place). Shape = the design's sample (Brief/Sample/brief-overview.json): header, sentence, tally, six checks,
// Coming in. The rules are README 8; the Watch lines are the defaults Nik accepted on 6 Nov:
//   Downside over 5% of what both hold · Concentration one name over 35% or the top three over 70% ·
//   Pace under the 4-week average · Calls at work under 90% · Delta any name past its best · To do any late.
//
// Words (Nik, 7 Nov): never "turns short"; a name past its best at its priced move.
// No em dashes; money lost is red with no minus sign.

import { type Leg, NameBook } from '../_shared/book-engine.ts';

type Row = Record<string, any>;
type Span = { t: string; b?: boolean; c?: string };

export interface BookSide {
  id: string;            // "S", "N"
  name: string;          // "Sunny", "Nicolay"
  brief: Row | null;     // payload.brief (names, position, friday, th, base, pace)
  inputs: Row | null;    // payload.brief_inputs (each name's legs)
  orders: Row[];         // the To do rows (this_week)
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd, wd: new Date(Date.UTC(y, m - 1, dd)).getUTCDay() }; };
const md = (d: string) => `${MON[ymd(d).m - 1]} ${ymd(d).d}`;
const dmd = (d: string) => `${DOW[ymd(d).wd]} ${md(d)}`;
const $0 = (x: number) => `$${Math.round(Math.abs(x)).toLocaleString('en-US')}`;
const n0 = (x: number) => Math.round(x).toLocaleString('en-US');
const pc = (x: number) => `${Math.round(Math.abs(x))}%`;
const p2 = (x: number) => `${Math.abs(x).toFixed(2)}%`;
const sp = (t: string, ink = false): Span => ({ t, b: true, c: ink ? 'ink' : 'secondary' });
const list = (xs: string[]) => (xs.length <= 1 ? xs.join('') : `${xs.slice(0, -1).join(', ')} and ${xs.at(-1)}`);
const check = (name: string, watch: boolean, big: string, sentence: string, chips: string[], bigColor = 'ink') =>
  ({ name, status: watch ? 'Watch' : 'On track', statusColor: watch ? 'orange' : 'green', big, bigColor, sentence, chips, aria: `${name}, ${watch ? 'Watch' : 'On track'}` });
/** Put cover in words: a quarter, a third, half... (the design's "only a quarter"). */
const coverWords = (p: number) => {
  const named: [number, string][] = [[25, 'a quarter'], [33, 'a third'], [50, 'half'], [67, 'two thirds'], [75, 'three quarters'], [100, 'all']];
  const hit = named.find(([v]) => Math.abs(v - p) <= 3);
  return `${p < 50 ? 'only ' : ''}${hit ? hit[1] : `${Math.round(p)}%`}`;
};

export function buildOverview(books: BookSide[], today: string, mins: number, company: (t: string) => string): Row {
  const held = books.filter((b) => (b.brief?.names ?? []).length > 0);
  type Per = { b: BookSide; downside: number; hold: number; shares: number; covered: number; callsSh: number; gaps: string[];
    short: string[]; thin: string[]; longNow: number; names: number; pace: number | null; avg4: number | null; late: number; values: Map<string, number> };
  const per: Per[] = books.map((b) => {
    const B = b.brief ?? {}, I = b.inputs ?? {}, th = Number(B.th ?? 0), F = String(B.friday ?? today);
    const rows: Row[] = B.position?.rows ?? [];
    let downside = 0, hold = 0, shares = 0, covered = 0, callsSh = 0, longNow = 0;
    const gaps: { t: string; f: number }[] = [], values = new Map<string, number>();
    for (const n of (I.names ?? []) as Row[]) {
      const legs = n.legs as Leg[];
      const nb = new NameBook({ t: n.t, S0: n.S0, P0: n.P0, iv: n.iv, legs, divs: n.divs, r: I.r });
      downside += nb.at(-nb.sd, th).p;
      if (nb.delta(nb.S0, 0) > 0) longNow++;
      const sh = legs.filter((l) => l.kind === 'shares').reduce((a, l) => a + l.q, 0);
      const ins = legs.filter((l) => l.kind === 'ins').reduce((a, l) => a + l.q * 100, 0);
      const sold = legs.filter((l) => l.kind === 'sc' && l.ex <= F).reduce((a, l) => a + -l.q * 100, 0);
      shares += sh; covered += Math.min(sh, ins);
      if (sh > 0) { const c = Math.min(sh, sold); callsSh += c; gaps.push({ t: n.t, f: c / sh }); }
    }
    for (const n of (B.names ?? []) as Row[]) {
      const h = n.h ?? {}, v = Number(h.sh?.[0] ?? 0) + Number(h.lp?.[0] ?? 0) + Number(h.oc?.[0] ?? 0);
      hold += v + Number(h.ip?.[0] ?? 0);
      values.set(String(n.t), v);
    }
    /* An order is late when it is a sale for this week's Friday still to place after that week's Monday. */
    const mon = (() => { const x = new Date(F + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() - ((ymd(F).wd + 6) % 7)); return x.toISOString().slice(0, 10); })();
    const late = b.orders.filter((o) => (o.kind === 'sell' || o.kind === 'put') && String(o.id ?? '').split('|')[2] <= F
      && (today > mon || (today === mon && mins >= 16 * 60))).length;
    return { b, downside, hold, shares, covered, callsSh, gaps: gaps.filter((g) => g.f < 0.9).sort((p, q) => p.f - q.f).map((g) => g.t),
      short: rows.filter((r) => r.st === 2).map((r) => String(r.id)), thin: rows.filter((r) => r.st === 1).map((r) => String(r.id)),
      longNow, names: (I.names ?? []).length, pace: B.pace?.week ?? null, avg4: B.pace?.avg4 ?? null, late, values };
  });

  const nm = (b: BookSide) => b.name, poss = (b: BookSide) => `${b.name}’s`;
  const sum = (f: (p: Per) => number) => per.reduce((a, p) => a + f(p), 0);

  // Downside
  const down = sum((p) => p.downside), hold = sum((p) => p.hold), downPct = hold > 0 ? (-down / hold) * 100 : 0;
  const coverAll = sum((p) => p.shares) > 0 ? (sum((p) => p.covered) / sum((p) => p.shares)) * 100 : 0;
  const downside = check('Downside', downPct > 5, down < 0 ? $0(down) : '$0',
    down < 0 ? `Lost by Friday if every name falls its priced move, ${downPct.toFixed(1)}% of what ${held.length > 1 ? 'both books hold' : 'the book holds'}.`
      : 'Nothing lost by Friday if every name falls its priced move.',
    [`Puts cover ${pc(coverAll)} of the shares`, ...per.filter((p) => p.shares > 0).map((p) => `${nm(p.b)} ${pc(p.covered / p.shares * 100)}`)], down < 0 ? 'red' : 'ink');

  // Concentration
  const byT = new Map<string, number>();
  for (const p of per) for (const [t, v] of p.values) byT.set(t, (byT.get(t) ?? 0) + v);
  const total = [...byT.values()].reduce((a, v) => a + v, 0);
  const ranked = [...byT].filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]).map(([t, v]) => ({ t, s: total > 0 ? (v / total) * 100 : 0 }));
  const top2 = ranked.slice(0, 2), top3 = ranked.slice(0, 3).reduce((a, r) => a + r.s, 0);
  const sets = per.filter((p) => p.names > 0).map((p) => [...p.values.keys()].sort().join(','));
  const same = sets.length > 1 && sets.every((s) => s === sets[0]);
  const shared = held.length > 1 ? [...per[0].values.keys()].filter((t) => per.slice(1).every((p) => p.values.has(t))).length : 0;
  const conc = check('Concentration', (ranked[0]?.s ?? 0) > 35 || top3 > 70, pc(top2.reduce((a, r) => a + r.s, 0)),
    ranked.length ? `Of ${held.length > 1 ? 'both books' : 'the book'} sits in ${list(top2.map((r) => company(r.t)))}.${same ? ` Both hold the same ${ranked.length} names, so they rise and fall together.` : shared ? ` ${shared} ${shared === 1 ? 'name is' : 'names are'} in both books.` : ''}` : 'Nothing held yet.',
    ranked.slice(0, 3).map((r) => `${company(r.t)} ${pc(r.s)}`));

  // Pace
  const basePace = per.filter((p) => p.pace != null && (p.b.brief?.base ?? 0) > 0);
  const wBase = basePace.reduce((a, p) => a + Number(p.b.brief!.base), 0);
  const pace = wBase > 0 ? basePace.reduce((a, p) => a + p.pace! * Number(p.b.brief!.base), 0) / wBase : null;
  const avg = wBase > 0 ? basePace.filter((p) => p.avg4 != null).reduce((a, p) => a + p.avg4! * Number(p.b.brief!.base), 0) / wBase : null;
  const behind = pace != null && avg != null && pace < avg;
  const paceC = check('Pace', behind, pace == null ? 'None' : p2(pace),
    pace == null ? 'Nothing sold this week yet.' : `${pace < 0 ? 'Given back' : 'Kept'} this week on what ${held.length > 1 ? 'both' : 'you'} bought, if Friday goes to plan.${avg != null ? ` A usual week is ${avg < 0 ? 'a loss of ' : ''}${p2(avg)}.` : ''}`,
    basePace.map((p) => `${nm(p.b)} ${p2(p.pace!)}`), pace != null && pace < 0 ? 'red' : 'ink');

  // Calls at work
  const shAll = sum((p) => p.shares), cw = shAll > 0 ? (sum((p) => p.callsSh) / shAll) * 100 : 0;
  const gapNames = [...new Set(per.flatMap((p) => p.gaps))];
  const gapIn = (t: string) => per.filter((p) => p.gaps.includes(t)).map((p) => p.b);
  const gapLine = gapNames.length ? ` ${list(gapNames.slice(0, 2).map((t) => company(t)))} ${gapNames.length === 1 ? 'is' : 'are'} the gap${held.length > 1 && gapIn(gapNames[0]).length === held.length ? ' in both' : ''}.` : '';
  const calls = check('Calls at work', shAll > 0 && cw < 90, shAll > 0 ? pc(cw) : 'None',
    shAll > 0 ? `Of the ${n0(shAll)} shares have a call sold this week, one per 100.${gapLine}` : 'No shares held, so no calls to sell on them.',
    per.filter((p) => p.shares > 0).map((p) => `${nm(p.b)} ${pc(p.callsSh / p.shares * 100)}`));

  // Delta (past their best at their priced move by Friday)
  const nNames = sum((p) => p.names), nShort = sum((p) => p.short.length), longNow = sum((p) => p.longNow);
  const shortTs = [...new Set(per.flatMap((p) => p.short))];
  /* Grouped by where they sit: "Nike in both books, Alibaba and Uber in Nicolay’s". */
  const groups = new Map<string, string[]>();
  for (const t of shortTs) {
    const in_ = per.filter((p) => p.short.includes(t)).map((p) => p.b);
    const k = in_.length === held.length && held.length > 1 ? 'both books' : poss(in_[0]);
    groups.set(k, [...(groups.get(k) ?? []), company(t)]);
  }
  const where = [...groups].map(([k, ts]) => `${list(ts)} in ${k}`);
  const delta = check('Delta', nShort > 0, `${nShort} of ${nNames}`,
    nNames === 0 ? 'Nothing held yet.'
      : `${nShort ? `Past their best if they rise their priced move by Friday: ${list(where)}.` : 'Every name keeps making more if it rises its priced move by Friday.'} ${longNow === nNames ? `All ${nNames} are long today.` : `${longNow} of ${nNames} are long today.`}`,
    per.filter((p) => p.names > 0).map((p) => `${nm(p.b)} ${[p.short.length ? `${p.short.length} past ${p.short.length === 1 ? 'its' : 'their'} best` : '', p.thin.length ? `${p.thin.length} thin` : ''].filter(Boolean).join(' · ') || 'all long'}`));

  // To do
  const nOrders = books.reduce((a, b) => a + b.orders.length, 0), nLate = sum((p) => p.late);
  const whose = books.filter((b) => b.orders.length).map((b) => `${list([...new Set(b.orders.map((o) => company(String(o.t))))])} in ${poss(b)}`);
  const empty = books.filter((b) => !(b.brief?.names ?? []).length);
  const todo = check('To do', nLate > 0, String(nOrders),
    nOrders ? `Trades to place, ${nLate ? `${nLate} late` : 'none late'}. ${list(whose)}.` : 'Nothing to place.',
    books.filter((b) => (b.brief?.names ?? []).length > 0).map((b) => `${nm(b)} ${b.orders.length}`));

  // Coming in: dividends declared in the next 45 days on the shares each book holds (kept apart from pace)
  const checks = [downside, conc, paceC, calls, delta, todo];
  const watch = checks.filter((c) => c.status === 'Watch').length;

  // The sentence: pace, a bad week, the put cover
  const onPace = basePace.filter((p) => !(p.avg4 != null && p.pace! < p.avg4));
  const paceWords: Span[] = basePace.length === 0 ? [sp('Nothing sold this week yet')]
    : basePace.length > 1 && onPace.length === basePace.length ? [sp('Both books are '), sp('on pace', true), sp(' this week')]
    : basePace.length > 1 && onPace.length === 0 ? [sp('Both books are '), sp('behind pace', true), sp(' this week')]
    : basePace.length > 1 ? [sp(`${nm(onPace[0].b)} is `), sp('on pace', true), sp(`, ${nm(basePace.find((p) => !onPace.includes(p))!.b)} is behind`)]
    : [sp(`${nm(basePace[0].b)} is `), sp(onPace.length ? 'on pace' : 'behind pace', true), sp(' this week')];
  const sentence: Span[] = held.length === 0 ? [sp('Nothing held yet in either book.')]
    : [...paceWords, sp('. A bad week would cost '), sp(downPct.toFixed(1).replace(/\.0$/, '') + '%', true),
      ...(shAll > 0 ? [sp(`, and the puts cover `), sp(coverWords(coverAll), true), sp(' of the shares.')] : [sp('.')]),
      ...(books.length > 1 && empty.length ? [sp(` ${list(empty.map(nm))} ${empty.length === 1 ? 'holds' : 'hold'} nothing yet.`)] : [])];

  return {
    v: 1, built_for: today, header: `${books.length > 1 ? 'Both accounts' : 'Your account'} · ${dmd(today)}`,
    sentence,
    tally: [{ t: `${checks.length - watch} on track`, dot: 'green' }, { t: `${watch} to watch`, dot: 'orange' },
      { t: `${nOrders} ${nOrders === 1 ? 'trade' : 'trades'} to place`, dot: null }],
    checks,
    comingIn: null as Row | null,
    // raw numbers for the invariants (README 12: 2, 3, 4, 5, 9)
    raw: { downside: Math.round(down), hold: Math.round(hold), cover: per.map((p) => ({ id: p.b.id, shares: p.shares, covered: p.covered })),
      calls: per.map((p) => ({ id: p.b.id, shares: p.shares, covered: p.callsSh })), short: per.map((p) => ({ id: p.b.id, names: p.short })),
      orders: books.map((b) => ({ id: b.id, n: b.orders.length })) },
  };
}

/** Coming in: dividends declared ahead (ex-date in the window) on the shares each book holds, by book. */
export function comingIn(books: BookSide[], divs: Row[], company: (t: string) => string): Row | null {
  const amt = new Map<string, number>(), names = new Set<string>();
  let last = '';
  for (const b of books) {
    let a = 0;
    for (const n of (b.inputs?.names ?? []) as Row[]) {
      const sh = (n.legs as Leg[]).filter((l) => l.kind === 'shares').reduce((s, l) => s + l.q, 0);
      if (!(sh > 0)) continue;
      for (const d of divs.filter((x) => String(x.ticker).toUpperCase() === n.t)) {
        a += sh * Number(d.cash_amount); names.add(n.t);
        if (String(d.ex_date) > last) last = String(d.ex_date);
      }
    }
    amt.set(b.id, a);
  }
  const all = [...amt.values()].reduce((s, v) => s + v, 0);
  if (!(all > 0)) return null;
  return { title: 'Coming in', amount: $0(all), amountColor: 'green',
    line: `Dividends by ${md(last)} from ${list([...names].map(company))}${books.filter((b) => (amt.get(b.id) ?? 0) > 0).length > 1 ? books.filter((b) => (amt.get(b.id) ?? 0) > 0).map((b) => ` · ${b.name} ${$0(amt.get(b.id)!)}`).join('') : ''} · kept apart from pace`,
    raw: books.map((b) => ({ id: b.id, amount: Math.round(amt.get(b.id) ?? 0) })) };
}
