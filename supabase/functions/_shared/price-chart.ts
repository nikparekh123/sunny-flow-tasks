// The Positions Price chart (handoff 2026-11-13-positions 2 §3.4, Web Dark v2 `P.pc` in r150x; Nik, 13 Nov 2026:
// "Just price chart"). One model for the web (src/web/positions/Band.tsx) and the phone (PositionsModels.swift ports
// it line for line). Pure: dates in, geometry out.
//
//   Time: the range drawn, then the trading days left to the Friday expiry kept open after today's dot, on one scale.
//     1W draws hours (7 a session: 10:00 to 16:00 New York, from sunny-chart's `hours`, our Theta quotes; an hour with
//     no quote is read on the straight line between the day's closes) and labels each day at its start; the longer
//     ranges draw daily closes and label weeks (1M) or months (January reads the year). Labels thin out from the
//     right; the last one up to today is white.
//   The Friday: the first Friday after today (from a Friday on, and all weekend, next Friday: the same rule as
//     Intelligence, P1), its last trading day when the Friday is shut.
//   Scale: today, the sold strikes and What if first (at least 6% of the price, centred, × 1.24), then everything drawn;
//     a bought strike joins when it adds under 40%, past that it pins to the edge with ↑ or ↓ and no line. Pad 5%.
//   Strikes: one line per strike, side and type (legs on one strike in different expiries share it); a tag column on
//     the right: the strike with C or P after it (Nik, 13 Nov 2026, option A: "how do i know which is put and which
//     is call?"), then how far from today; puts in a grey capsule; today's price a white capsule. Tags sort
//     by price and spread in rows; a group holding today's price stays pinned to it; a tag off its line gets a short
//     connector.
// No em dashes in any words here (Nik).

export type PCRange = '1W' | '1M' | '3M' | 'YTD' | '1Y' | 'All';
export const PC_RANGES: PCRange[] = ['1W', '1M', '3M', 'YTD', '1Y', 'All'];
export const PC_WORDS: Record<PCRange, string> = { '1W': 'Past week', '1M': 'Past month', '3M': 'Past 3 months', YTD: 'This year', '1Y': 'Past year', All: 'All time' };

/** A strike to draw: a held option leg (on), or a What if trade (`w`). `label` reads the legs in full for the hover. */
export interface PCStrike { key: string; K: number; ty: 'C' | 'P'; q: number; w: boolean; label: string }
export interface PCIn {
  dates: string[]; closes: number[];
  /** sunny-chart's hours: { day: [10:00 ... 16:00] }, null where no quote. */
  hours?: Record<string, (number | null)[]> | null;
  S0: number;
  /** New York's date and minutes since midnight now. */
  today: string; mins: number;
  /** Days the market is shut (the calendar's holidays). */
  closed: Set<string>;
  rg: PCRange;
  strikes: PCStrike[];
  phone: boolean;
}
/** A point drawn: x from 0 to 1 across the plot, its value, the day and (1W) the hour, 9 for the close before the day. */
export interface PCPoint { x: number; v: number; d: string; h: number | null; now: boolean }
export interface PCTag {
  key: string; top: number; n: string; s: string; px: boolean; sold: boolean; put: boolean; w: boolean; out: boolean; title: string;
}
export interface PCOut {
  pts: PCPoint[]; up: boolean; move: number; words: string;
  /** Today's dot: x 0 to 1, y in px. */
  dotX: number; dotY: number;
  lines: { key: string; y: number; kind: 'sold' | 'bought' | 'w' }[];
  tags: PCTag[];
  conn: { y0: number; y1: number }[];
  xl: { key: string; x: number; t: string; now: boolean }[];
  /** The plot's height and the tag rows, in px. */
  CH: number; TH: number;
  friday: string; fridayWords: string;
  /** The price at a y in px, and the y of a price. */
  y: (v: number) => number;
  aria: string;
}

const MN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const dt = (iso: string) => new Date(iso.slice(0, 10) + 'T12:00:00Z');
const iso = (d: Date) => d.toISOString().slice(0, 10);
const dow = (s: string) => dt(s).getUTCDay();
export const pcFk = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));
const dpc = (k: number, S0: number) => { const p = Math.abs(k / S0 - 1) * 100; return (p < 0.1 ? p.toFixed(2) : p.toFixed(1)) + '%'; };
const trading = (s: string, closed: Set<string>) => { const w = dow(s); return w > 0 && w < 6 && !closed.has(s); };
const addDays = (s: string, n: number) => { const d = dt(s); d.setUTCDate(d.getUTCDate() + n); return iso(d); };

/** The Friday the chart runs to: the first Friday after today (P1). */
export function pcFriday(today: string): string {
  return addDays(today, (5 - dow(today) + 7) % 7 || 7);
}
/** "Fri Nov 20". */
export const pcDayWords = (s: string) => { const d = dt(s); return `${WD[d.getUTCDay()]} ${MN[d.getUTCMonth()]} ${d.getUTCDate()}`; };

