// ── The brief: New Home and Positions on the real book (handoff 6 Nov 2026, Pass 2) ──
// sunny-home hands this its reads; it turns them into the shared engine's inputs (days from now, each
// option's own IV, a 4% rate, dividends counted) and writes `payload.brief`: Your position, every name's
// status for the Positions logo strip, the totals row, the Time value sheet's sold legs, and the inputs the
// sunny-positions function prices on a grid when Positions opens a name. One engine, so the turns-short
// price on Home, To decide and the Positions chart is the same to the cent (README 12, invariant 1).
//
// No em dashes in any words written here (Nik).

import { type Div, holdings, type Holdings, type Kind, type Leg, NameBook, otmStrike, type Stop, yourPosition } from '../_shared/book-engine.ts';

type Row = Record<string, any>;
export type Moment = 'futures' | 'pre' | 'bell' | 'open' | 'last20' | 'last5' | 'post' | 'weekend';

/** Answer C5 (6 Nov 2026): a 4% rate. */
export const RATE = 0.04;

export interface BriefLeg {
  ticker: string; type: 'call' | 'put'; side: 'sold' | 'bought'; strike: number; expiry: string;
  n: number; avg: number; mark: number | null; iv: number | null; opened: string;
}
export interface BriefIn {
  today: string; wd: string; mins: number;
  isTrading: (d: string) => boolean; addDays: (d: string, n: number) => string;
  cal: Row[];                              // market_calendar rows (kind closed | early_close, closes "13:00:00")
  legs: BriefLeg[]; isLeap: (l: BriefLeg) => boolean;
  shares: Map<string, number>; shareAvg: Map<string, number>;
  spot: Map<string, number>; closes: Row[];   // daily_closes (ticker, date, close_price), oldest first
  chain: Row[];                            // option_chain_next (ticker, expiry, side, strike, iv)
  divRows: Row[];                          // dividends (ticker, ex_date, cash_amount, frequency), oldest first
  strategies: Record<string, string>;
}

/** The moment, as the app's clock has it (BriefCore Moment.at). */
export function momentOf(wd: string, m: number): Moment {
  if (wd === 'Sat') return 'weekend';
  if (wd === 'Sun') return m >= 18 * 60 ? 'futures' : 'weekend';
  if (wd === 'Fri' && m >= 16 * 60) return 'weekend';
  if (m < 4 * 60) return 'futures';
  if (m < 9 * 60 + 30) return 'pre';
  if (m < 9 * 60 + 35) return 'bell';
  if (m < 15 * 60 + 40) return 'open';
  if (m < 15 * 60 + 55) return 'last20';
  if (m < 16 * 60) return 'last5';
  if (m < 20 * 60) return 'post';
  return 'futures';
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAYNAME = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd, wd: new Date(Date.UTC(y, m - 1, dd)).getUTCDay() }; };
const dayDiff = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);
/** "Nov 13" within six months, else "Jan ’28" (the design's labels). */
export const expLabel = (d: string, daysOut: number) => { const x = ymd(d); return daysOut <= 183 ? `${MON[x.m - 1]} ${x.d}` : `${MON[x.m - 1]} ’${String(x.y).slice(2)}`; };
const longDay = (d: string) => { const x = ymd(d); return `${DOW[x.wd]} ${MON[x.m - 1]} ${x.d}`; };
const fk = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));
const n0 = (x: number) => Math.round(x).toLocaleString('en-US');
const good = (iv: number | null | undefined) => iv != null && iv > 0.03 && iv < 2.5;

/** The company name the brief writes ("Nike", "Alibaba", "FIS"). */
const CO: Record<string, string> = { BABA: 'Alibaba', LULU: 'Lululemon', NKE: 'Nike', NFLX: 'Netflix', UBER: 'Uber', FIS: 'FIS', PEP: 'PepsiCo',
  TSLA: 'Tesla', SPCX: 'SpaceX', NVDA: 'Nvidia', TLT: 'TLT', AAPL: 'Apple', MSFT: 'Microsoft', GOOGL: 'Alphabet', AMZN: 'Amazon', META: 'Meta' };
