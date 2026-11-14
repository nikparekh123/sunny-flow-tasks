// The band's left side (handoff 2026-11-13-positions §3.4, §3.5): Price | Payoff.
//   Price: the ticker chart's closes (useTicker, its ranges 1W 1M 3M YTD 1Y All) with today's price at the end, the
//          name's strikes on the line (sold solid, bought dotted) and What if trades dashed orange.
//   Payoff: P&L by price at a date from today's marks, summed from the server's grid (Pricer), ±12% of the price, the
//           priced move shaded, where the P&L peaks (Nik 7 Nov: never "short above", it reads as a loss), the Greeks
//           at that date, and a table of prices against dates.
//   Both scrub (Nik 13 Nov 2026, "like before"): a pointer or finger on the chart shows a line, a dot on the curve and a
//   small read: Price the close's date, the close and the move since the range's first close; Payoff the price, how far
//   from today, and the P&L there (with your changes, and the book as it is).
import { useMemo, useState, type ReactNode } from 'react';
import { CountUp } from '../components/CountUp';
import { count, money, price } from '../lib/format';
import { ny } from '../lib/clock';
import { PC_RANGES, priceChart, type PCPoint, type PCRange, type PCStrike, type PCTone } from '../../../supabase/functions/_shared/price-chart.ts';
import type { SoldRow } from '../../../supabase/functions/_shared/positions-engine.ts';
import type { J } from '../lib/data';
import { fk, type DPt, type PLeg, type Pricer, type Seg } from './model';
import { G, K, MT, MU, O, R, Segmented, cl, kicker, tnum } from './ui';

/* ── Price ─────────────────────────────────────────────────────────────── */
// Handoff 2026-11-13-positions 2 §3.4 (Nik, 13 Nov 2026: "Just price chart"): the SunnyPositions week chart style. The
// maths is the shared model (supabase/functions/_shared/price-chart.ts, the phone ports it); this draws it: the line
// with no fill ending in a ring at today, the days to the Friday kept open after it, strike lines to a tag column on
// the right (112 px), the day, week or month labels, the ranges (opens on 1W), the note. The scrub stays (Nik).
/** Bright gray: the text on the tags that is not white (Nik 14 Nov: the gray % was hard to read). */
const LT = '#D1D1D6';
const TAGW = 112, MON3 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], WD3 = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** A sold leg's closeness from its Sold in SD row (same strike, side and expiry); none without a row. */
const toneOf = (l: PLeg, sold: SoldRow[]): PCTone | null =>
  l.q < 0 ? sold.find((r) => r.put === (l.ty === 'P') && Math.abs(r.K - l.K) < 1e-6 && r.ex === l.ex)?.tone ?? null : null;
