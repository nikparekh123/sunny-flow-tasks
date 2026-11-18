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
//   Tag colours (Nik, 14 Nov 2026, "4 + 2"): the text is bright on a solid pill so the numbers read; a sold strike's %
//     wears how close it is (PCTone, the Sold in SD rings: red under 0.5 SD or in the money, orange to 1 SD, quiet past).
//
// Round 162a (handoff 2026-11-18 CHANGES "Web · Positions · Price chart", Nov 16), all OPTIONAL so the fields above
// keep meaning what they meant (the phone's Swift port reads them):
//   `iv` in: this week's IV (the name's IV on the Friday chain at the strike nearest the price, Home's brief_inputs).
//     m0 = iv × √(max(1, days left) / 252) is this week's 1 SD move; every strike's SD is |ln(K / S0)| ÷ m0.
//   Lines get `ty`, a name ("Sold call 36", "Sold put 34", "Hedge call 42.5", "Hedge put 33", "What if 36"; every call
//     bought is a Hedge call, LEAPS too, Nik's rule) and where it sits: above its line (`lt` -16) or below (2), or
//     hidden (`lo` false) when both would overlap another name or leave the plot.
//   Tags get `k` (the strike), `ty`, `z` (SD on this week's move), `sd` ("0.46 SD", "ITM" for a sold strike in the
//     money, an arrow when off the chart) and `zTone` (red under 0.5 SD or in the money, orange to 1, quiet past).
//   `near`: the nearest sold call and put (in the money first, then SD), nearest first, for the card under the chart.
//   `room`: green between the nearest sold call above and sold put below (any expiry), faint red past them; only
//     when a sold strike expires by this Friday (PCStrike `ex`).
// Round 164 (Nov 17), the 1 SD switch, `cone` in (honoured on 1W and 1M only, with an IV and a day left):
//   The cone from today's dot to the Friday close: S0·e^(±m0·√(t)), t the share of the days left. The scale widens to
//   take in its ends (± 8% of its width); `yb` and `tf` carry the scale before (the drawn line and the cone ride one
//   transform, y = yb × sy + ty), `y` the one after. Fills: green inside the nearest sold strikes, red where the cone
//   spills past them. A dot where the cone first reaches each sold strike (not in the money, under 1 SD): the day
//   is days left × z²; the nearest a side gets a drop line and, on 1W, its weekday under the axis.
//   1W labels read Last week and This week (Nik, Nov 17), not each day.
// No em dashes in any words here (Nik).

export type PCRange = '1W' | '1M' | '3M' | 'YTD' | '1Y' | 'All';
export const PC_RANGES: PCRange[] = ['1W', '1M', '3M', 'YTD', '1Y', 'All'];
export const PC_WORDS: Record<PCRange, string> = { '1W': 'Past week', '1M': 'Past month', '3M': 'Past 3 months', YTD: 'This year', '1Y': 'Past year', All: 'All time' };

/** A strike to draw: a held option leg (on), or a What if trade (`w`). `label` reads the legs in full for the hover. */
/** How close a sold strike is, the Sold in SD rings' colours: red under 0.5 SD or in the money, orange 0.5 to 1 SD,
    quiet past 1 SD (Nik, 14 Nov 2026, "4 + 2": the tag's % wears it). */
export type PCTone = 'red' | 'orange' | 'quiet';
/** `ex`: the leg's expiry (ISO), for the room's "a sold strike this week" (optional). */
export interface PCStrike { key: string; K: number; ty: 'C' | 'P'; q: number; w: boolean; label: string; tone?: PCTone | null; ex?: string }
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
  /** This week's IV (162a). Without it: no SD, no cone, the tags keep the %. */
  iv?: number;
  /** The 1 SD layer on (164). */
  cone?: boolean;
}
/** A point drawn: x from 0 to 1 across the plot, its value, the day and (1W) the hour, 9 for the close before the day. */
export interface PCPoint { x: number; v: number; d: string; h: number | null; now: boolean }
export interface PCTag {
  key: string; top: number; n: string; s: string; px: boolean; sold: boolean; put: boolean; w: boolean; out: boolean; title: string;
  /** A sold strike's closeness (the nearest of its legs); null for bought, What if, today or a sold leg without an SD. */
  tone: PCTone | null;
  /** 162a: the strike ("36"), its type, its SD on this week's move (null without an IV), "0.46 SD" or "ITM" (plus ↑ or
      ↓ off the chart; null without an IV), that SD's colour (sold strikes only), in the money. */
  k?: string; ty?: 'C' | 'P' | null; z?: number | null; sd?: string | null; zTone?: PCTone | null; itm?: boolean;
}
export interface PCLine {
  key: string; y: number; kind: 'sold' | 'bought' | 'w';
  /** 162a: the type, the name at the line's right end, its offset from the line in px (-16 above, 2 below), shown. */
  ty?: 'C' | 'P'; name?: string; lt?: number; lo?: boolean;
}
/** 162a: one of the nearest sold strikes for the card under the chart. `d` reads "↑2.0% · 0.46 SD" or "in the money
    by $1.20"; `reach` the trading days until the 1 SD cone reaches it (null: in the money, or outside the cone);
    `day` that day's weekday ("Wed"), `fri` the last day's ("Fri"). */
