// ── Positions, one name at a time: what the grid needs besides the legs (handoff 6 Nov 2026, Pass 2) ──
// sunny-home adds these to each name in payload.brief_inputs, and sunny-positions hands them to the phone
// with the price-by-date grid:
//   walls  every chain's Ceiling, Floor, Accelerator and Flip from the tape's gamma views (gamma_view_day, the
//          latest session), for the chart's Walls layer and Walls by expiry;
//   tech   the 20-day average and the month's high and low, for the Technicals layer;
//   ended  on the weekend, the sold legs that ended on Friday and how each one ended (answer 3: they fold
//          under "Ended Nov 6 · settled"), from the trade log.
//
// No em dashes in any words written here (Nik).

import { fK } from '../_shared/book-engine.ts';

type Row = Record<string, any>;

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (d: string) => { const [, m, dd] = d.split('-').map(Number); return `${MON[m - 1]} ${dd}`; };
const fk = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));
/* Money made or lost in K and M (fK, README 11.5); a premium or strike a share stays to the cent. */
const usd2 = (v: number) => '$' + Math.abs(v).toFixed(2);

export interface Wall { k: number; gex: number }
export interface WallChain { ex: string; label: string; kind: 'Weekly' | 'Monthly'; days: number; trading: number;
  flip: number | null; c: Wall | null; f: Wall | null; a: Wall | null }
export interface Tech { sma20: number | null; hi: number | null; lo: number | null }
export interface EndedLeg { k: string; label: string; K: number; put: boolean; q: number; note: string; pl: number }

export interface PositionsCtx {
  today: string; moment: string;
  isTrading: (d: string) => boolean; addDays: (d: string, n: number) => string;
  gviews: Map<string, Row>;                         // ticker|view -> gamma view (latest session)
  daily: Record<string, { d: string[]; c: number[] }>;
  groups: Map<string, Row[]>;                       // ticker|type|direction|strike|expiry -> trades
}

/** A monthly is the third Friday (or the Thursday before it when the Friday is a holiday): day 15 to 21. */
const isMonthly = (d: string) => { const dd = Number(d.slice(8, 10)); return dd >= 15 && dd <= 21; };

export function wallsFor(t: string, x: PositionsCtx): WallChain[] {
  const out: WallChain[] = [];
  for (const [key, v] of x.gviews) {
    const [tk, view] = key.split('|');
    if (tk !== t || !/^\d{4}-\d{2}-\d{2}$/.test(view) || view < x.today) continue;
    const week: Row[] = Array.isArray(v?.week) ? v.week : [];
    const best = (label: string): Wall | null => {
      const w = week.filter((r) => r.label === label && Number.isFinite(Number(r.k))).sort((a, b) => Number(a.rank) - Number(b.rank))[0];
      return w ? { k: Number(w.k), gex: Math.round(Number(w.gex) || 0) } : null;
    };
    let trading = 0;
    for (let d = x.addDays(x.today, 1); d <= view; d = x.addDays(d, 1)) if (x.isTrading(d)) trading++;
    const days = Math.round((Date.parse(view + 'T12:00:00Z') - Date.parse(x.today + 'T12:00:00Z')) / 864e5);
    let a = best('accelerator');
    const f = best('floor');
    if (a && f && a.k === f.k) a = null;
    out.push({ ex: view, label: md(view), kind: isMonthly(view) ? 'Monthly' : 'Weekly', days, trading: Math.max(1, trading),
      flip: v?.flip != null && Number.isFinite(Number(v.flip)) ? +Number(v.flip).toFixed(2) : null, c: best('ceiling'), f, a });
  }
  return out.sort((p, q) => p.ex.localeCompare(q.ex)).slice(0, 8);
}

export function techFor(t: string, x: PositionsCtx): Tech {
  const c = x.daily[t]?.c ?? [];
  if (c.length < 20) return { sma20: null, hi: null, lo: null };
  const last20 = c.slice(-20), last22 = c.slice(-22);
  return { sma20: +(last20.reduce((a, b) => a + b, 0) / 20).toFixed(2), hi: +Math.max(...last22).toFixed(2), lo: +Math.min(...last22).toFixed(2) };
}

/** The Friday whose legs ended: the last trading day on or before today (the weekend moment only). */
export function endedDay(x: PositionsCtx): string | null {
  if (x.moment !== 'weekend') return null;
  let d = x.today;
  while (!x.isTrading(d)) d = x.addDays(d, -1);
  return d;
}

/** The sold legs that ended that day, each with how it ended, from the trade log (bought back, expired,
 *  assigned) and what it made or lost. */
export function endedFor(t: string, day: string | null, x: PositionsCtx): EndedLeg[] {
  if (!day) return [];
  const out: EndedLeg[] = [];
  for (const [key, rows] of x.groups) {
    const [tk, type, dir, strike, exp] = key.split('|');
    if (tk !== t || dir !== 'short' || exp !== day) continue;
    const opens = rows.filter((r) => r.action === 'open'), closes = rows.filter((r) => r.action === 'close');
    const n = opens.reduce((a, r) => a + Number(r.contracts), 0);
    if (!n) continue;
    const at = opens.reduce((a, r) => a + Number(r.contracts) * Number(r.premium), 0) / n;
    const life = (r: Row, code: string) => new RegExp(`\\b${code}\\b lifecycle`).test(String(r.note ?? ''));
    const bought = closes.filter((r) => !/lifecycle/.test(String(r.note ?? '')));
    const b = bought.reduce((a, r) => a + Number(r.contracts), 0);
    const bAt = b ? bought.reduce((a, r) => a + Number(r.contracts) * Number(r.premium), 0) / b : 0;
    const e = closes.filter((r) => life(r, 'Ep')).reduce((a, r) => a + Number(r.contracts), 0);
    const asg = closes.filter((r) => life(r, 'A') || life(r, 'Ex')).reduce((a, r) => a + Number(r.contracts), 0);
    const pl = Math.round(closes.reduce((a, r) => a + (Number(r.realized_pl) || 0), 0));
    const K = Number(strike), put = type === 'put';
    const parts: string[] = [`Sold ${n} at ${usd2(at)}.`];
    if (b) parts.push(b === n ? `Bought back all ${n} before the close, at ${usd2(bAt)} on average.` : `Bought back ${b} at ${usd2(bAt)} on average.`);
    if (e) parts.push(e === n ? 'All of them expired worthless.' : `${e} expired worthless.`);
    if (asg) parts.push(`${asg} assigned: ${(asg * 100).toLocaleString('en-US')} shares ${put ? 'bought' : 'sold'} at ${usd2(K)}.`);
    if (b + e + asg < n) parts.push(`${n - b - e - asg} still to settle.`);
    parts.push(pl >= 0 ? `Made ${fK(pl)}.` : `Lost ${fK(pl)}.`);
    out.push({ k: `ended-${type}-${fk(K)}-${exp}`, label: `${put ? 'Puts' : 'Calls'} ${fk(K)} ×${n}, ${md(exp)}`, K, put, q: n, note: parts.join(' '), pl });
  }
  return out.sort((p, q) => p.K - q.K);
}