export function priceChart(I: PCIn): PCOut | null {
  const { S0, today, mins, closed, rg, phone } = I;
  const CH = phone ? 200 : 280, PT = phone ? 20 : 24, TH = phone ? 18 : 22;
  const pairs: [string, number][] = [];
  for (let i = 0; i < Math.min(I.dates.length, I.closes.length); i++) if (I.closes[i] > 0) pairs.push([I.dates[i].slice(0, 10), +I.closes[i]]);
  // Today: a session once the bell has rung. Its close is the price now; before the bell the line ends on the last
  // close, moved to the price now so the dot sits on it.
  const live = trading(today, closed) && mins >= 9 * 60 + 30;
  if (pairs.length && pairs[pairs.length - 1][0] === today) pairs[pairs.length - 1][1] = S0;
  else if (live) pairs.push([today, S0]);
  else if (pairs.length) pairs[pairs.length - 1][1] = S0;
  if (pairs.length < 2 || !(S0 > 0)) return null;
  const nAll = pairs.length - 1;
  const yr = today.slice(0, 4);
  const nR = Math.max(1, Math.min(nAll, rg === '1W' ? 5 : rg === '1M' ? 21 : rg === '3M' ? 63 : rg === '1Y' ? 252 : rg === 'All' ? nAll
    : pairs.filter(([d]) => d.slice(0, 4) === yr).length));
  const sl = pairs.slice(pairs.length - 1 - nR);
  const last = sl[sl.length - 1][0];
  const inDay = live && last === today && mins < 16 * 60;

  // The days left to the Friday, after the last session drawn (holidays skipped; a shut Friday ends on its Thursday).
  const fri = pcFriday(today);
  const FT: string[] = [];
  for (let d = addDays(last, 1); d <= fri; d = addDays(d, 1)) if (trading(d, closed)) FT.push(d);
  const FD = FT.length;
  const friday = FT.length ? FT[FT.length - 1] : fri;

  const wk = rg === '1W';
  const pts: PCPoint[] = [];
  let U: number;
  if (wk) {
    U = (nR + FD) * 7;
    pts.push({ x: 0, v: sl[0][1], d: sl[0][0], h: 9, now: false });
    for (let d = 0; d < nR; d++) {
      const day = sl[d + 1][0], a = sl[d][1], b = sl[d + 1][1], hr = I.hours?.[day] ?? null, isToday = inDay && d === nR - 1;
      // Known points this session: the close before it (k 0), each hour with a quote, and its end: the close (k 7),
      // or the price now partway through today.
      const kNow = isToday ? Math.max(0.5, Math.min(7, (mins - 9 * 60) / 60)) : 7;
      const known: [number, number][] = [[0, a]];
      for (let k = 1; k <= 7; k++) {
        if (k >= kNow) break;
        const v = hr?.[k - 1];
        if (v != null && v > 0) known.push([k, v]);
      }
      known.push([kNow, b]);
      const at = (k: number) => { let j = 0; while (j < known.length - 2 && known[j + 1][0] < k) j++; const [k0, v0] = known[j], [k1, v1] = known[j + 1]; return k1 > k0 ? v0 + (v1 - v0) * (k - k0) / (k1 - k0) : v1; };
      for (let k = 1; k < kNow; k++) pts.push({ x: (d * 7 + k) / U, v: hr?.[k - 1] ?? at(k), d: day, h: 9 + k, now: false });
      pts.push({ x: (d * 7 + kNow) / U, v: b, d: day, h: isToday ? null : 16, now: isToday });
    }
  } else {
    U = nR + FD;
    const stp = Math.max(1, Math.ceil(sl.length / 130));
    sl.forEach(([d, v], i) => { if (i % stp === 0 || i === sl.length - 1) pts.push({ x: i / U, v, d, h: null, now: false }); });
  }
  const end = pts[pts.length - 1];
  end.v = S0;

  // The scale.
  const opt = I.strikes;
  const sK = opt.filter((l) => l.q < 0 || l.w).map((l) => l.K), hs = pts.map((p) => p.v);
  let a0 = Math.min(S0, ...sK), b0 = Math.max(S0, ...sK);
  { const sp = Math.max(b0 - a0, S0 * 0.06), md = (a0 + b0) / 2; a0 = Math.min(md - sp * 0.62, ...hs); b0 = Math.max(md + sp * 0.62, ...hs); }
  { const r0 = b0 - a0; for (const l of opt) if (l.q > 0 && !l.w) { if (l.K < a0 && a0 - l.K <= r0 * 0.4) a0 = l.K; if (l.K > b0 && l.K - b0 <= r0 * 0.4) b0 = l.K; } const q = (b0 - a0) * 0.05; a0 -= q; b0 += q; }
  const y = (v: number) => ((b0 - v) / (b0 - a0)) * CH;

  // One line per strike, side and type; What if trades their own.
  interface G { kk: string; sd: boolean; ty: 'C' | 'P'; K: number; w: boolean; ls: string[] }
  const gp = new Map<string, G>();
  for (const l of opt) {
    const kk = l.w ? 'w' + l.key : (l.q < 0 ? 's' : 'b') + l.ty + l.K;
    const g = gp.get(kk) ?? { kk, sd: l.q < 0, ty: l.ty, K: l.K, w: l.w, ls: [] };
    g.ls.push(l.label); gp.set(kk, g);
  }
  const GS = [...gp.values()];
  interface T { key: string; y: number; px: boolean; out: boolean; up: boolean; g?: G; cy: number }
  const tg: T[] = [{ key: 'px', y: y(S0), px: true, out: false, up: false, cy: 0 }, ...GS.map((g) => {
    const yy = y(g.K), out = yy < 0 || yy > CH;
    return { key: g.kk, y: out ? (yy < 0 ? 0 : CH) : yy, out, up: yy < 0, g, px: false, cy: 0 };
  })].sort((p, q) => p.y - q.y);
  type C = T[] & { top?: number };
  const cl: C[] = tg.map((x) => [x] as C);
  const place = (c: C) => {
    const j = c.findIndex((x) => x.px);
    const top = j >= 0 ? c[j].y - PT / 2 - j * PT : c.reduce((a, x, i) => a + x.y - i * PT, 0) / c.length - PT / 2;
    c.top = Math.max(0, Math.min(CH - PT * c.length, top));
  };
  cl.forEach(place);
  for (let it = 0, mg = true; mg && it < 30; it++) {
    mg = false;
    for (let i = 0; i < cl.length - 1; i++) if (cl[i].top! + cl[i].length * PT > cl[i + 1].top!) { const c = [...cl[i], ...cl[i + 1]] as C; place(c); cl.splice(i, 2, c); mg = true; break; }
  }
  cl.forEach((c) => c.forEach((x, i) => { x.cy = c.top! + i * PT + PT / 2; }));
  const tags: PCTag[] = tg.map((x) => {
    if (x.px) return { key: 'px', top: x.cy - TH / 2, n: S0.toFixed(2), s: '', px: true, sold: true, put: false, w: false, out: false, title: `Today ${S0.toFixed(2)}` };
    const g = x.g!;
    return { key: x.key, top: x.cy - TH / 2, n: `${pcFk(g.K)} ${g.ty}`, s: dpc(g.K, S0) + (x.out ? (x.up ? ' ↑' : ' ↓') : ''), px: false, sold: g.sd, put: g.ty === 'P', w: g.w, out: x.out,
      title: g.ls.join(', ') + (x.out ? `, off the chart ${x.up ? 'above' : 'below'}` : '') };
  });
  const conn = tg.filter((x) => !x.px && !x.out && Math.abs(x.cy - x.y) > 3).map((x) => ({ y0: x.y, y1: x.cy }));
  const lines = GS.filter((g) => { const yy = y(g.K); return yy >= 0 && yy <= CH; })
    .map((g) => ({ key: g.kk, y: y(g.K), kind: (g.w ? 'w' : g.sd ? 'sold' : 'bought') as 'sold' | 'bought' | 'w' }));

  // The labels under the chart.
  const xl0: { x: number; t: string; fut: boolean }[] = [];
  if (wk) {
    for (let d = 0; d < nR; d++) xl0.push({ x: (d * 7) / U, t: WD[dow(sl[d + 1][0])], fut: false });
    FT.forEach((s, j) => xl0.push({ x: ((nR + j) * 7) / U, t: WD[dow(s)], fut: true }));
  } else {
    for (let i = 1; i <= nR; i++) {
      const a = dt(sl[i][0]), b = dt(sl[i - 1][0]);
      if (rg === '1M' ? a.getUTCDay() < b.getUTCDay() || (a.getTime() - b.getTime()) > 3 * 864e5 : a.getUTCMonth() !== b.getUTCMonth())
        xl0.push({ x: i / U, t: rg === '1M' ? `${MN[a.getUTCMonth()]} ${a.getUTCDate()}` : a.getUTCMonth() === 0 ? String(a.getUTCFullYear()) : MN[a.getUTCMonth()], fut: false });
    }
  }
  const gX = (phone ? (wk ? 10 : 17) : (wk ? 6 : 8.5)) / 100, xl: typeof xl0 = [];
  xl0.slice().reverse().forEach((x) => { if (!xl.length || xl[xl.length - 1].x - x.x >= gX - 1e-9) xl.push(x); });
  xl.reverse();
  let li = -1; xl.forEach((x, i) => { if (!x.fut) li = i; });

  const move = S0 / sl[0][1] - 1;
  return {
    pts, up: move >= 0, move, words: PC_WORDS[rg], dotX: end.x, dotY: y(S0), lines, tags, conn,
    xl: xl.map((x, i) => ({ key: 'x' + i, x: x.x, t: x.t, now: i === li })), CH, TH, friday, fridayWords: pcDayWords(friday), y,
    aria: `${PC_WORDS[rg].toLowerCase()}, today ${S0.toFixed(2)}. ` + GS.map((g) => `${g.ls.join(', ')}, ${dpc(g.K, S0)} ${g.K >= S0 ? 'above' : 'below'}`).join('; '),
  };
}