export interface PCNear { key: string; ty: 'C' | 'P'; name: string; K: number; itm: boolean; z: number; d: string; tone: PCTone; reach: number | null; day: string | null; fri: string }
/** 164: the cone, in px on the scale before it widened (`yb`); x 0 to 1. Fills are [top edge, bottom edge] on X. */
export interface PCCone {
  X: number[]; YU: number[]; YD: number[];
  fG: [number[], number[]] | null; fU: [number[], number[]] | null; fD: [number[], number[]] | null;
  /** The cone's ends at the Friday close. */
  lo: number; hi: number;
  /** Where it first reaches each sold strike (y in px on the widened scale), and the drop lines for the nearest a side. */
  dots: { key: string; x: number; y: number; ty: 'C' | 'P' }[];
  drops: { key: string; x: number; y: number; ty: 'C' | 'P'; day: string }[];
}
export interface PCOut {
  pts: PCPoint[]; up: boolean; move: number; words: string;
  /** Today's dot: x 0 to 1, y in px. */
  dotX: number; dotY: number;
  lines: PCLine[];
  tags: PCTag[];
  conn: { y0: number; y1: number }[];
  /** `c`/`b` (164): a cone day under its drop line, in its strike's type colour, bold. */
  xl: { key: string; x: number; t: string; now: boolean; c?: 'C' | 'P'; b?: boolean }[];
  /** 162a and 164 (optional for older readers): this week's 1 SD move (0 without an IV), the trading days left, the
      switch can show (1W or 1M, an IV, a day left), it is on, the scale before the cone widened it and the transform
      from it (y = yb × sy + ty, px), the room, the nearest sold strikes, the cone. */
  m0?: number; FD?: number; coneOk?: boolean; coneOn?: boolean;
  yb?: (v: number) => number; tf?: { ty: number; sy: number };
  room?: { top: number; bottom: number; up: boolean; dn: boolean } | null;
  near?: PCNear[];
  cone?: PCCone | null;
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
const TONE_RANK: Record<PCTone, number> = { quiet: 0, orange: 1, red: 2 };
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
  // 162a: this week's 1 SD move. 164: with the cone on, the scale widens to take in its ends at the Friday close.
  const m0 = I.iv != null && I.iv > 0 ? I.iv * Math.sqrt(Math.max(1, FD) / 252) : 0;
  const coneOk = (wk || rg === '1M') && FD >= 1 && m0 > 0, coneOn = coneOk && !!I.cone;
  const A0 = a0, B0 = b0;
  if (coneOn) { const cu = S0 * Math.exp(m0), cd = S0 * Math.exp(-m0), q = (cu - cd) * 0.08; a0 = Math.min(a0, cd - q); b0 = Math.max(b0, cu + q); }
  const y = (v: number) => ((b0 - v) / (b0 - a0)) * CH;
  const yb = (v: number) => ((B0 - v) / (B0 - A0)) * CH;
  const tf = { ty: ((b0 - B0) / (b0 - a0)) * CH, sy: (B0 - A0) / (b0 - a0) };