export const company = (t: string) => CO[t] ?? t;

export interface NameInput { t: string; S0: number; P0: number; iv: number; legs: Leg[]; divs: Div[]; stops: Stop[]; fridayStop: number;
  otm: { K: number; ex: string; days: number; label: string } | null }

export function buildBrief(x: BriefIn) {
  const { today, mins, addDays, isTrading } = x;
  const moment = momentOf(x.wd, mins);
  const early = new Map(x.cal.filter((c) => c.kind === 'early_close' && c.closes).map((c) => [String(c.date), Number(String(c.closes).slice(0, 2)) * 60 + Number(String(c.closes).slice(3, 5))]));
  const closeMin = (d: string) => early.get(d) ?? 960;
  /** Calendar days from now to a date's close (options stop at the early close too). */
  const daysTo = (d: string) => dayDiff(today, d) + (closeMin(d) - mins) / 1440;
  const lastTradingOnOrBefore = (d: string) => { let y = d; while (!isTrading(y)) y = addDays(y, -1); return y; };
  const nextTradingAfter = (d: string) => { let y = addDays(d, 1); while (!isTrading(y)) y = addDays(y, 1); return y; };

  // ── The Friday the card is about: this week's until its close, then next week's ──
  const wdN = ymd(today).wd, pastClose = isTrading(today) && mins >= closeMin(today);
  const nextFriday = wdN === 6 || wdN === 0 || (wdN === 5 && pastClose);
  let F = addDays(today, (5 - wdN + 7) % 7);
  if (wdN === 5 && pastClose) F = addDays(F, 7);
  F = lastTradingOnOrBefore(F);
  const th = Math.max(0, daysTo(F));

  // ── Legs still open (an expiry's legs end at its close) ──
  const ended = (exp: string) => exp < today || (exp === today && mins >= closeMin(today));
  const legsOpen = x.legs.filter((l) => !ended(l.expiry));
  const soldBy = legsOpen.some((l) => l.side === 'sold' && l.type === 'call' && l.expiry <= F);
  const weekend = nextFriday && !soldBy;

  // ── Prices: now and the previous close (on a day off, the last session's move) ──
  const lastSession = isTrading(today) ? today : lastTradingOnOrBefore(today);
  const closeOf = new Map<string, number>(), prevOf = new Map<string, number>();
  for (const c of x.closes) {
    const t = String(c.ticker).toUpperCase(), d = String(c.date), p = Number(c.close_price);
    if (d < lastSession) prevOf.set(t, p);
    if (d <= lastSession) closeOf.set(t, p);
  }

  // ── Dividends: the declared ones, then each name's regular one carried forward (answer C5) ──
  const divsOf = (t: string): Div[] => {
    const rows = x.divRows.filter((r) => String(r.ticker).toUpperCase() === t && Number(r.cash_amount) > 0);
    if (!rows.length) return [];
    const out: Div[] = [];
    for (const r of rows) if (String(r.ex_date) >= today) out.push({ days: dayDiff(today, String(r.ex_date)) - mins / 1440, amt: Number(r.cash_amount) });
    const last = rows[rows.length - 1], f = Number(last.frequency) || 0;
    let step = f >= 1 ? Math.round(12 / f) : 0;
    if (!step && rows.length >= 2) { const gap = dayDiff(String(rows[rows.length - 2].ex_date), String(last.ex_date)); step = gap > 300 ? 12 : gap > 150 ? 6 : gap > 60 ? 3 : 1; }
    if (!step || step === 0) return out;
    const { y, m, d } = ymd(String(last.ex_date));
    for (let i = 1; i <= 40; i++) {
      const dt = new Date(Date.UTC(y, m - 1 + step * i, Math.min(d, 28))).toISOString().slice(0, 10);
      const dd = dayDiff(today, dt);
      if (dd > 1200) break;
      if (dt > String(last.ex_date) && dt >= today) out.push({ days: dd - mins / 1440, amt: Number(last.cash_amount) });
    }
    return out;
  };

  // ── The name's IV for its priced move: the chain's IV at the strike nearest the price (call and put
  //    averaged), on the card's Friday if that chain is cached, else the nearest expiry still trading. An
  //    expiry that has ended is never used: after its close its IVs are noise (6 Nov: NKE 0.75, FIS 1.18). ──
  const ivOf = (t: string, S0: number, ls: BriefLeg[]) => {
    const rows = x.chain.filter((r) => String(r.ticker).toUpperCase() === t && good(Number(r.iv)) && !ended(String(r.expiry)));
    if (rows.length) {
      const exps = [...new Set(rows.map((r) => String(r.expiry)))].sort();
      const e = exps.includes(F) ? F : exps[0];
      const at = rows.filter((r) => String(r.expiry) === e);
      const k = at.reduce((a, r) => (Math.abs(Number(r.strike) - S0) < Math.abs(a - S0) ? Number(r.strike) : a), Number(at[0].strike));
      const ivs = at.filter((r) => Number(r.strike) === k).map((r) => Number(r.iv));
      if (ivs.length) return ivs.reduce((a, b) => a + b, 0) / ivs.length;
    }
    const leg = [...ls].filter((l) => good(l.iv)).sort((a, b) => a.expiry.localeCompare(b.expiry))[0];
    return leg?.iv ?? 0.35;
  };

  // ── Date-slider stops: now, then each session's close to the last sold expiry (at least the Friday) ──
  const stopsFor = (ls: BriefLeg[]): { stops: Stop[]; fri: number } => {
    const lastSold = ls.filter((l) => l.side === 'sold').map((l) => l.expiry).sort().at(-1);
    const end = lastSold && lastSold > F ? lastSold : F;
    const exps = new Set(ls.filter((l) => l.side === 'sold').map((l) => l.expiry));
    /* Mon to Thu, and Friday until its close: Today (now) first. Friday after the close and the weekend: the
       slider runs Monday to Friday of next week (answer 3), so there is no Today stop. Today's own close is a
       stop only on an expiry day (Friday's close is the stop Home opens on). */
    const stops: Stop[] = [];
    if (!nextFriday) stops.push({ tt: 0, short: 'Today', phrase: 'today', long: longDay(today), friday: false });
    const start = isTrading(today) && !pastClose ? today : nextTradingAfter(today);
    for (let d = start; d <= end; d = nextTradingAfter(d)) {
      const isFri = exps.has(d) || d === F || ymd(d).wd === 5;
      if (d === today && !isFri) continue;
      const lbl = `${MON[ymd(d).m - 1]} ${ymd(d).d}`;
      stops.push({ tt: +daysTo(d).toFixed(4), short: isFri ? lbl : DOW[ymd(d).wd], phrase: isFri ? `at the ${lbl} close` : `on ${DAYNAME[ymd(d).wd]}`,
        long: `${longDay(d)}${isFri ? ' close' : ''}`, friday: isFri });
    }
    if (!stops.length) stops.push({ tt: 0, short: 'Today', phrase: 'today', long: longDay(today), friday: false });
    const fri = Math.max(0, stops.findIndex((s) => s.tt >= th - 0.001));
    return { stops, fri };
  };

  // ── The OTM call a fix buys: about 7.5% out, the monthly about ten months on (A5, as designed) ──
  const otmFor = (S0: number) => {
    const t = ymd(today);
    const first = new Date(Date.UTC(t.y, t.m - 1 + 10, 1)), wd1 = first.getUTCDay();
    const third = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), 1 + ((5 - wd1 + 7) % 7) + 14)).toISOString().slice(0, 10);
    const ex = lastTradingOnOrBefore(third), days = daysTo(ex);
    return { K: otmStrike(S0), ex, days: +days.toFixed(3), label: expLabel(ex, days) };
  };

  // ── Every name held ──
  const tickers = [...new Set([...legsOpen.map((l) => l.ticker), ...[...x.shares].filter(([, n]) => n > 0).map(([t]) => t)])].sort();
  const inputs: NameInput[] = [];
  const books: NameBook[] = [];
  for (const t of tickers) {
    const ls = legsOpen.filter((l) => l.ticker === t);
    const S0 = x.spot.get(t) ?? closeOf.get(t) ?? 0;
    if (!(S0 > 0)) continue;
    const P0 = prevOf.get(t) ?? S0, ivN = ivOf(t, S0, ls), sh = x.shares.get(t) ?? 0;
    const legs: Leg[] = [];
    if (sh > 0) { const avg = x.shareAvg.get(t) ?? 0; legs.push({ k: 'sh', kind: 'shares', ty: 'S', K: avg, q: sh, days: 0, iv: 0, ex: '', label: `Shares ${n0(sh)}${avg > 0 ? ` at $${avg.toFixed(2)}` : ''}` }); }
    for (const l of ls) {
      const kind: Kind = l.side === 'sold' ? (l.type === 'call' ? 'sc' : 'sp') : l.type === 'put' ? 'ins' : x.isLeap(l) ? 'leaps' : 'otm';
      const days = daysTo(l.expiry), el = expLabel(l.expiry, days);
      const nm = kind === 'sc' ? 'Calls' : kind === 'sp' ? 'Puts' : kind === 'ins' ? 'Insurance puts' : kind === 'leaps' ? 'LEAPS' : 'OTM calls';
      legs.push({ k: `${kind}-${fk(l.strike)}-${l.expiry}`, kind, ty: l.type === 'call' ? 'C' : 'P', K: l.strike, q: l.side === 'sold' ? -l.n : l.n,
        days: +days.toFixed(4), iv: good(l.iv) ? l.iv! : ivN, ex: l.expiry, label: `${nm} ${fk(l.strike)} ×${l.n}, ${el}`,
        at: l.avg, ...(l.mark != null ? { now: l.mark } : {}) });
    }
    if (!legs.length) continue;
    const divs = divsOf(t), { stops, fri } = stopsFor(ls);
    const nb = new NameBook({ t, S0, P0, iv: ivN, legs, divs, r: RATE });
    books.push(nb);
    inputs.push({ t, S0, P0, iv: ivN, legs, divs, stops, fridayStop: fri, otm: otmFor(S0) });
  }

  // ── Your position ──
  let shT = 0, cvT = 0;
  for (const nb of books) {
    const sh = nb.legs.filter((l) => l.kind === 'shares').reduce((a, l) => a + l.q, 0);
    const ins = nb.legs.filter((l) => l.kind === 'ins').reduce((a, l) => a + l.q * 100, 0);
    shT += sh; cvT += Math.min(sh, ins);
  }
  /* Early assignment (A4, as proposed): ex-dividend within 7 days on a name with a call sold that is still
     open on the ex-date, in the money, with less time value left than the dividend. Declared dividends only. */
  const assign: { t: string; exLabel: string }[] = [];
  for (const nb of books) {
    const d = x.divRows.find((r) => String(r.ticker).toUpperCase() === nb.t && String(r.ex_date) >= today && dayDiff(today, String(r.ex_date)) <= 7);
    if (!d) continue;
    const amt = Number(d.cash_amount), ex = String(d.ex_date);
    const hit = nb.legs.some((l) => l.kind === 'sc' && l.ex >= ex && nb.S0 > l.K && (l.now ?? 0) - (nb.S0 - l.K) < amt);
    if (hit) assign.push({ t: nb.t, exLabel: longDay(ex) });
  }
  const sub = moment === 'weekend' ? (weekend ? 'Calls ended Friday · to next Friday' : 'Next week · by next Friday’s close')
    : moment === 'post' ? 'At the close · by Friday'
    : moment === 'pre' || moment === 'futures' ? 'Before the bell · by Friday’s close' : 'Now · by Friday’s close';
  const position = books.length
    ? yourPosition(books, { th, weekend, nextFriday, sub }, company, { shares: shT, covered: cvT }, assign)
    : null;

  // ── Per name: the logo strip (short at its priced move by Friday), the strategy, the holdings ──
  const names = books.map((nb) => {
    const row = position?.rows.find((r) => r.id === nb.t);
    const h = holdings(nb);
    return { t: nb.t, name: company(nb.t), S0: nb.S0, P0: nb.P0, iv: +nb.iv.toFixed(4), sd: +nb.sd.toFixed(3),
      st: row?.st ?? 0, short: (row?.st ?? 0) === 2, fp: row?.fp ?? null, strategy: x.strategies[nb.t] ?? '',
      size: Math.round(h.sh[0] + h.lp[0] + h.oc[0]), h: roundH(h),
      gain: Math.round(nb.legs.filter((l) => l.kind === 'shares').reduce((a, l) => a + l.q * (nb.S0 - l.K), 0)) };
  });
  const totals = names.reduce((a, n) => addH(a, n.h), zeroH());

  // ── The Time value sheet: every sold leg still open (answer 2: the REAL sold legs) ──
  const sold = books.flatMap((nb) => nb.legs.filter((l) => l.q < 0).map((l) => {
    const now = l.now ?? 0, at = l.at ?? 0, q = -l.q;
    const itm = l.ty === 'C' ? nb.S0 > l.K : nb.S0 < l.K;
    const cap = at > 0 ? Math.round((1 - now / at) * 100) : 0;
    /* The sheet's "time value left": what is still to decay, less what the leg is in the money. */
    const intr = l.ty === 'C' ? Math.max(0, nb.S0 - l.K) : Math.max(0, l.K - nb.S0), tvPer = Math.max(0, now - intr);
    return { t: nb.t, name: company(nb.t), kind: l.kind, put: l.ty === 'P', K: l.K, q, ex: l.ex, exLabel: expLabel(l.ex, l.days),
      at, now, col: Math.round(q * 100 * at), left: Math.round(q * 100 * now), kept: Math.round(q * 100 * (at - now)), cap, itm,
      intr: +intr.toFixed(2), tvPer: +tvPer.toFixed(2), tvLeft: Math.round(q * 100 * tvPer),
      ready: tvPer < 0.05 || cap >= 90 || itm };
  })).sort((a, b) => a.ex.localeCompare(b.ex) || b.left - a.left);
  const col = sold.reduce((a, s) => a + s.col, 0), left = sold.reduce((a, s) => a + s.left, 0), tvLeft = sold.reduce((a, s) => a + s.tvLeft, 0);
  const timeValue = { col, left, kept: col - left, cap: col > 0 ? Math.round((col - left) / col * 100) : 0, tvLeft,
    tvCap: col > 0 ? Math.round((1 - tvLeft / col) * 100) : 0, legs: sold };

  return {
    brief: {
      v: 1, moment, today, friday: F, fridayLabel: longDay(F), nextFriday, weekend, th: +th.toFixed(4),
      position, names, totals, timeValue,
    },
    inputs: { v: 1, built_at: new Date().toISOString(), r: RATE, names: inputs },
  };
}