const strikesOf = (legs: PLeg[], trades: PLeg[], sold: SoldRow[]): PCStrike[] => [
  ...legs.filter((l) => l.ty !== 'S').map((l) => ({ key: l.k, K: l.K, ty: l.ty as 'C' | 'P', q: l.q, w: false, tone: toneOf(l, sold),
    label: `${l.q < 0 ? 'Sold' : 'Bought'} ${l.ty === 'C' ? 'calls' : 'puts'} ${fk(l.K)} ×${count(Math.abs(l.q))} · ${l.exL}` })),
  ...trades.filter((l) => l.ty !== 'S').map((l) => ({ key: l.k, K: l.K, ty: l.ty as 'C' | 'P', q: l.q, w: true, label: `What if · ${l.lb}` })),
];
function model(chart: J, S0: number, closed: Set<string>, rg: PCRange, strikes: PCStrike[]) {
  const n = ny();
  return priceChart({ dates: chart?.dates ?? [], closes: (chart?.closes ?? []).map(Number), hours: chart?.hours ?? null, S0, today: n.date, mins: n.mins, closed, rg, strikes, phone: false });
}
/** What the scrub reads at a point: "Wed Nov 12 · 11 AM", "Fri Nov 7 close", "Now", or the day on the longer ranges. */
function whenWords(p: PCPoint, rg: PCRange): string {
  if (p.now) return 'Now';
  const [y, m, d] = p.d.split('-').map(Number), wd = WD3[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  if (p.h != null) return p.h === 9 || p.h === 16 ? `${wd} ${MON3[m - 1]} ${d} close` : `${wd} ${MON3[m - 1]} ${d} · ${p.h > 12 ? p.h - 12 : p.h} ${p.h >= 12 ? 'PM' : 'AM'}`;
  return rg === '1Y' || rg === 'All' ? `${MON3[m - 1]} ${d}, ${y}` : `${wd} ${MON3[m - 1]} ${d}`;
}

export function PriceChart({ chart, failed, S0, closed, legs, trades, sold, rg, setRg }:
  { chart: J; failed?: boolean; S0: number; closed: Set<string>; legs: PLeg[]; trades: PLeg[]; sold: SoldRow[]; rg: PCRange; setRg: (r: PCRange) => void }) {
  const v = useMemo(() => model(chart, S0, closed, rg, strikesOf(legs, trades, sold)), [chart, S0, closed, rg, legs, trades, sold]);
  const c = v ? (v.up ? G : R) : G;
  const d = v ? v.pts.map((p, i) => `${i ? 'L' : 'M'}${(p.x * 400).toFixed(2)} ${((v.y(p.v) / v.CH) * 100).toFixed(2)}`).join(' ') : '';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {v ? <>
        <div role="img" aria-label={`${chart?.t ?? ''} price, ${v.aria}`} style={{ position: 'relative', height: v.CH }}>
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, right: TAGW }}>
            <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible' }}>
              <path d={d} style={{ fill: 'none', stroke: c, strokeWidth: 2, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
            </svg>
            {v.lines.map((x) => (
              <span key={x.key} aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: x.y, pointerEvents: 'none',
                borderTop: x.kind === 'w' ? `1.5px dashed ${O}` : x.kind === 'sold' ? '1px dashed rgba(245,245,247,.42)' : '1.5px dotted rgba(245,245,247,.3)' }} />
            ))}
            <span aria-hidden="true" style={{ position: 'absolute', left: `${(v.dotX * 100).toFixed(3)}%`, top: v.dotY, width: 13, height: 13, margin: '-6.5px 0 0 -6.5px', boxSizing: 'border-box',
              borderRadius: '50%', border: `2.5px solid ${c}`, background: '#060807', boxShadow: '0 1px 4px rgba(0,0,0,.6)' }} />
            <Scrub top={0} bottom={0} read={(f) => {
              // The line follows the pointer (up to today's dot); the dot slides along the price line; the read is the
              // nearest point drawn.
              const x = Math.min(f, v.dotX), P = v.pts;
              let j = 0; while (j < P.length - 2 && P[j + 1].x < x) j++;
              const a = P[j], b = P[j + 1] ?? a, w = b.x > a.x ? Math.max(0, Math.min(1, (x - a.x) / (b.x - a.x))) : 0;
              const near = w < 0.5 ? a : b, mvp = P[0].v > 0 ? near.v / P[0].v - 1 : 0;
              return { x, y: v.y(a.v + (b.v - a.v) * w) / v.CH, dot: c, rows: [
                { t: whenWords(near, rg), c: MU },
                { t: price(near.v), b: true },
                { t: `${mvp < 0 ? '▼' : '▲'} ${(Math.abs(mvp) * 100).toFixed(1)}% since ${whenWords(P[0], rg).replace(/ close$/, '')}`, c: mvp < 0 ? R : G },
              ] };
            }} />
          </div>
          <div aria-hidden="true" style={{ position: 'absolute', top: 0, bottom: 0, right: 0, width: TAGW }}>
            <svg width="10" height={v.CH} style={{ position: 'absolute', left: 0, top: 0, overflow: 'visible' }}>
              {v.conn.map((x, i) => <path key={i} d={`M0 ${x.y0.toFixed(1)} L8 ${x.y1.toFixed(1)}`} style={{ fill: 'none', stroke: 'rgba(245,245,247,.4)', strokeWidth: 1 }} />)}
            </svg>
            {v.tags.map((x) => {
              // Nik, 14 Nov 2026 ("4 + 2"): bright text on a solid pill; a sold strike's % in its closeness colour.
              const loud = x.sold || x.w, pc = x.tone === 'red' ? R : x.tone === 'orange' ? O : loud ? LT : MT;
              return (
                <span key={x.key} title={x.title} className="tnum" style={{ position: 'absolute', left: 10, top: x.top, height: v.TH, boxSizing: 'border-box', display: 'flex', alignItems: 'center', gap: 5,
                  padding: x.px ? '0 8px' : x.put ? '0 7px' : 0, borderRadius: 999, whiteSpace: 'nowrap', pointerEvents: 'auto',
                  background: x.px ? K : x.put ? (loud ? '#242426' : '#18181A') : 'transparent' }}>
                  <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: x.px || loud ? 700 : 600, color: x.px ? '#000000' : x.w ? O : loud ? K : LT }}>{x.n}</span>
                  {!x.px && <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: loud ? 600 : 500, color: pc }}>{x.s}</span>}
                </span>
              );
            })}
          </div>
        </div>
        <div aria-hidden="true" style={{ position: 'relative', height: 18, marginRight: TAGW }}>
          {v.xl.map((x) => <span key={x.key} style={{ position: 'absolute', left: `${(x.x * 100).toFixed(2)}%`, top: 0, fontSize: 13, lineHeight: '18px', color: x.now ? K : MU, whiteSpace: 'nowrap' }}>{x.t}</span>)}
        </div>
      </> : <div style={{ position: 'relative', height: 280 }}><span style={{ position: 'absolute', top: '45%', left: 0, fontSize: 13, color: MU }}>{chart || failed ? 'No price history for this name yet.' : 'Loading the price…'}</span></div>}
      <div style={{ display: 'flex', gap: 4 }} role="radiogroup" aria-label="Range">
        {PC_RANGES.map((r) => (
          <button key={r} type="button" role="radio" aria-checked={r === rg} className="bare" onClick={() => setRg(r)}
            style={{ padding: '4px 10px', fontSize: 14, lineHeight: '20px', fontWeight: r === rg ? 700 : 500, color: r === rg ? K : MU, boxShadow: `inset 0 -2px 0 ${r === rg ? K : 'transparent'}` }}>{r}</button>
        ))}
      </div>
      <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>
        Strikes sit on the right with how far they are from today: sold dashed, bought dotted, puts in a gray tag. A sold strike’s % is red within 0.5 SD or in the money, orange within 1 SD, gray past 1 SD. After the dot, the days left to {v?.fridayWords ?? 'Friday'}. A trade you try in What if shows dashed orange.
      </span>
    </div>
  );
}
/** "Past week ▼ 1.7%" beside the Price | Payoff switch: the range's first point to the price now. */
export function rangeWords(chart: J, S0: number, closed: Set<string>, rg: PCRange): { l: string; v: string; c: string } | null {
  const v = model(chart, S0, closed, rg, []);
  if (!v) return null;
  return { l: v.words, v: `${v.move < 0 ? '▼' : '▲'} ${(Math.abs(v.move) * 100).toFixed(1)}%`, c: v.move < 0 ? R : G };
}

