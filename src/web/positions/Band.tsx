// The band's left side (handoff 2026-11-13-positions §3.4, §3.5): Price | Payoff.
//   Price: the ticker chart's closes (useTicker, its ranges 1W 1M 3M YTD 1Y All) with today's price at the end, the
//          name's strikes on the line (sold solid, bought dotted) and What if trades dashed orange.
//   Payoff: P&L by price at a date from today's marks, summed from the server's grid (Pricer), ±12% of the price, the
//           priced move shaded, where the P&L peaks (Nik 7 Nov: never "short above", it reads as a loss), the Greeks
//           at that date, and a table of prices against dates.
import { useMemo } from 'react';
import { CountUp } from '../components/CountUp';
import { count, money, price } from '../lib/format';
import { RANGES, series, spread, type Range } from '../ticker/model';
import type { J } from '../lib/data';
import { fk, type DPt, type PLeg, type Pricer, type Seg } from './model';
import { G, K, MU, O, R, Segmented, cl, kicker, tnum } from './ui';

/* ── Price ─────────────────────────────────────────────────────────────── */
const RNG_WORDS: Record<Range, string> = { '1W': 'Past week', '1M': 'Past month', '3M': 'Past 3 months', YTD: 'This year', '1Y': 'Past year', All: 'All time' };
const H = 300;