type H = Holdings;
const zeroH = (): H => ({ sh: [0, 0], lp: [0, 0], oc: [0, 0], ip: [0, 0], sc: [0, 0], sp: [0, 0], tv: { lp: 0, oc: 0, ip: 0, sc: 0, sp: 0 } });
const roundH = (h: H): H => {
  const r = (p: [number, number]): [number, number] => [Math.round(p[0]), Math.round(p[1])];
  return { sh: r(h.sh), lp: r(h.lp), oc: r(h.oc), ip: r(h.ip), sc: r(h.sc), sp: r(h.sp),
    tv: { lp: Math.round(h.tv.lp), oc: Math.round(h.tv.oc), ip: Math.round(h.tv.ip), sc: Math.round(h.tv.sc), sp: Math.round(h.tv.sp) } };
};
const addH = (a: H, b: H): H => {
  const s = (p: [number, number], q: [number, number]): [number, number] => [p[0] + q[0], p[1] + q[1]];
  return { sh: s(a.sh, b.sh), lp: s(a.lp, b.lp), oc: s(a.oc, b.oc), ip: s(a.ip, b.ip), sc: s(a.sc, b.sc), sp: s(a.sp, b.sp),
    tv: { lp: a.tv.lp + b.tv.lp, oc: a.tv.oc + b.tv.oc, ip: a.tv.ip + b.tv.ip, sc: a.tv.sc + b.tv.sc, sp: a.tv.sp + b.tv.sp } };
};