/* ── Payoff ────────────────────────────────────────────────────────────── */
const XR = 0.12, NP = 121, PH = 232;

export interface PayoffProps {
  t: string; pr: Pricer; base: PLeg[]; wi: PLeg[]; chg: boolean; segs: Seg[]; seg: Seg; dLong: (s: Seg) => string;
  pick: (s: Seg) => void; tab: 'chart' | 'table'; mask: (s: string) => string; iv: number;
}
export function Payoff({ t, pr, base, wi, chg, segs, seg, dLong, pick, tab, mask, iv }: PayoffProps) {
  const m = pr.m, S0 = m.S0, D: DPt = { tt: seg.tt, row: seg.row }, byT = seg.i === 0 && seg.tt < 0.01 ? 'today' : 'by ' + dLong(seg);
  const v = useMemo(() => {
    const xs = Array.from({ length: NP }, (_, i) => S0 * (1 - XR + (2 * XR * i) / (NP - 1)));
    const vW = xs.map((x) => pr.pl(wi, x, D)), vB = chg ? xs.map((x) => pr.pl(base, x, D)) : [];
    let ylo = Math.min(0, ...vW, ...vB), yhi = Math.max(0, ...vW, ...vB);
    const yp = (yhi - ylo) * 0.12 || 1; ylo -= yp; yhi += yp;
    const fy = (y: number) => ((yhi - y) / (yhi - ylo)) * 100;
    const pth = (a: number[]) => a.map((y, i) => `${i ? 'L' : 'M'}${((i / (NP - 1)) * 400).toFixed(1)} ${fy(y).toFixed(2)}`).join(' ');
    return { fy, dW: pth(vW), dB: chg ? pth(vB) : '', zy: fy(0), vW, vB };
  }, [pr, base, wi, chg, S0, D.tt, D.row]); // eslint-disable-line react-hooks/exhaustive-deps
  const xp = (x: number) => ((x / S0 - (1 - XR)) / (2 * XR)) * 100;
  const v0 = pr.pl(wi, S0, D), vb0 = pr.pl(base, S0, D);
  const sh = pr.shortAt(wi, D, !chg);
  const mv = iv > 0 ? iv * Math.sqrt(Math.max(seg.tt, 1) / 365) : 0;
  const bL = Math.max(0, xp(S0 * Math.exp(-mv))), bR = Math.min(100, xp(S0 * Math.exp(mv)));
  const gk = pr.greeks(wi, S0, D);
  const peakPast = sh != null && sh <= S0 * 1.0005, top = m.topPct;
  const gks = [
    { l: 'Delta', v: (gk.d < 0 ? 'Short ' : 'Long ') + count(gk.d), c: gk.d < 0 ? O : K },
    { l: 'Theta a day', v: mask(money(gk.th)), c: cl(gk.th) },
    { l: 'Gamma', v: count(gk.g) + ' a $1', c: gk.g < 0 ? R : K },
    { l: 'Vega', v: mask(money(gk.vg)), c: cl(gk.vg) },
  ];
  const zy = v.zy;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 16 }}>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <CountUp v={mask(money(v0))} style={{ fontSize: 30, lineHeight: '36px', fontWeight: 700, letterSpacing: '-.02em', color: cl(v0) }} />
          <span style={{ fontSize: 13, color: MU }}>If {t} is at {price(S0)} {byT}, from today’s marks</span>
          {chg && <span style={{ fontSize: 13, color: '#AEAEB2' }}>Without your changes: <span style={{ fontWeight: 600, color: cl(vb0) }}>{mask(money(vb0))}</span></span>}
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', textAlign: 'right', gap: 2 }}>
          <span style={{ fontSize: 15, fontWeight: 600, color: sh != null ? O : K }}>
            {sh == null ? `Keeps making more past ↑${top}% ${byT}` : peakPast ? `Already past its best ${byT}` : `Makes the most at ${price(sh)} ${byT}`}
          </span>
          <span style={{ fontSize: 13, color: MU }}>{sh == null ? `still rising at ↑${top}%` : peakPast ? `each $1 up costs you from ${price(S0)}` : `↑${((sh / S0 - 1) * 100).toFixed(1)}% from ${price(S0)}`}</span>
        </span>
      </div>
      {tab === 'chart' ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ position: 'relative', height: PH }} aria-label={`P&L chart, ${mask(money(v0))} at ${price(S0)} ${byT}`} role="img">
            {mv > 0 && (
              <span style={{ position: 'absolute', top: 0, bottom: 0, left: `${bL.toFixed(2)}%`, width: `${(bR - bL).toFixed(2)}%`, pointerEvents: 'none',
                background: 'linear-gradient(180deg,rgba(255,255,255,0),rgba(255,255,255,.06) 20%,rgba(255,255,255,.06) 80%,rgba(255,255,255,0))' }}>
                <span style={{ position: 'absolute', left: 8, top: 4, fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>
                  Priced move ±{(mv * 100).toFixed(1)}%{seg.i === 0 && seg.tt < 0.01 ? ' a day' : ` by ${seg.label}`}
                </span>
              </span>
            )}
            <div style={{ position: 'absolute', left: 0, right: 0, top: 10, bottom: 10, pointerEvents: 'none' }}>
              <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible', clipPath: `inset(0 0 ${(100 - zy).toFixed(2)}% 0)` }}>
                <defs><linearGradient id="swpPu" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={G} stopOpacity=".4" /><stop offset="1" stopColor={G} stopOpacity="0" /></linearGradient></defs>
                <path d={`${v.dW} L400 ${zy.toFixed(2)} L0 ${zy.toFixed(2)} Z`} fill="url(#swpPu)" />
                <path d={v.dW} style={{ fill: 'none', stroke: G, strokeWidth: 2.5, strokeLinejoin: 'round', vectorEffect: 'non-scaling-stroke' }} />
              </svg>
              <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible', clipPath: `inset(${zy.toFixed(2)}% 0 0 0)` }}>
                <defs><linearGradient id="swpPd" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stopColor={R} stopOpacity=".4" /><stop offset="1" stopColor={R} stopOpacity="0" /></linearGradient></defs>
                <path d={`${v.dW} L400 ${zy.toFixed(2)} L0 ${zy.toFixed(2)} Z`} fill="url(#swpPd)" />
                <path d={v.dW} style={{ fill: 'none', stroke: R, strokeWidth: 2.5, strokeLinejoin: 'round', vectorEffect: 'non-scaling-stroke' }} />
              </svg>
              <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible' }}>
                <line x1="0" y1={zy} x2="400" y2={zy} style={{ stroke: 'rgba(255,255,255,.3)', strokeWidth: 1, vectorEffect: 'non-scaling-stroke' }} />
                {chg && <path d={v.dB} style={{ fill: 'none', stroke: 'rgba(255,255,255,.55)', strokeWidth: 1.75, strokeDasharray: '6 5', vectorEffect: 'non-scaling-stroke' }} />}
              </svg>
              <span style={{ position: 'absolute', left: '50%', top: 0, bottom: 0, borderLeft: '1px solid rgba(255,255,255,.3)' }} />
              {sh != null && !peakPast && xp(sh) <= 100 && (
                <span style={{ position: 'absolute', left: `${xp(sh).toFixed(2)}%`, top: 0, bottom: 0, borderLeft: `1.5px dotted ${O}` }}>
                  <span style={{ position: 'absolute', left: 0, bottom: 4, transform: 'translateX(-50%)', padding: '2px 6px', borderRadius: 6, background: 'rgba(6,8,7,.9)',
                    fontSize: 12, lineHeight: '16px', fontWeight: 600, color: O, whiteSpace: 'nowrap' }}>Peaks at {price(sh)}</span>
                </span>
              )}
              <span style={{ position: 'absolute', left: '50%', top: `${v.fy(v0).toFixed(2)}%`, width: 14, height: 14, margin: '-7px 0 0 -7px', borderRadius: '50%',
                background: '#FFFFFF', boxShadow: '0 0 0 3px rgba(0,0,0,.6),0 0 14px rgba(255,255,255,.45)' }} />
            </div>
            <Scrub top={10} bottom={10} read={(f) => {
              const k = f * (NP - 1), i = Math.min(NP - 2, Math.floor(k)), w = k - i;
              const at = (a: number[]) => a[i] + (a[i + 1] - a[i]) * w;
              const x = S0 * (1 - XR + 2 * XR * f), vw = at(v.vW), mvp = x / S0 - 1;
              const rows: ScrubRow[] = [
                { t: `${price(x)} · ${Math.abs(mvp) < 0.0005 ? 'today' : `${mvp > 0 ? '↑' : '↓'}${(Math.abs(mvp) * 100).toFixed(1)}%`}`, c: MU },
                { t: (chg ? 'With changes · ' : '') + mask(money(vw)), c: cl(vw), b: true },
              ];
              if (chg) { const vb = at(v.vB); rows.push({ t: 'The book · ' + mask(money(vb)), c: cl(vb) }); }
              return { x: f, y: v.fy(vw) / 100, dot: cl(vw), rows };
            }} />
          </div>
          <div className="tnum" style={{ position: 'relative', height: 18, borderTop: '1px solid rgba(255,255,255,.08)' }}>
            {[-12, -6, 0, 6, 12].map((p) => (
              <span key={p} style={{ position: 'absolute', top: 4, left: `${xp(S0 * (1 + p / 100)).toFixed(2)}%`, transform: `translateX(${p === -12 ? '0' : p === 12 ? '-100%' : '-50%'})`,
                fontSize: 12, lineHeight: '14px', color: MU, whiteSpace: 'nowrap' }}>{price(S0 * (1 + p / 100))}</span>
            ))}
          </div>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>
            {chg ? 'Solid: with your changes. Dashed: without them (income only).' : `The ${t} legs switched on in Every leg (income to start), P&L from today’s marks.`} Shaded: the priced move. The dot is today’s price.
          </span>
        </div>
      ) : <PayTable t={t} pr={pr} set={wi} segs={segs} seg={seg} pick={pick} mask={mask} />}
      <Segmented label="Date" items={segs.map((s) => [s.i, s.label] as [number, string])} value={seg.i} onPick={(i) => pick(segs.find((s) => s.i === i)!)} size={13} width="100%" />
      <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', paddingTop: 10, borderTop: '1px solid rgba(255,255,255,.08)' }}>
        {gks.map((g) => (
          <span key={g.l} style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{g.l} · {seg.label}</span>
            <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600, color: g.c, whiteSpace: 'nowrap' }}>{g.v}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

const SP = [10, 7.5, 5, 2.5, 0, -2.5, -5, -7.5, -10];
/** P&L for prices ↑10% to ↓10% in 2.5% steps against today and each Friday; the selected date outlined. */
function PayTable({ t, pr, set, segs, seg, pick, mask }: { t: string; pr: Pricer; set: PLeg[]; segs: Seg[]; seg: Seg; pick: (s: Seg) => void; mask: (s: string) => string }) {
  const S0 = pr.m.S0;
  const cols = [segs[0], ...segs.filter((s, i) => i > 0 && s.friday)].slice(0, 7);
  const grid = SP.map((p) => cols.map((c) => pr.pl(set, S0 * (1 + p / 100), { tt: c.tt, row: c.row })));
  const gmx = Math.max(1, ...grid.map((r) => Math.max(...r.map(Math.abs))));
  const tpl = `128px repeat(${cols.length},minmax(0,1fr))`;
  return (
    <div className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <div style={{ display: 'grid', gridTemplateColumns: tpl, gap: 2, borderBottom: '1px solid rgba(255,255,255,.14)' }}>
        <span style={{ ...kicker, padding: '6px 0' }}>If {t} is at</span>
        {cols.map((c) => (
          <button key={c.i} type="button" className="bare" onClick={() => pick(c)} aria-pressed={c.i === seg.i}
            style={{ textAlign: 'center', padding: '6px 0', fontSize: 13, lineHeight: '18px', fontWeight: c.i === seg.i ? 700 : 500, color: c.i === seg.i ? K : '#AEAEB2',
              boxShadow: `inset 0 -2px 0 ${c.i === seg.i ? K : 'transparent'}` }}>{c.label}</button>
        ))}
      </div>
      {SP.map((p, ri) => (
        <div key={p} style={{ display: 'grid', gridTemplateColumns: tpl, gap: 2 }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 6, padding: '4px 0' }}>
            <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: p === 0 ? 700 : 500 }}>{price(S0 * (1 + p / 100))}</span>
            <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{p === 0 ? 'today' : `${p > 0 ? '↑' : '↓'}${Math.abs(p)}%`}</span>
          </span>
          {grid[ri].map((val, j) => {
            const a = Math.min(1, Math.abs(val) / gmx), z = Math.abs(val) < 0.5, on = cols[j].i === seg.i;
            return (
              <button key={j} type="button" className="bare swp-cell" onClick={() => pick(cols[j])}
                aria-label={`${price(S0 * (1 + p / 100))} by ${cols[j].label}, ${mask(money(val))}${val < 0 ? ' loss' : ''}`}
                style={{ textAlign: 'center', padding: '4px 0', borderRadius: 6, fontSize: 13, lineHeight: '18px', fontWeight: on ? 700 : 500,
                  color: z ? MU : val > 0 ? G : R, background: z ? 'transparent' : `${val > 0 ? 'rgba(101,196,102,' : 'rgba(255,105,97,'}${(0.05 + a * 0.18).toFixed(3)})`,
                  boxShadow: on ? 'inset 0 0 0 1.5px rgba(245,245,247,.8)' : 'none' }}>{z ? '$0' : mask(money(val))}</button>
            );
          })}
        </div>
      ))}
      <span style={{ paddingTop: 6, fontSize: 12, lineHeight: '16px', color: MU }}>P&amp;L from today’s marks, with your changes. Tap a column to pick the date.</span>
    </div>
  );
}