export function PriceChart({ chart, failed, S0, today, legs, trades, rg, setRg }:
  { chart: J; failed?: boolean; S0: number; today: string; legs: PLeg[]; trades: PLeg[]; rg: Range; setRg: (r: Range) => void }) {
  const v = useMemo(() => {
    const closes: number[] = (chart?.closes ?? []).map(Number), dates: string[] = chart?.dates ?? [];
    if (closes.length < 2) return null;
    const s = series(closes, dates, rg, { m20: [], m50: [] });
    const pts = s.pts.slice(), ds = s.dates.slice();
    if (S0 > 0) { if (ds[ds.length - 1] === today) pts[pts.length - 1] = S0; else { pts.push(S0); ds.push(today); } }
    const stp = Math.max(1, Math.ceil(pts.length / 130)), p = pts.filter((_, i) => i % stp === 0 || i === pts.length - 1);
    const Ks = [...legs.map((l) => l.K), ...trades.map((l) => l.K)];
    let lo = Math.min(...p, ...Ks), hi = Math.max(...p, ...Ks);
    const pd = (hi - lo) * 0.07 || p[0] * 0.05; lo -= pd; hi += pd;
    const cy = (x: number) => ((hi - x) / (hi - lo)) * 100;
    const d = p.map((x, i) => `${i ? 'L' : 'M'}${((i / (p.length - 1)) * 400).toFixed(1)} ${cy(x).toFixed(2)}`).join(' ');
    const up = p[p.length - 1] >= p[0];
    // One line per strike and kind; the labels pushed apart so none overlap.
    const lines = [
      ...legs.map((l) => ({ k: l.k, y: cy(l.K), sold: l.q < 0, wi: false,
        l: `${fk(l.K)} ${l.ty === 'C' ? 'call' : 'put'} · ${l.exL} · ${l.q < 0 ? 'sold' : 'bought'} ${count(l.q)}` })),
      ...trades.map((l) => ({ k: l.k, y: cy(l.K), sold: l.q < 0, wi: true, l: `What if · ${l.lb}` })),
    ];
    const ly = spread(lines.map((x) => (x.y / 100) * H), 18, H - 4, 19);
    return { d, area: d + ' L400 100 L0 100 Z', up, chg: p[p.length - 1] / p[0] - 1, py: cy(S0), lines: lines.map((x, i) => ({ ...x, ly: ly[i] })) };
  }, [chart, S0, today, legs, trades, rg]);
  const c = v?.up ? G : R;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ position: 'relative', height: H }}>
        {v ? <>
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible' }}>
            <defs><linearGradient id="swpPr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={c} stopOpacity=".26" /><stop offset="1" stopColor={c} stopOpacity="0" /></linearGradient></defs>
            <path d={v.area} fill="url(#swpPr)" />
            <path d={v.d} style={{ fill: 'none', stroke: c, strokeWidth: 2, strokeLinejoin: 'round', vectorEffect: 'non-scaling-stroke' }} />
          </svg>
          {v.lines.map((x) => (
            <span key={x.k} aria-hidden="true" style={{ position: 'absolute', left: 0, right: 72, top: `${x.y.toFixed(2)}%`, pointerEvents: 'none',
              borderTop: x.wi ? `1.5px dashed ${O}` : x.sold ? '1px solid rgba(245,245,247,.55)' : '1.5px dotted rgba(245,245,247,.5)' }} />
          ))}
          {v.lines.map((x) => (
            <span key={'l' + x.k} style={{ position: 'absolute', top: x.ly - 18, ...(x.wi ? { right: 72 } : { left: 0 }), padding: '1px 6px', borderRadius: 6, background: 'rgba(6,8,7,.86)',
              fontSize: 12, lineHeight: '16px', fontWeight: x.wi ? 600 : 500, color: x.wi ? O : '#AEAEB2', whiteSpace: 'nowrap', pointerEvents: 'none' }}>{x.l}</span>
          ))}
          <span className="tnum" style={{ position: 'absolute', right: 0, top: `${v.py.toFixed(2)}%`, transform: 'translateY(-50%)', padding: '2px 8px', borderRadius: 999,
            background: K, color: '#000000', fontSize: 12, lineHeight: '16px', fontWeight: 700 }}>{price(S0)}</span>
        </> : <span style={{ position: 'absolute', top: '45%', left: 0, fontSize: 13, color: MU }}>{chart || failed ? 'No price history for this name yet.' : 'Loading the price…'}</span>}
      </div>
      <div style={{ display: 'flex', gap: 4 }} role="radiogroup" aria-label="Range">
        {RANGES.map((r) => (
          <button key={r} type="button" role="radio" aria-checked={r === rg} className="bare" onClick={() => setRg(r)}
            style={{ padding: '4px 10px', fontSize: 14, lineHeight: '20px', fontWeight: r === rg ? 700 : 500, color: r === rg ? K : MU, boxShadow: `inset 0 -2px 0 ${r === rg ? K : 'transparent'}` }}>{r}</button>
        ))}
      </div>
      <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>Your strikes on the line: sold solid, bought dotted. A trade you try in What if shows dashed orange.</span>
    </div>
  );
}
/** "Past 3 months ▼ 8.6%" beside the Price | Payoff switch. */
export function rangeWords(chart: J, S0: number, today: string, rg: Range): { l: string; v: string; c: string } | null {
  const closes: number[] = (chart?.closes ?? []).map(Number), dates: string[] = chart?.dates ?? [];
  if (closes.length < 2 || !(S0 > 0)) return null;
  const s = series(closes, dates, rg, { m20: [], m50: [] });
  const first = s.dates[0] === today && s.pts.length > 1 ? s.pts[0] : s.pts[0];
  const r = S0 / first - 1;
  return { l: RNG_WORDS[rg], v: `${r < 0 ? '▼' : '▲'} ${(Math.abs(r) * 100).toFixed(1)}%`, c: r < 0 ? R : G };
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
    return { fy, dW: pth(vW), dB: chg ? pth(vB) : '', zy: fy(0) };
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
          {chg && <span style={{ fontSize: 13, color: '#AEAEB2' }}>The book as it is: <span style={{ fontWeight: 600, color: cl(vb0) }}>{mask(money(vb0))}</span></span>}
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
          </div>
          <div className="tnum" style={{ position: 'relative', height: 18, borderTop: '1px solid rgba(255,255,255,.08)' }}>
            {[-12, -6, 0, 6, 12].map((p) => (
              <span key={p} style={{ position: 'absolute', top: 4, left: `${xp(S0 * (1 + p / 100)).toFixed(2)}%`, transform: `translateX(${p === -12 ? '0' : p === 12 ? '-100%' : '-50%'})`,
                fontSize: 12, lineHeight: '14px', color: MU, whiteSpace: 'nowrap' }}>{price(S0 * (1 + p / 100))}</span>
            ))}
          </div>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>
            {chg ? 'Solid: with your changes. Dashed: the book as it is.' : `Your ${t} book, P&L from today’s marks.`} Shaded: the priced move. The dot is today’s price.
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

