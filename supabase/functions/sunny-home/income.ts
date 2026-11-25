// ── INCOME (handoff 2026-11-24 §1 and handoff-2026-11-24-income, SunnyIncome.dc.html) ──
// The daily income cadence in one place: every call and put sold and still open (a rung), what each has kept, where
// the ready ones roll to, the multi-expiry names' delta line, a small calendar a name, the totals, and the banner of
// realized income by week and month. One object, `payload.income`, that the phone and the web both draw (Income today
// on Home, the Income tab).
//
// Nik's rules (24 Nov 2026):
//   · A rung is every expiry actually sold, any weekday (D3). A name with sold legs on three or more expiries is a
//     ladder (Nicolay's Nvidia and SpaceX): its calendar shows four weeks and a rung rolls to the next listed expiry
//     after the last one open on that side. Otherwise weekly: two weeks, a rung rolls to the next week's expiry.
//     Daily (IWM) only once a daily name is sold (D4).
//   · Ready to roll at 90% kept (1 - mark ÷ sold at); 95% is shown too. In the money is flagged only, never advice.
//   · The next rung: calls at the SD they were sold at (option_fill_context z0, at least 0.25; 0.5 when unknown), puts
//     at 1 SD from today, both on a strike the chain lists for that expiry, priced at its mid. No chain, no strike.
//   · The delta line (ladders): how far the stock can rise before the name's book turns short (book-engine
//     turnsShort, today), red within 3%.
//   · The banner: realized income = what was kept on calls and puts sold (premium less any buyback), booked the day each
//     expired or was bought back (Nik, 24 Nov 2026); nothing from shares, LEAPS or hedges. By week (Mon to Fri) and by
//     month, by ticker and by account. Yield = income ÷ what the shares cost (IBKR's cost basis of shares held). Share
//     average = (what the shares cost - every premium kept on the name since the start) ÷ shares.
// No em dashes in any words here.

type Row = Record<string, any>;

export interface IncLeg {
  t: string; ty: 'call' | 'put'; K: number; ex: string; n: number; at: number; mk: number | null; iv: number | null;
  books: string[]; lots: { id: string; n: number }[];
}
export interface IncReal { d: string; t: string; kind: 'calls sold' | 'puts sold'; amt: number; book: string }
export interface Chain { strikes: { c: number[]; p: number[] }; mid: Map<string, number> }
export interface IncIn {
  today: string; start: string;
  isTrading: (d: string) => boolean; addDays: (d: string, n: number) => string;
  legs: IncLeg[];                                  // sold, open
  spot: Map<string, number>; prev: Map<string, number>;
  company: (t: string) => string;
  bookName: Record<string, string>;
  z0: Map<string, number>;                         // option_trade_id → SD when sold
  expiries: Map<string, string[]>;                 // ticker → listed expiries
  chains: Map<string, Chain>;                      // `${t}|${ex}` → chain
  flips: Map<string, { price: number; now: boolean } | null>;
  realized: IncReal[];
  shares: Map<string, { sh: number; cost: number }>;
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd, wd: new Date(Date.UTC(y, m - 1, dd)).getUTCDay() }; };
const md = (d: string) => `${MON[ymd(d).m - 1]} ${ymd(d).d}`;
const r2 = (v: number) => Math.round(v * 100) / 100;
const r4 = (v: number) => Math.round(v * 10000) / 10000;
const calDays = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);

export function chainKey(t: string, ex: string) { return `${t}|${ex}`; }

/** The rungs that are ready to roll and where each would go: the caller fetches those chains, then builds. */
export function rollTargets(x: Pick<IncIn, 'today' | 'legs' | 'expiries' | 'addDays'> & { kp: (l: IncLeg) => number | null; itm: (l: IncLeg) => boolean }):
  { t: string; ex: string }[] {
  const out = new Map<string, { t: string; ex: string }>();
  for (const l of x.legs) {
    const k = x.kp(l);
    if (k == null || k < 90 || x.itm(l)) continue;
    const ex = targetOf(l, x.legs, x.expiries.get(l.t) ?? [], x.addDays);
    if (ex) out.set(chainKey(l.t, ex), { t: l.t, ex });
  }
  return [...out.values()];
}