/* ── Scrub ─────────────────────────────────────────────────────────────── */
interface ScrubRow { t: string; c?: string; b?: boolean }
/** The pointer (or a finger) on a chart: a line down the plot, a dot on the curve and a small read beside it. `read`
    takes how far across (0 to 1) and gives where the dot sits (x, y as fractions of the plot) and the read's rows.
    The plot sits `top` and `bottom` px in from the box. Only this layer renders as the pointer moves. A vertical
    drag still scrolls the page on a phone. */
function Scrub({ top, bottom, read }: { top: number; bottom: number; read: (f: number) => { x: number; y: number; dot: string; rows: ScrubRow[] } }) {
  const [f, setF] = useState<number | null>(null);
  const at = (e: React.PointerEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    if (r.width) setF(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)));
  };
  const q = f == null ? null : read(f);
  let tip: ReactNode = null;
  if (q) {
    const right = q.x > 0.6;
    tip = (
      <span style={{ position: 'absolute', top: 0, left: `${(q.x * 100).toFixed(3)}%`, transform: right ? 'translateX(calc(-100% - 10px))' : 'translateX(10px)',
        display: 'flex', flexDirection: 'column', gap: 1, padding: '6px 9px', borderRadius: 10, background: 'rgba(16,18,17,.94)', boxShadow: '0 0 0 1px rgba(255,255,255,.12)',
        whiteSpace: 'nowrap', pointerEvents: 'none', ...tnum }}>
        {q.rows.map((x, i) => <span key={i} style={{ fontSize: x.b ? 15 : 12, lineHeight: x.b ? '20px' : '16px', fontWeight: x.b ? 700 : 500, color: x.c ?? K }}>{x.t}</span>)}
      </span>
    );
  }
  return (
    <div onPointerMove={at} onPointerDown={at} onPointerLeave={() => setF(null)} onPointerCancel={() => setF(null)}
      onPointerUp={(e) => { if (e.pointerType === 'touch') setF(null); }} aria-hidden="true"
      style={{ position: 'absolute', left: 0, right: 0, top, bottom, cursor: 'crosshair', touchAction: 'pan-y', userSelect: 'none' }}>
      {q && <>
        <span style={{ position: 'absolute', top: 0, bottom: 0, left: `${(q.x * 100).toFixed(3)}%`, borderLeft: '1px solid rgba(245,245,247,.55)', pointerEvents: 'none' }} />
        <span style={{ position: 'absolute', left: `${(q.x * 100).toFixed(3)}%`, top: `${(q.y * 100).toFixed(3)}%`, width: 11, height: 11, margin: '-5.5px 0 0 -5.5px',
          borderRadius: '50%', background: q.dot, boxShadow: '0 0 0 2px #0B0D0C', pointerEvents: 'none' }} />
        {tip}
      </>}
    </div>
  );
}