  // One line per strike, side and type; What if trades their own.
  interface G { kk: string; sd: boolean; ty: 'C' | 'P'; K: number; w: boolean; ls: string[]; tone: PCTone | null }
  const gp = new Map<string, G>();
  for (const l of opt) {
    const kk = l.w ? 'w' + l.key : (l.q < 0 ? 's' : 'b') + l.ty + l.K;
    const g = gp.get(kk) ?? { kk, sd: l.q < 0, ty: l.ty, K: l.K, w: l.w, ls: [], tone: null };
    g.ls.push(l.label); gp.set(kk, g);
    // Legs on one strike in different expiries share a tag: it wears the closest one's colour.
    if (g.sd && !g.w && l.tone && (!g.tone || TONE_RANK[l.tone] > TONE_RANK[g.tone])) g.tone = l.tone;
  }
  const GS = [...gp.values()];
  // 162a: SD on this week's move, in the money, the colour, the name.
  const zOf = (K: number) => (m0 > 0 ? Math.abs(Math.log(K / S0)) / m0 : null);
  const itmOf = (g: G) => (g.ty === 'C' ? S0 > g.K : S0 < g.K);
  const zTone = (g: G): PCTone => { const z = zOf(g.K) ?? Infinity; return itmOf(g) || z < 0.5 ? 'red' : z < 1 ? 'orange' : 'quiet'; };
  const nameOf = (g: G) => (g.w ? `What if ${pcFk(g.K)}` : `${g.sd ? 'Sold' : 'Hedge'} ${g.ty === 'C' ? 'call' : 'put'} ${pcFk(g.K)}`);
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
    if (x.px) return { key: 'px', top: x.cy - TH / 2, n: S0.toFixed(2), s: '', px: true, sold: true, put: false, w: false, out: false, title: `Today ${S0.toFixed(2)}`, tone: null,
      k: S0.toFixed(2), ty: null, z: null, sd: null, zTone: null, itm: false };
    const g = x.g!, z = zOf(g.K), it = g.sd && !g.w && itmOf(g), arw = x.out ? (x.up ? ' ↑' : ' ↓') : '';
    return { key: x.key, top: x.cy - TH / 2, n: `${pcFk(g.K)} ${g.ty}`, s: dpc(g.K, S0) + arw, px: false, sold: g.sd, put: g.ty === 'P', w: g.w, out: x.out, tone: g.sd && !g.w ? g.tone : null,
      title: g.ls.join(', ') + (z != null ? `, ${it ? 'in the money' : `${z.toFixed(2)} SD ${g.K >= S0 ? 'above' : 'below'}`}` : '') + (x.out ? `, off the chart ${x.up ? 'above' : 'below'}` : ''),
      k: pcFk(g.K), ty: g.ty, z, sd: z == null ? null : (it ? 'ITM' : `${z.toFixed(2)} SD`) + arw, zTone: g.sd && !g.w && z != null ? zTone(g) : null, itm: itmOf(g) };
  });
  const conn = tg.filter((x) => !x.px && !x.out && Math.abs(x.cy - x.y) > 3).map((x) => ({ y0: x.y, y1: x.cy }));
  const lines: PCLine[] = GS.filter((g) => { const yy = y(g.K); return yy >= 0 && yy <= CH; })
    .map((g) => ({ key: g.kk, y: y(g.K), kind: (g.w ? 'w' : g.sd ? 'sold' : 'bought') as PCLine['kind'], ty: g.ty, name: nameOf(g), lt: -16, lo: true }));
  // 162a: each name sits above its line, else below, else it is left off; never over another name or out of the plot.
  {
    const bx: [number, number][] = [];
    const ok = (a: number, b: number) => a >= 0 && b <= CH && bx.every(([p, q]) => b <= p || a >= q);
    [...lines].sort((a, b) => a.y - b.y).forEach((L) => {
      if (ok(L.y - 16, L.y - 2)) { L.lt = -16; bx.push([L.y - 16, L.y - 2]); }
      else if (ok(L.y + 2, L.y + 16)) { L.lt = 2; bx.push([L.y + 2, L.y + 16]); }
      else L.lo = false;
    });
  }

  // 162a: the nearest sold call and put (in the money first, then SD), and the room between the nearest sold strikes.
  const nG = GS.filter((g) => g.sd && !g.w);
  const dist = (g: G) => zOf(g.K) ?? Math.abs(Math.log(g.K / S0));
  const rank = (a: G, b: G) => Number(itmOf(b)) - Number(itmOf(a)) || dist(a) - dist(b);
  const p1 = (ty: 'C' | 'P') => nG.filter((g) => g.ty === ty).sort(rank)[0];
  const nC1 = p1('C'), nP1 = p1('P');
  const reachOf = (g: G) => { if (!coneOk || itmOf(g)) return null; const z = zOf(g.K)!; return z < 1 ? FD * z * z : null; };
  const dayOf = (r: number) => WD[dow(FT[Math.min(FD, Math.max(1, Math.ceil(r - 1e-9))) - 1])];
  const friW = WD[dow(FD ? FT[FD - 1] : friday)];
  const near: PCNear[] = m0 > 0 ? [nC1, nP1].filter((g): g is G => !!g).sort(rank).map((g) => {
    const z = zOf(g.K)!, it = itmOf(g), r = reachOf(g);
    return { key: 'n' + g.kk, ty: g.ty, name: nameOf(g), K: g.K, itm: it, z, tone: zTone(g), reach: r, day: r == null ? null : dayOf(r), fri: friW,
      d: it ? `in the money by $${Math.abs(S0 - g.K).toFixed(2)}` : `${g.K >= S0 ? '↑' : '↓'}${dpc(g.K, S0)} · ${z.toFixed(2)} SD` };
  }) : [];
  const sc0 = nG.filter((g) => g.ty === 'C').sort((a, b) => a.K - b.K)[0], sp0 = nG.filter((g) => g.ty === 'P').sort((a, b) => b.K - a.K)[0];
  const thisWeek = opt.some((l) => l.q < 0 && !l.w && !!l.ex && l.ex <= fri);
  const cY = (v: number) => Math.max(0, Math.min(CH, v));
  let room: PCOut['room'] = null;
  if ((sc0 || sp0) && thisWeek) {
    const top = sc0 ? cY(y(sc0.K)) : 0, bottom = Math.max(top, sp0 ? cY(y(sp0.K)) : CH);
    room = { top, bottom, up: !!sc0 && top > 0, dn: !!sp0 && bottom < CH };
  }

  // 164: the cone, from today's dot to the Friday close, on the scale before it widened.
  let cone: PCCone | null = null;
  if (coneOk) {
    const NQ = 24, X: number[] = [], YU: number[] = [], YD: number[] = [], lim = (v: number) => Math.max(-4 * CH, Math.min(5 * CH, v));
    for (let n = 0; n <= NQ; n++) { const f = n / NQ, mj = m0 * Math.sqrt(f); X.push(end.x + (1 - end.x) * f); YU.push(lim(yb(S0 * Math.exp(mj)))); YD.push(lim(yb(S0 * Math.exp(-mj)))); }
    let fG: PCCone['fG'] = null, fU: PCCone['fU'] = null, fD: PCCone['fD'] = null;
    if (sc0 || sp0) {
      const tP = sc0 ? yb(sc0.K) : -1e6, bP = sp0 ? yb(sp0.K) : 1e6, gT = YU.map((v) => Math.max(v, tP));
      fG = [gT, YD.map((v, n) => Math.max(gT[n], Math.min(v, bP)))];
      if (sc0) fU = [YU, YU.map((v, n) => Math.max(v, Math.min(YD[n], tP)))];
      if (sp0) fD = [YD.map((v, n) => Math.min(v, Math.max(YU[n], bP))), YD];
    }
    const dots: PCCone['dots'] = [], drops: PCCone['drops'] = [];
    for (const g of nG) {
      const r = reachOf(g), yy = y(g.K);
      if (r == null || yy < 0 || yy > CH) continue;
      const x = end.x + (1 - end.x) * (r / FD);
      dots.push({ key: 'cd' + g.kk, x, y: yy, ty: g.ty });
      if (g === nC1 || g === nP1) drops.push({ key: 'dr' + g.kk, x, y: yy, ty: g.ty, day: dayOf(r) });
    }
    cone = { X, YU, YD, fG, fU, fD, lo: S0 * Math.exp(-m0), hi: S0 * Math.exp(m0), dots, drops };
  }

  // The labels under the chart. 1W reads Last week and This week (Nik, 17 Nov 2026).
  const xl0: { x: number; t: string; fut: boolean }[] = [];
  if (wk) {
    let bd = -1;
    for (let d = 0; d < nR; d++) if (dow(sl[d + 1][0]) < dow(sl[d][0])) bd = d;
    if (bd > 0) xl0.push({ x: 0, t: 'Last week', fut: false });
    xl0.push({ x: (Math.max(0, bd) * 7) / U, t: 'This week', fut: false });
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
  const xls: PCOut['xl'] = xl.map((x, i) => ({ key: 'x' + i, x: x.x, t: x.t, now: i === li }));
  // 164, 1W: the day the cone first reaches the nearest sold strike a side, under its drop line, in the strike's colour.
  if (wk && coneOn && cone) {
    const o: PCOut['xl'] = [];
    [...cone.drops].sort((a, b) => a.x - b.x).forEach((q) => {
      const pv = o[o.length - 1];
      if (pv && (pv.t === q.day || q.x - pv.x < gX)) return;
      o.push({ key: 'xd' + q.key, x: q.x, t: q.day, now: false, c: q.ty, b: true });
    });
    xls.push(...o);
  }

  const move = S0 / sl[0][1] - 1;
  return {
    pts, up: move >= 0, move, words: PC_WORDS[rg], dotX: end.x, dotY: y(S0), lines, tags, conn,
    xl: xls, CH, TH, friday, fridayWords: pcDayWords(friday), y,
    aria: `${PC_WORDS[rg].toLowerCase()}, today ${S0.toFixed(2)}. ` + GS.map((g) => `${g.ls.join(', ')}, ${dpc(g.K, S0)} ${g.K >= S0 ? 'above' : 'below'}`).join('; '),
    m0, FD, coneOk, coneOn, yb, tf, room, near, cone,
  };
}