/** Ladder: three or more distinct sold expiries on the name. */
const isLadder = (t: string, legs: IncLeg[]) => new Set(legs.filter((l) => l.t === t).map((l) => l.ex)).size >= 3;

/** Where a rung rolls to: a ladder's next listed expiry after the last one open on that side; a weekly name's next
    week's expiry (the first listed at least five days after this one). */
function targetOf(l: IncLeg, legs: IncLeg[], exps: string[], addDays: (d: string, n: number) => string): string | null {
  if (!exps.length) return null;
  if (isLadder(l.t, legs)) {
    const last = legs.filter((x) => x.t === l.t && x.ty === l.ty).map((x) => x.ex).sort().at(-1) ?? l.ex;
    return exps.find((e) => e > last) ?? null;
  }
  const from = addDays(l.ex, 5);
  return exps.find((e) => e >= from) ?? null;
}

export function buildIncome(x: IncIn): Row {
  const { today, isTrading, addDays } = x;
  const tradingDays = (ex: string) => { let n = 0; for (let d = addDays(today, 1); d <= ex; d = addDays(d, 1)) if (isTrading(d)) n++; return n; };
  const ivOf = (l: IncLeg) => (l.iv != null && l.iv > 0.02 ? l.iv : 0.4);
  const kpOf = (l: IncLeg) => (l.at > 0 && l.mk != null ? Math.round((1 - l.mk / l.at) * 100) : null);

  // ── Rungs ──
  const rungs = x.legs.map((l) => {
    const S = x.spot.get(l.t) ?? 0, c = l.ty === 'call', td = tradingDays(l.ex), cd = calDays(today, l.ex);
    const m = ivOf(l) * Math.sqrt(Math.max(0.5, td) / 252);
    const sN = S > 0 && l.K > 0 ? (c ? Math.log(l.K / S) : Math.log(S / l.K)) / m : null;
    const w = l.lots.reduce((a, o) => a + (x.z0.has(o.id) ? o.n : 0), 0);
    /* option_fill_context's z0 is ln(K/S)/m, so a put sold below the price reads negative; s0 here is "SD from the
       strike" like sN (positive = out of the money), so a put's flips. */
    const z = w ? l.lots.reduce((a, o) => a + (x.z0.has(o.id) ? o.n * x.z0.get(o.id)! : 0), 0) / w : null;
    const s0 = z == null ? null : c ? z : -z;
    const kp = kpOf(l), itm = sN != null && sN < 0;
    const st: 'itm' | 'roll' | 'hold' = itm ? 'itm' : kp != null && kp >= 90 ? 'roll' : 'hold';
    let next: Row | null = null;
    if (st === 'roll') {
      const ex = targetOf(l, x.legs, x.expiries.get(l.t) ?? [], addDays);
      if (ex) {
        const ch = x.chains.get(chainKey(l.t, ex)), tdN = tradingDays(ex);
        const z = c ? (s0 != null ? Math.max(0.25, r2(s0)) : 0.5) : 1, mN = ivOf(l) * Math.sqrt(Math.max(0.5, tdN) / 252);
        const want = S * Math.exp((c ? 1 : -1) * z * mN), ks = ch ? (c ? ch.strikes.c : ch.strikes.p) : [];
        const K = ks.length ? ks.reduce((a, b) => (Math.abs(b - want) < Math.abs(a - want) ? b : a)) : null;
        const pr = K != null && ch ? ch.mid.get(`${c ? 'c' : 'p'}|${K}`) ?? null : null;
        next = { ex, exL: md(ex), K, pr: pr != null ? r2(pr) : null, z: r2(z), d: pr != null ? r2(pr - l.at) : null };
      }
    }
    return { k: `${l.t}|${l.ty}|${l.K}|${l.ex}`, t: l.t, ty: c ? 'c' : 'p', K: l.K, ex: l.ex, exL: md(l.ex), days: cd, td, q: l.n,
      at: r4(l.at), mk: l.mk != null ? r4(l.mk) : null, kp, sN: sN != null ? r2(sN) : null, s0: s0 != null ? r2(s0) : null, itm,
      intr: r2(Math.max(0, S > 0 ? (c ? S - l.K : l.K - S) : 0)), be: r2(c ? l.K + l.at : l.K - l.at),
      books: l.books.map((b) => x.bookName[b] ?? b), st, next };
  }).sort((a, b) => a.t.localeCompare(b.t) || a.ex.localeCompare(b.ex) || (a.ty === b.ty ? a.K - b.K : a.ty === 'c' ? -1 : 1));

  // ── Names: the price, the cadence, the delta line, the calendar ──
  const mon0 = (() => { const w = ymd(today).wd; return addDays(today, w === 0 ? 1 : w === 6 ? 2 : -(w - 1)); })();
  const tickers = [...new Set(rungs.map((r) => r.t))];
  const names = tickers.map((t) => {
    const rs = rungs.filter((r) => r.t === t), S = x.spot.get(t) ?? 0, P = x.prev.get(t) ?? 0;
    const cad: 'ladder' | 'weekly' = isLadder(t, x.legs) ? 'ladder' : 'weekly';
    const books = [...new Set(rs.flatMap((r) => r.books))];
    const fl = cad === 'ladder' ? x.flips.get(t) ?? null : null;
    const flip = cad !== 'ladder' ? null : !fl ? { now: false, price: null, up: null }
      : { now: fl.now, price: r2(fl.price), up: fl.now ? 0 : r2((fl.price / S - 1) * 100) };
    // Where the next roll goes, for the dashed day: the first ready rung's target, else the ladder's next expiry.
    const nextEx = rs.find((r) => r.next?.ex)?.next?.ex
      ?? (cad === 'ladder' ? (x.expiries.get(t) ?? []).find((e) => e > (rs.map((r) => r.ex).sort().at(-1) ?? today)) ?? null : null);
    const weeks = cad === 'ladder' ? 4 : 2, cal: Row[] = [];
    for (let w = 0; w < weeks; w++) for (let i = 0; i < 5; i++) {
      const d = addDays(mon0, 7 * w + i), on = rs.filter((r) => r.ex === d);
      const chip = (ty: 'c' | 'p') => {
        const g = on.filter((r) => r.ty === ty), q = g.reduce((a, r) => a + r.q, 0);
        if (!q) return null;
        const tone = g.some((r) => r.itm) ? 'itm' : g.some((r) => r.st === 'roll') ? 'roll' : 'run';
        return { k: ty, q, t: `${q} ${ty === 'c' ? (q === 1 ? 'call' : 'calls') : (q === 1 ? 'put' : 'puts')}`, tone };
      };
      const chips = [chip('c'), chip('p')].filter(Boolean) as Row[];
      const nx = !chips.length && d === nextEx;
      const first = !cal.length || ymd(d).d === 1;
      cal.push({ d, lbl: first ? md(d) : String(ymd(d).d), today: d === today, past: d < today, closed: !isTrading(d),
        chips: nx ? [{ k: 'n', q: 0, t: 'next', tone: 'next' }] : chips });
    }
    return { t, co: x.company(t), books, cad, px: r2(S), chg: P > 0 && S > 0 ? r2((S / P - 1) * 100) : null, flip, nextEx, cal };
  });

  // ── Totals (the page's row) ──
  const col = rungs.reduce((a, r) => a + r.at * r.q * 100, 0), left = rungs.reduce((a, r) => a + (r.mk ?? r.at) * r.q * 100, 0);
  const totals = { left: r2(left), kept: r2(col - left), collected: r2(col), roll: rungs.filter((r) => r.st === 'roll').length,
    itm: rungs.filter((r) => r.st === 'itm').length };

  // ── The banner: realized income by week and by month ──
  const monOf = (d: string) => { const w = ymd(d).wd; return addDays(d, w === 0 ? -6 : -(w - 1)); };
  const ev = x.realized.filter((e) => e.d >= x.start && e.d <= today);
  type P = { c: number; p: number };
  const add = (m: Map<string, Row>, key: string, mk: () => Row, e: IncReal) => {
    const o = m.get(key) ?? m.set(key, mk()).get(key)!;
    const s = e.kind === 'calls sold' ? 'c' : 'p';
    o.c += s === 'c' ? e.amt : 0; o.p += s === 'p' ? e.amt : 0;
    const bt = (o.by[e.t] ??= { c: 0, p: 0 }) as P; bt[s] += e.amt;
    const bb = (o.bk[e.book] ??= { c: 0, p: 0 }) as P; bb[s] += e.amt;
  };
  const wk = new Map<string, Row>(), mo = new Map<string, Row>();
  for (const e of ev) {
    const m0 = monOf(e.d);
    add(wk, m0, () => ({ k: m0, from: m0, to: addDays(m0, 4), c: 0, p: 0, by: {}, bk: {} }), e);
    const ym = e.d.slice(0, 7);
    add(mo, ym, () => ({ k: ym, c: 0, p: 0, by: {}, bk: {} }), e);
  }
  // Every week and month from the start to now, empty ones too, so the bars keep their places.
  const weeksAll: Row[] = [];
  for (let m0 = monOf(x.start); m0 <= monOf(today); m0 = addDays(m0, 7)) {
    const o = wk.get(m0) ?? { k: m0, from: m0, to: addDays(m0, 4), c: 0, p: 0, by: {}, bk: {} };
    const cur = m0 === monOf(today) && !(ymd(today).wd === 6 || ymd(today).wd === 0);
    weeksAll.push({ ...o, l: md(m0), range: `${md(m0)} to ${ymd(addDays(m0, 4)).m === ymd(m0).m ? ymd(addDays(m0, 4)).d : md(addDays(m0, 4))}`, cur });
  }
  const monthsAll: Row[] = [];
  for (let ym = x.start.slice(0, 7); ym <= today.slice(0, 7);) {
    const o = mo.get(ym) ?? { k: ym, c: 0, p: 0, by: {}, bk: {} };
    const [y, m] = ym.split('-').map(Number);
    monthsAll.push({ ...o, l: MON[m - 1], long: MONTH[m - 1], cur: ym === today.slice(0, 7), from: ym === x.start.slice(0, 7) ? md(x.start) : null });
    ym = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  }
  const rd = (o: Row) => ({ ...o, c: r2(o.c), p: r2(o.p),
    by: Object.fromEntries(Object.entries(o.by as Record<string, P>).map(([k, v]) => [k, [r2(v.c), r2(v.p)]])),
    bk: Object.fromEntries(Object.entries(o.bk as Record<string, P>).map(([k, v]) => [x.bookName[k] ?? k, [r2(v.c), r2(v.p)]])) });
  // What the shares cost, and each name's share average after every premium kept on it since the start.
  const capital = [...x.shares.values()].reduce((a, s) => a + (s.sh > 0 ? s.cost : 0), 0);
  const allBy = new Map<string, number>();
  for (const e of ev) allBy.set(e.t, (allBy.get(e.t) ?? 0) + e.amt);
  const shares: Row = {};
  for (const t of new Set([...allBy.keys(), ...tickers])) {
    const s = x.shares.get(t);
    shares[t] = s && s.sh > 0 && s.cost > 0
      ? { sh: s.sh, paid: r4(s.cost / s.sh), avg: r4((s.cost - (allBy.get(t) ?? 0)) / s.sh), co: x.company(t) }
      : { sh: 0, paid: null, avg: null, co: x.company(t) };
  }
  const banner = { start: x.start, capital: r2(capital), weeks: weeksAll.map(rd), months: monthsAll.map(rd), shares };

  return { v: 1, today, rungs, names, totals, banner };
}
