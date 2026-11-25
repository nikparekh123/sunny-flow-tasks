// The band's left side (handoff 2026-11-13-positions §3.4, §3.5; handoff 2026-11-18 §3, CHANGES Nov 16 and 17):
// Price | Payoff.
//   Price (round 162a, Nov 16): the ticker chart's closes (useTicker, its ranges 1W 1M 3M YTD 1Y All) with today's
//          price at the end, calls blue and puts brown, sold dashed and hedges dotted, each line named at its right end,
//          the tag column with each strike's SD on this week's move, the nearest sold call and put in a card under the
//          chart, the room between the nearest sold strikes shaded. The 1 SD switch (round 164, Nov 17) adds the cone.
//   Payoff (round 168a, Nov 17): P&L by price at a date from today's marks, summed from the server's grid (Pricer; a
//          date the grid has no row for is priced with the engine), on a date slider (each trading day from today to
//          the day the nearest sold legs expire) and a range slider (±5% to ±50%), with a hover read, a target and
//          the Greeks at that date. The table follows the slider. The hover reads the Greeks at the cursor (24 Nov 2026,
//          r150x hv8): the top label adds the delta there and the Greeks row follows the hovered price, back on leave.
//   The maths is supabase/functions/_shared/price-chart.ts (the Price chart, shared with the phone) and model.ts.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { CountUp } from '../components/CountUp';
import { count, money, price } from '../lib/format';
import { ny } from '../lib/clock';
import { PC_RANGES, priceChart, type PCPoint, type PCRange, type PCStrike, type PCTone } from '../../../supabase/functions/_shared/price-chart.ts';
import type { SoldRow } from '../../../supabase/functions/_shared/positions-engine.ts';
import type { J } from '../lib/data';
import { fk, type DPt, type PLeg, type PosModel, type Pricer } from './model';
import { G, K, MT, MU, O, QU, R, cl, kicker, tnum, useReducedMotion } from './ui';

/* ── Price ─────────────────────────────────────────────────────────────── */
/** Bright gray: the text on the tags that is not white (Nik 14 Nov: the gray % was hard to read). */
const LT = '#D1D1D6';
const TAGW = 112, MON3 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], WD3 = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** Calls blue, puts brown (Nov 16). */
const TC = (ty: 'C' | 'P', a: number) => (ty === 'C' ? `rgba(134,168,240,${a})` : `rgba(200,148,106,${a})`);
const TONE_C: Record<PCTone, string> = { red: R, orange: O, quiet: MU };
const EZ = ' .55s cubic-bezier(.22,1,.36,1)';
/** A sold leg's closeness from its Sold in SD row (same strike, side and expiry); none without a row. Used only when the
    name has no IV, so no SD on this week's move. */
const toneOf = (l: PLeg, sold: SoldRow[]): PCTone | null =>
  l.q < 0 ? sold.find((r) => r.put === (l.ty === 'P') && Math.abs(r.K - l.K) < 1e-6 && r.ex === l.ex)?.tone ?? null : null;
const strikesOf = (legs: PLeg[], trades: PLeg[], sold: SoldRow[]): PCStrike[] => [
  ...legs.filter((l) => l.ty !== 'S').map((l) => ({ key: l.k, K: l.K, ty: l.ty as 'C' | 'P', q: l.q, w: false, tone: toneOf(l, sold), ex: l.ex,
    label: `${l.q < 0 ? 'Sold' : 'Hedge'} ${l.ty === 'C' ? 'calls' : 'puts'} ${fk(l.K)} ×${count(Math.abs(l.q))} · ${l.exL}` })),
  ...trades.filter((l) => l.ty !== 'S').map((l) => ({ key: l.k, K: l.K, ty: l.ty as 'C' | 'P', q: l.q, w: true, ex: l.ex, label: `What if · ${l.lb}` })),
];
function model(chart: J, S0: number, closed: Set<string>, rg: PCRange, strikes: PCStrike[], iv = 0, cone = false) {
  const n = ny();
  return priceChart({ dates: chart?.dates ?? [], closes: (chart?.closes ?? []).map(Number), hours: chart?.hours ?? null, S0, today: n.date, mins: n.mins, closed, rg, strikes, phone: false, iv, cone });
}
/** What the scrub reads at a point: "Wed Nov 12 · 11 AM", "Fri Nov 7 close", "Now", or the day on the longer ranges. */
function whenWords(p: PCPoint, rg: PCRange): string {
  if (p.now) return 'Now';
  const [y, m, d] = p.d.split('-').map(Number), wd = WD3[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  if (p.h != null) return p.h === 9 || p.h === 16 ? `${wd} ${MON3[m - 1]} ${d} close` : `${wd} ${MON3[m - 1]} ${d} · ${p.h > 12 ? p.h - 12 : p.h} ${p.h >= 12 ? 'PM' : 'AM'}`;
  return rg === '1Y' || rg === 'All' ? `${MON3[m - 1]} ${d}, ${y}` : `${wd} ${MON3[m - 1]} ${d}`;
}

/** The 1 SD switch's pick, remembered across visits (localStorage sunny.cone164; off when storage is shut). */
const CONE_KEY = 'sunny.cone164';
export function useCone(): [boolean, () => void] {
  const [on, setOn] = useState(() => { try { return localStorage.getItem(CONE_KEY) === '1'; } catch { return false; } });
  const toggle = () => {
    const v = !on;
    try { localStorage.setItem(CONE_KEY, v ? '1' : '0'); } catch { /* private window: this visit only */ }
    setOn(v);
  };
  return [on, toggle];
}
/** The glass "1 SD" capsule in the chart header (round 164): white when on. */
export function ConeSwitch({ on, toggle }: { on: boolean; toggle: () => void }) {
  const rm = useReducedMotion();
  return (
    <button type="button" role="switch" aria-checked={on} className="bare" onClick={toggle} aria-label="1 SD cone, when the price could reach your strikes" title="1 SD cone: when the price could reach your strikes"
      style={{ display: 'flex', alignItems: 'center', gap: 6, height: 30, padding: '0 12px', borderRadius: 999, fontSize: 13, lineHeight: '18px', fontWeight: on ? 600 : 500, whiteSpace: 'nowrap',
        color: on ? '#000000' : K, background: on ? K : 'linear-gradient(160deg,rgba(255,255,255,.20) 0%,rgba(255,255,255,.09) 50%,rgba(255,255,255,.15) 100%)',
        boxShadow: on ? '0 2px 8px rgba(0,0,0,.35)' : 'inset 0 0 0 .5px rgba(255,255,255,.32),inset 1px 1px 0 -.5px rgba(255,255,255,.45),0 2px 8px rgba(0,0,0,.35)',
        transition: rm ? 'none' : 'background .3s ease, color .3s ease' }}>
      <svg width="14" height="12" viewBox="0 0 14 12" aria-hidden="true" style={{ flex: 'none' }}>
        <path d="M1.5 6 L12.5 1.5 M1.5 6 L12.5 10.5" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round' }} />
      </svg>1 SD
    </button>
  );
}

/** The plot's width in px (for keeping a line's name clear of a cone dot). */
function useWidth<T extends HTMLElement>(on: boolean): [React.RefObject<T>, number] {
  const ref = useRef<T>(null);
  const [w, setW] = useState(600);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    setW(el.clientWidth);
    const ro = new ResizeObserver(() => setW(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, [on]);
  return [ref, w];
}

export function PriceChart({ chart, failed, S0, closed, legs, trades, sold, rg, setRg, iv, cone }:
  { chart: J; failed?: boolean; S0: number; closed: Set<string>; legs: PLeg[]; trades: PLeg[]; sold: SoldRow[]; rg: PCRange; setRg: (r: PCRange) => void; iv: number; cone: boolean }) {
  const rm = useReducedMotion();
  const v = useMemo(() => model(chart, S0, closed, rg, strikesOf(legs, trades, sold), iv, cone), [chart, S0, closed, rg, legs, trades, sold, iv, cone]);
  const [plot, pw] = useWidth<HTMLDivElement>(!!v);
  const c = v ? (v.up ? G : R) : G;
  const CH = v?.CH ?? 280, yb = v?.yb ?? v?.y ?? ((x: number) => x), tf = v?.tf ?? { ty: 0, sy: 1 }, on = !!v?.coneOn, cn = v?.cone ?? null;
  const pc = (y: number) => ((y / CH) * 100).toFixed(2);
  const d = v ? v.pts.map((p, i) => `${i ? 'L' : 'M'}${(p.x * 400).toFixed(2)} ${pc(yb(p.v))}`).join(' ') : '';
  // The line and the cone ride one transform from the scale before the cone widened it (round 164, .55 s).
  const ride: CSSProperties = { transform: `translateY(${((tf.ty / CH) * 100).toFixed(3)}px) scaleY(${tf.sy.toFixed(4)})`, transformOrigin: '0 0', transformBox: 'view-box', transition: rm ? 'none' : `transform${EZ}` };
  const glide = rm ? 'none' : `top${EZ}, height${EZ}, opacity .3s ease`;
  const P = (ys: number[]) => (cn ? cn.X.map((x, n) => `${n ? 'L' : 'M'}${(x * 400).toFixed(1)} ${pc(ys[n])}`).join(' ') : '');
  const poly = (f: [number[], number[]] | null) => (cn && f ? `${P(f[0])} ${cn.X.map((x, n) => `L${(x * 400).toFixed(1)} ${pc(f[1][n])}`).reverse().join(' ')} Z` : '');
  // A line's name never sits over its cone dot: it ends 8 px left of the dot when the dot is under it.
  const nameRight = (key: string, name: string) => {
    const q = on ? cn?.dots.find((x) => x.key === 'cd' + key) : null;
    if (!q) return '3px';
    const dr = (1 - q.x) * pw, lw = name.length * 6.6 + 6;
    return dr - 7 < 3 + lw ? `calc(${((1 - q.x) * 100).toFixed(2)}% + 8px)` : '3px';
  };
  const hasSold = legs.some((l) => l.q < 0 && l.ty !== 'S');
  const note = !v ? '' : on && cn
    ? `1 SD cone: a normal week, ${price(cn.lo)} to ${price(cn.hi)} by ${v.fridayWords}; about 2 weeks in 3 end inside.${hasSold ? ' Green: inside your sold strikes; red: where it spills past them. The dot marks the day it first reaches one.' : ''} Calls blue, puts brown; sold dashed, hedges dotted.`
    : `Calls blue, puts brown; sold dashed, hedges dotted. ${v.m0 ? 'Each tag gives the strike’s SD on this week’s move: red under 0.5 SD or in the money, orange to 1 SD, gray past 1 SD.' : 'Each tag gives how far the strike is from today.'}${v.room ? ' Green is the room between your nearest sold put and call, faint red past them.' : ''} After the dot, the days left to ${v.fridayWords}. A trade you try in What if shows dashed orange.`;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {v ? <>
        <div role="img" aria-label={`${chart?.t ?? ''} price, ${v.aria}`} style={{ position: 'relative', height: CH }}>
          <div ref={plot} style={{ position: 'absolute', left: 0, top: 0, bottom: 0, right: TAGW }}>
            {v.room && <>
              <span aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: v.room.top, height: Math.max(0, v.room.bottom - v.room.top), background: 'rgba(101,196,102,.10)', opacity: on ? 0 : 1, transition: glide, pointerEvents: 'none' }} />
              {v.room.up && <span aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: 0, height: v.room.top, background: 'rgba(255,105,97,.08)', opacity: on ? 0 : 1, transition: glide, pointerEvents: 'none' }} />}
              {v.room.dn && <span aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: v.room.bottom, height: CH - v.room.bottom, background: 'rgba(255,105,97,.08)', opacity: on ? 0 : 1, transition: glide, pointerEvents: 'none' }} />}
            </>}
            {cn && (
              <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'hidden', pointerEvents: 'none',
                opacity: on ? 1 : 0, transition: rm ? 'none' : on ? 'opacity .4s ease .15s' : 'opacity .2s ease' }}>
                <g style={ride}>
                  {cn.fG && <path d={poly(cn.fG)} style={{ fill: 'rgba(101,196,102,.24)', stroke: 'none' }} />}
                  {cn.fU && <path d={poly(cn.fU)} style={{ fill: 'rgba(255,105,97,.45)', stroke: 'none' }} />}
                  {cn.fD && <path d={poly(cn.fD)} style={{ fill: 'rgba(255,105,97,.45)', stroke: 'none' }} />}
                  <path d={P(cn.YU)} style={{ fill: 'none', stroke: 'rgba(245,245,247,.8)', strokeWidth: 1, vectorEffect: 'non-scaling-stroke' }} />
                  <path d={P(cn.YD)} style={{ fill: 'none', stroke: 'rgba(245,245,247,.8)', strokeWidth: 1, vectorEffect: 'non-scaling-stroke' }} />
                </g>
              </svg>
            )}
            <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible',
              opacity: on ? 0.35 : 1, transition: rm ? 'none' : 'opacity .35s ease' }}>
              <g style={ride}><path d={d} style={{ fill: 'none', stroke: c, strokeWidth: 2, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} /></g>
            </svg>
            {cn?.drops.map((q) => (
              <span key={q.key} aria-hidden="true" style={{ position: 'absolute', left: `${(q.x * 100).toFixed(2)}%`, top: q.y, bottom: 0, borderLeft: `1px dotted ${TC(q.ty, 0.8)}`,
                opacity: on ? 1 : 0, transition: glide, pointerEvents: 'none' }} />
            ))}
            {cn?.dots.map((q) => (
              <span key={q.key} aria-hidden="true" style={{ position: 'absolute', left: `${(q.x * 100).toFixed(2)}%`, top: q.y, width: 9, height: 9, margin: '-4.5px 0 0 -4.5px', borderRadius: '50%',
                background: TC(q.ty, 1), boxShadow: '0 0 0 2px #060807', opacity: on ? 1 : 0, transition: glide, pointerEvents: 'none' }} />
            ))}
            {v.lines.map((x) => {
              const ty = x.ty ?? 'C', name = x.name ?? '';
              const bd = x.kind === 'w' ? `1.5px dashed ${O}` : x.kind === 'sold' ? `1.5px dashed ${TC(ty, 0.9)}` : `1px dotted ${TC(ty, 0.55)}`;
              return (
                <span key={x.key} aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: x.y, borderTop: bd, transition: glide, pointerEvents: 'none' }}>
                  {name && (
                    <span style={{ position: 'absolute', right: nameRight(x.key, name), top: x.lt ?? -16, zIndex: 1, padding: '0 3px', borderRadius: 3, background: on ? '#060807' : 'transparent',
                      fontSize: 12, lineHeight: '14px', fontWeight: 600, color: x.kind === 'w' ? O : TC(ty, x.kind === 'sold' ? 1 : 0.85), opacity: x.lo === false ? 0 : 1, whiteSpace: 'nowrap' }}>{name}</span>
                  )}
                </span>
              );
            })}
            <span aria-hidden="true" style={{ position: 'absolute', left: `${(v.dotX * 100).toFixed(3)}%`, top: v.dotY, width: 13, height: 13, margin: '-6.5px 0 0 -6.5px', boxSizing: 'border-box',
              borderRadius: '50%', border: `2.5px solid ${c}`, background: '#060807', boxShadow: '0 1px 4px rgba(0,0,0,.6)', transition: glide }} />
            <Scrub top={0} bottom={0} read={(f) => {
              // The line follows the pointer (up to today's dot); the dot slides along the price line; the read is the
              // nearest point drawn.
              const x = Math.min(f, v.dotX), Q = v.pts;
              let j = 0; while (j < Q.length - 2 && Q[j + 1].x < x) j++;
              const a = Q[j], b = Q[j + 1] ?? a, w = b.x > a.x ? Math.max(0, Math.min(1, (x - a.x) / (b.x - a.x))) : 0;
              const near = w < 0.5 ? a : b, mvp = Q[0].v > 0 ? near.v / Q[0].v - 1 : 0;
              return { x, y: v.y(a.v + (b.v - a.v) * w) / CH, dot: c, rows: [
                { t: whenWords(near, rg), c: MU },
                { t: price(near.v), b: true },
                { t: `${mvp < 0 ? '▼' : '▲'} ${(Math.abs(mvp) * 100).toFixed(1)}% since ${whenWords(Q[0], rg).replace(/ close$/, '')}`, c: mvp < 0 ? R : G },
              ] };
            }} />
          </div>
          <div aria-hidden="true" style={{ position: 'absolute', top: 0, bottom: 0, right: 0, width: TAGW }}>
            <svg width="10" height={CH} style={{ position: 'absolute', left: 0, top: 0, overflow: 'visible' }}>
              {v.conn.map((x, i) => <path key={i} d={`M0 ${x.y0.toFixed(1)} L8 ${x.y1.toFixed(1)}`} style={{ fill: 'none', stroke: 'rgba(245,245,247,.4)', strokeWidth: 1 }} />)}
            </svg>
            {v.tags.map((x) => {
              if (x.px) return (
                <span key={x.key} title={x.title} className="tnum" style={{ position: 'absolute', left: 10, top: x.top, height: v.TH, boxSizing: 'border-box', display: 'flex', alignItems: 'center',
                  padding: '0 8px', borderRadius: 999, whiteSpace: 'nowrap', pointerEvents: 'auto', background: K, transition: glide }}>
                  <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 700, color: '#000000' }}>{x.n}</span>
                </span>
              );
              // Round 162a: the strike in its type's colour, then its SD on this week's move (red under 0.5 SD or in the
              // money, orange to 1, gray past); without an IV, how far it is from today in its Sold in SD colour.
              const loud = x.sold || x.w, ty = x.ty ?? (x.put ? 'P' : 'C'), hasSd = x.sd != null;
              const sc = hasSd ? (loud && !x.w && x.zTone ? TONE_C[x.zTone] : QU) : x.tone === 'red' ? R : x.tone === 'orange' ? O : loud ? LT : MT;
              return (
                <span key={x.key} title={x.title} className="tnum" style={{ position: 'absolute', left: 10, top: x.top, height: v.TH, boxSizing: 'border-box', display: 'flex', alignItems: 'center', gap: 5,
                  whiteSpace: 'nowrap', pointerEvents: 'auto', transition: glide }}>
                  <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: loud ? 700 : 500, color: x.w ? O : TC(ty, loud ? 1 : 0.85) }}>{x.k ?? x.n}</span>
                  <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: sc }}>{hasSd ? x.sd : x.s}</span>
                </span>
              );
            })}
          </div>
        </div>
        <div aria-hidden="true" style={{ position: 'relative', height: 18, marginRight: TAGW }}>
          {v.xl.map((x) => (
            <span key={x.key} style={{ position: 'absolute', left: `${(x.x * 100).toFixed(2)}%`, top: 0, transform: x.b ? 'translateX(-50%)' : 'none', fontSize: 13, lineHeight: '18px',
              fontWeight: x.b ? 700 : 400, color: x.b && x.c ? TC(x.c, 1) : x.now ? K : MU, whiteSpace: 'nowrap' }}>{x.t}</span>
          ))}
        </div>
      </> : <div style={{ position: 'relative', height: 280 }}><span style={{ position: 'absolute', top: '45%', left: 0, fontSize: 13, color: MU }}>{chart || failed ? 'No price history for this name yet.' : 'Loading the price…'}</span></div>}
      <div style={{ display: 'flex', gap: 4 }} role="radiogroup" aria-label="Range">
        {PC_RANGES.map((r) => (
          <button key={r} type="button" role="radio" aria-checked={r === rg} className="bare" onClick={() => setRg(r)}
            style={{ padding: '4px 10px', fontSize: 14, lineHeight: '20px', fontWeight: r === rg ? 700 : 500, color: r === rg ? K : MU, boxShadow: `inset 0 -2px 0 ${r === rg ? K : 'transparent'}` }}>{r}</button>
        ))}
      </div>
      {v?.near && v.near.length > 0 && (
        <div role="list" aria-label="Your sold strikes, nearest first" style={{ display: 'flex', flexWrap: 'wrap', gap: '10px 28px', padding: '12px 16px', borderRadius: 16,
          background: 'rgba(255,255,255,.05)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08)', ...tnum }}>
          {v.near.map((n) => (
            <div key={n.key} role="listitem" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <span aria-hidden="true" style={{ width: 18, height: 0, borderTop: `2px dashed ${TC(n.ty, 1)}` }} />
              <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: TC(n.ty, 1) }}>{n.name}</span>
              <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: 600, color: TONE_C[n.tone], whiteSpace: 'nowrap' }}>{n.d}</span>
              {on && !n.itm && <span style={{ fontSize: 13, lineHeight: '20px', color: MU, whiteSpace: 'nowrap' }}>· {n.reach != null ? `the cone reaches it ${n.day}` : `outside the cone to ${n.fri}`}</span>}
            </div>
          ))}
        </div>
      )}
      <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{note || 'A trade you try in What if shows dashed orange.'}</span>
    </div>
  );
}
/** "Past week ▼ 1.7%" beside the Price | Payoff switch: the range's first point to the price now; `coneOk`: the 1 SD
    switch can show (1W and 1M, with an IV and a day left to the Friday). */
export function rangeWords(chart: J, S0: number, closed: Set<string>, rg: PCRange, iv = 0): { l: string; v: string; c: string; coneOk: boolean } | null {
  const v = model(chart, S0, closed, rg, [], iv);
  if (!v) return null;
  return { l: v.words, v: `${v.move < 0 ? '▼' : '▲'} ${(Math.abs(v.move) * 100).toFixed(1)}%`, c: v.move < 0 ? R : G, coneOk: !!v.coneOk };
}

/* ── Payoff (round 168a) ───────────────────────────────────────────────── */
const NP = 121, PH = 232;
/** The range the chart opens on, and the slider's ends (±5% to ±50%). */
export const XR0 = 12;
const XMIN = 5, XMAX = 50;
const isoAdd = (iso: string, n: number) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const dowOf = (iso: string) => new Date(iso + 'T12:00:00Z').getUTCDay();
const daysBetween = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);
/** "Fri Nov 20" and "Nov 20". */
const fullDay = (iso: string) => { const d = new Date(iso + 'T12:00:00Z'); return `${WD3[d.getUTCDay()]} ${MON3[d.getUTCMonth()]} ${d.getUTCDate()}`; };
const mdDay = (iso: string) => { const d = new Date(iso + 'T12:00:00Z'); return `${MON3[d.getUTCMonth()]} ${d.getUTCDate()}`; };
const dayWords = (n: number) => (n === 1 ? '1 day' : `${n} days`);
/** "↑7.7%", "today" within 0.05%. */
const fromToday = (x: number, S0: number) => { const ch = x / S0 - 1, a = Math.abs(ch) * 100; return Math.abs(ch) < 0.0005 ? 'today' : `${ch > 0 ? '↑' : '↓'}${a < 0.1 ? a.toFixed(2) : a.toFixed(1)}%`; };

/** One stop on the date slider: the day, how it is priced (the grid's row for it, else the engine), calendar days from
    today, and the legs that expire at its close. Index 0 is now. */
export interface PayDay { iso: string; D: DPt; cd: number; fri: boolean; ends: PLeg[] }
/** The slider's days: now, then each trading day (weekends and the calendar's closed days skipped) to the day the
    LAST sold legs expire (Nik, 20 Nov 2026, option 1: the full picture past the first expiry; it had stopped at the
    nearest, round 168), or to the first expiry of any leg when nothing is sold; at most a year out. Past an expiry
    the legs that ended there are worth what they were at that close and the rest keep their time value: the "do
    nothing" path. `exp` is the end (null: no option on); `near` the nearest sold expiry (where the slider opens when
    this Friday is not on it). */
export function payDays(m: PosModel, wi: PLeg[], closed: Set<string>): { pts: PayDay[]; exp: string | null; near: string | null } {
  const d0 = m.isoAt(0);
  const opts = wi.filter((l) => l.ty !== 'S' && !!l.ex && l.ex >= d0);
  const ex = (a: PLeg[]) => a.map((l) => l.ex).sort();
  const sold = opts.filter((l) => l.q < 0);
  const exp = ex(sold).at(-1) ?? ex(opts)[0] ?? null, near = ex(sold)[0] ?? ex(opts)[0] ?? null;
  const cap = isoAdd(d0, 366), end = exp ? (exp < cap ? exp : cap) : d0;
  const rowOf = new Map<string, number>();
  m.stops.forEach((s, i) => { if (s.tt > 0.01) { const iso = m.isoAt(s.tt); if (!rowOf.has(iso)) rowOf.set(iso, i); } });
  const at = (iso: string): DPt => { const r = rowOf.get(iso); return r != null ? { tt: m.stops[r].tt, row: r } : { tt: Math.max(0, m.daysTo(iso)), row: null }; };
  const ends = (iso: string) => wi.filter((l) => l.ty !== 'S' && l.ex === iso);
  const pts: PayDay[] = [{ iso: d0, D: m.today, cd: 0, fri: dowOf(d0) === 5, ends: [] }];
  // Legs that end today: today's close is its own stop.
  if (end === d0 && m.daysTo(d0) > 0.01) pts.push({ iso: d0, D: at(d0), cd: 0, fri: dowOf(d0) === 5, ends: ends(d0) });
  for (let d = isoAdd(d0, 1); d <= end; d = isoAdd(d, 1)) {
    const w = dowOf(d);
    if (w === 0 || w === 6 || closed.has(d)) continue;
    pts.push({ iso: d, D: at(d), cd: daysBetween(d0, d), fri: w === 5, ends: ends(d) });
  }
  return { pts, exp, near };
}
/** "a, b and c". */
const andList = (a: string[]) => (a.length < 2 ? a.join('') : `${a.slice(0, -1).join(', ')} and ${a[a.length - 1]}`);
/** What has expired by a date (Nik, 20 Nov 2026, option 1): "Nov 20: 20 sold calls and 10 sold puts expired",
    "Nov 20 and Nov 27: ...", "Nov 20 to Dec 4, 3 expiries: ...". Empty before the first expiry. */
export function goneWords(wi: PLeg[], iso: string): string {
  const by = new Map<string, PLeg[]>();
  for (const l of wi) if (l.ty !== 'S' && l.ex && l.ex < iso) by.set(l.ex, [...(by.get(l.ex) ?? []), l]);
  const what = (ls: PLeg[]) => andList(([['C', -1, 'sold calls'], ['P', -1, 'sold puts'], ['C', 1, 'hedge calls'], ['P', 1, 'hedge puts']] as const)
    .map(([ty, sg, w]) => { const n = ls.filter((l) => l.ty === ty && Math.sign(l.q) === sg).reduce((a, l) => a + Math.abs(l.q), 0); return n > 0 ? `${count(n)} ${w}` : ''; })
    .filter(Boolean));
  const days = [...by.keys()].sort();
  if (!days.length) return '';
  const when = days.length === 1 ? mdDay(days[0]) : days.length === 2 ? `${mdDay(days[0])} and ${mdDay(days[1])}` : `${mdDay(days[0])} to ${mdDay(days[days.length - 1])}, ${days.length} expiries`;
  return `${when}: ${what(days.flatMap((d) => by.get(d)!))} expired`;
}
/** "Sold puts, hedge calls expire". */
const endsWords = (ls: PLeg[]) => {
  const nm = (a: PLeg[]) => [...new Set(a.map((l) => l.ty))].sort().map((y) => (y === 'C' ? 'calls' : 'puts')).join(' and ');
  const so = ls.filter((l) => l.q < 0), bo = ls.filter((l) => l.q > 0);
  if (!ls.length) return '';
  return [so.length ? `Sold ${nm(so)}` : '', bo.length ? `${so.length ? 'hedge' : 'Hedge'} ${nm(bo)}` : ''].filter(Boolean).join(', ') + ' expire';
};

export interface PayoffProps {
  t: string; pr: Pricer; base: PLeg[]; wi: PLeg[]; chg: boolean; tab: 'chart' | 'table'; mask: (s: string) => string; iv: number;
  closed: Set<string>;
  /** The date on the slider: 'now', an ISO day, or null for this Friday (kept across names). */
  day: string | null; setDay: (d: string | null) => void;
  /** The range, ±5 to ±50 (%). */
  xr: number; setXr: (x: number) => void;
  /** The target (a price), saved per book and name. */
  tg: number | null; setTg: (v: number | null) => void;
}
export function Payoff({ t, pr, base, wi, chg, tab, mask, iv, closed, day, setDay, xr, setXr, tg, setTg }: PayoffProps) {
  const m = pr.m, S0 = m.S0;
  const { pts, exp, near } = useMemo(() => payDays(m, wi, closed), [m, wi, closed]);
  const N = pts.length - 1;
  // The day on screen: the one picked, the end when the pick is past it, else this Friday, else the nearest sold
  // expiry (where the slider used to end), else the end.
  const fIso = m.stops[m.fridayStop] && m.stops[m.fridayStop].tt > 0.01 ? m.isoAt(m.stops[m.fridayStop].tt) : null;
  let ti = day === 'now' ? 0 : day ? pts.findIndex((p, i) => i > 0 && p.iso === day) : -1;
  if (ti < 0 && day && day !== 'now' && N > 0 && day > pts[N].iso) ti = N;
  if (ti < 0) {
    const f = fIso ? pts.findIndex((p, i) => i > 0 && p.iso === fIso) : -1, ne = near ? pts.findIndex((p, i) => i > 0 && p.iso === near) : -1;
    ti = f >= 0 ? f : ne >= 0 ? ne : N;
  }
  const P = pts[ti], D = P.D, X = Math.max(XMIN, Math.min(XMAX, xr)) / 100;
  const full = fullDay(P.iso), sh8 = ti === 0 ? 'Today' : P.cd < 3 ? WD3[dowOf(P.iso)] : mdDay(P.iso), byT = ti === 0 ? 'today' : 'by ' + full;
  const pick = (i: number) => setDay(i <= 0 ? 'now' : pts[i].iso);

  // The scale holds across the dates (round 168): today, the middle and the end of the slider, with the date on screen.
  const hold = useMemo(() => {
    let lo = 0, hi = 0;
    const xs = Array.from({ length: 21 }, (_, i) => S0 * (1 - X + (2 * X * i) / 20));
    for (const q of [pts[0], pts[Math.round(N / 2)], pts[N]]) for (const x of xs) { const y = pr.pl(wi, x, q.D); if (y < lo) lo = y; if (y > hi) hi = y; }
    return { lo, hi };
  }, [pr, wi, S0, X, pts, N]);
  const v = useMemo(() => {
    const xs = Array.from({ length: NP }, (_, i) => S0 * (1 - X + (2 * X * i) / (NP - 1)));
    const vW = xs.map((x) => pr.pl(wi, x, D)), vB = chg ? xs.map((x) => pr.pl(base, x, D)) : [];
    let ylo = hold.lo, yhi = hold.hi;
    for (const y of [...vW, ...vB]) { if (y < ylo) ylo = y; if (y > yhi) yhi = y; }
    const yp = (yhi - ylo) * 0.12 || 1; ylo -= yp; yhi += yp;
    const fy = (y: number) => ((yhi - y) / (yhi - ylo)) * 100;
    const pth = (a: number[]) => a.map((y, i) => `${i ? 'L' : 'M'}${((i / (NP - 1)) * 400).toFixed(1)} ${fy(y).toFixed(2)}`).join(' ');
    return { fy, dW: pth(vW), dB: chg ? pth(vB) : '', zy: fy(0), vW, vB };
  }, [pr, base, wi, chg, S0, X, D.tt, D.row, hold]); // eslint-disable-line react-hooks/exhaustive-deps
  const xp = (x: number) => ((x / S0 - (1 - X)) / (2 * X)) * 100;
  const v0 = pr.pl(wi, S0, D), vb0 = pr.pl(base, S0, D);
  const sh = useMemo(() => pr.shortAt(wi, D, !chg), [pr, wi, chg, D.tt, D.row]); // eslint-disable-line react-hooks/exhaustive-deps
  const mv = iv > 0 ? iv * Math.sqrt(Math.max(D.tt, 1) / 365) : 0;
  const bL = Math.max(0, xp(S0 * Math.exp(-mv))), bR = Math.min(100, xp(S0 * Math.exp(mv)));
  // The hover (0 to 1 across the chart, null off it): the Greeks row reads the hovered price (Nik, 24 Nov 2026: "the
  // delta should move when I scrub Payoff"), back to today's price on leave.
  const [hf, setHf] = useState<number | null>(null);
  useEffect(() => { if (tab !== 'chart') setHf(null); }, [tab]);
  const xH = hf == null ? null : S0 * (1 - X + 2 * X * hf);
  const gk0 = useMemo(() => pr.greeks(wi, S0, D), [pr, wi, S0, D.tt, D.row]); // eslint-disable-line react-hooks/exhaustive-deps
  const gk = useMemo(() => (xH == null ? gk0 : pr.greeks(wi, xH, D)), [gk0, xH, pr, wi, D.tt, D.row]); // eslint-disable-line react-hooks/exhaustive-deps
  const peakPast = sh != null && sh <= S0 * 1.0005, top = m.topPct;
  const gkAt = xH == null ? sh8 : `at ${xH.toFixed(2)}`;
  const gks = [
    { l: 'Delta', v: (gk.d < 0 ? 'Short ' : 'Long ') + count(gk.d), c: gk.d < 0 ? O : K },
    { l: 'Theta a day', v: mask(money(gk.th)), c: cl(gk.th) },
    { l: 'Gamma', v: count(gk.g) + ' a $1', c: gk.g < 0 ? R : K },
    { l: 'Vega', v: mask(money(gk.vg)), c: cl(gk.vg) },
  ];
  // The target: a dashed line, a ring on the curve and a pill; its P&L in the headline.
  const tgV = tg != null ? pr.pl(wi, tg, D) : 0, tgx = tg != null ? xp(tg) : -1, tgShow = tg != null && tgx >= 0 && tgx <= 100;
  const shx = sh != null && !peakPast ? xp(sh) : -1;
  const setTarget = (x: number | null) => {
    setTg(x);
    // A target past the range widens it to fit (3 points of room).
    if (x != null) { const nd = Math.min(XMAX, Math.ceil(Math.abs(x / S0 - 1) * 100 + 3)); if (nd > xr) setXr(nd); }
  };
  const zy = v.zy;
  const exD = exp ? daysBetween(P.iso, exp) : 0, atExp = !!exp && P.iso === exp && (ti > 0 || N === 0);
  // What has expired by then: screen readers only (Nik, 20 Nov 2026: "No need to write the text underneath").
  const ew = endsWords(P.ends), gone = ti > 0 ? goneWords(wi, P.iso) : '';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 16 }}>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <CountUp v={mask(money(v0))} style={{ fontSize: 30, lineHeight: '36px', fontWeight: 700, letterSpacing: '-.02em', color: cl(v0) }} />
          <span style={{ fontSize: 13, color: MU }}>If {t} is at {price(S0)} {byT}, from today’s marks</span>
          {tg != null && (
            <span className="tnum" style={{ fontSize: 13, color: '#C7C7CC' }}>At your target {price(tg)} · {fromToday(tg, S0)}, {byT}: <span style={{ fontWeight: 700, color: cl(tgV) }}>{mask(money(tgV))}</span></span>
          )}
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
              <span style={{ position: 'absolute', top: 0, bottom: 0, left: `${bL.toFixed(2)}%`, width: `${Math.max(0, bR - bL).toFixed(2)}%`, pointerEvents: 'none',
                background: 'linear-gradient(180deg,rgba(255,255,255,0),rgba(255,255,255,.06) 20%,rgba(255,255,255,.06) 80%,rgba(255,255,255,0))' }}>
                <span style={{ position: 'absolute', left: 8, top: 4, fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>
                  Priced move ±{(mv * 100).toFixed(1)}%{ti === 0 ? ' a day' : ` by ${sh8}`}
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
              {shx >= 0 && shx <= 100 && (
                <span style={{ position: 'absolute', left: `${shx.toFixed(2)}%`, top: 0, bottom: 0, borderLeft: `1.5px dotted ${O}` }}>
                  <span style={{ position: 'absolute', left: 0, bottom: 4, transform: 'translateX(-50%)', padding: '2px 6px', borderRadius: 6, background: 'rgba(6,8,7,.9)',
                    fontSize: 12, lineHeight: '16px', fontWeight: 600, color: O, whiteSpace: 'nowrap' }}>Peaks at {price(sh!)}</span>
                </span>
              )}
              {tgShow && <>
                <span style={{ position: 'absolute', left: `${tgx.toFixed(2)}%`, top: 0, bottom: 0, borderLeft: '1.5px dashed rgba(245,245,247,.6)' }}>
                  <span className="tnum" style={{ position: 'absolute', left: 0, bottom: shx >= 0 && Math.abs(shx - tgx) < 22 ? 30 : 4, transform: `translateX(${tgx < 12 ? '0' : tgx > 88 ? '-100%' : '-50%'})`,
                    padding: '2px 8px', borderRadius: 999, background: 'rgba(6,8,7,.9)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.3)', fontSize: 12, lineHeight: '16px', fontWeight: 600, color: K, whiteSpace: 'nowrap' }}>Target {price(tg!)}</span>
                </span>
                <span style={{ position: 'absolute', left: `${tgx.toFixed(2)}%`, top: `${Math.max(0, Math.min(100, v.fy(tgV))).toFixed(2)}%`, width: 13, height: 13, margin: '-6.5px 0 0 -6.5px',
                  boxSizing: 'border-box', borderRadius: '50%', border: `2.5px solid ${K}`, background: '#060807' }} />
              </>}
              <span style={{ position: 'absolute', left: '50%', top: `${v.fy(v0).toFixed(2)}%`, width: 14, height: 14, margin: '-7px 0 0 -7px', borderRadius: '50%',
                background: '#FFFFFF', boxShadow: '0 0 0 3px rgba(0,0,0,.6),0 0 14px rgba(255,255,255,.45)' }} />
            </div>
            <PayHover f={hf} setF={setHf} read={(f, full) => {
              const k = f * (NP - 1), i = Math.min(NP - 2, Math.floor(k)), w = k - i, val = v.vW[i] + (v.vW[i + 1] - v.vW[i]) * w;
              const x = S0 * (1 - X + 2 * X * f);
              // The top label adds the delta at that price (r150x hv8): "$155.20 · ↑1.9% · Δ long 300".
              const dl = full ? pr.delta(wi, x, D) : 0;
              return { y: Math.max(0, Math.min(100, v.fy(val))), top: `${price(x)} · ${fromToday(x, S0)}${full ? ` · Δ ${dl < 0 ? 'short' : 'long'} ${count(dl)}` : ''}`, val: mask(money(val)), c: cl(val) };
            }} />
          </div>
          <div className="tnum" style={{ position: 'relative', height: 18, borderTop: '1px solid rgba(255,255,255,.08)' }}>
            {[-1, -0.5, 0, 0.5, 1].map((r) => (
              <span key={r} style={{ position: 'absolute', top: 4, left: `${xp(S0 * (1 + r * X)).toFixed(2)}%`, transform: `translateX(${r === -1 ? '0' : r === 1 ? '-100%' : '-50%'})`,
                fontSize: 12, lineHeight: '14px', color: MU, whiteSpace: 'nowrap' }}>{price(S0 * (1 + r * X))}</span>
            ))}
          </div>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>
            {chg ? 'Solid: with your changes. Dashed: without them (income only).' : `The ${t} legs switched on in Every leg (income to start), P&L from today’s marks.`} Shaded: the priced move. The dot is today’s price.
          </span>
        </div>
      ) : <PayTable t={t} pr={pr} set={wi} pts={pts} ti={ti} pick={pick} mask={mask} tg={tg} chg={chg} />}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(min(100%,260px),1fr))', columnGap: 28, rowGap: 12, paddingTop: 6 }}>
        {N > 0 ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', columnGap: 12, minHeight: 28 }}>
              <span className="tnum" style={{ fontSize: 14, lineHeight: '20px', whiteSpace: 'nowrap' }}>
                <span style={{ fontWeight: 600 }}>{ti === 0 ? 'Today' : full}</span>
                <span style={{ color: MU }}> · {ti === 0 ? `${full} · now` : `close · ${P.cd === 0 ? 'today' : 'in ' + dayWords(P.cd)}`}</span>
              </span>
              {/* No "Sold calls, hedge puts expire · At expiration" line (Nik, 18 Nov 2026): one line, so the date and range
                  sliders sit level. Screen readers still hear it in the slider's text. */}
            </div>
            <Slider label="Date the curve is drawn for" min={0} max={N} value={ti} onPick={pick}
              text={(ti === 0 ? 'Today, now' : `${full} close, in ${dayWords(P.cd)}`) + (atExp ? `. At expiration${ew ? ', ' + ew.toLowerCase() : ''}` : ew ? `. ${ew}` : '') + (gone ? `. ${gone}` : '')} />
            <DateTicks pts={pts} ti={ti} />
          </div>
        ) : <div />}
        <RangeBox S0={S0} xr={xr} setXr={setXr} tg={tg} setTarget={setTarget} />
      </div>
      <div className="tnum" aria-live="off" style={{ display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', paddingTop: 10, borderTop: '1px solid rgba(255,255,255,.08)' }}>
        {gks.map((g) => (
          <span key={g.l} style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{g.l} · {gkAt}</span>
            <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600, color: g.c, whiteSpace: 'nowrap' }}>{g.v}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/** The ticks under the date slider: each Friday, taller and brighter where legs expire; every day when there are 8 or
    fewer. Labels: Today, the end, and between them each expiry (Nik, 20 Nov 2026, option 1; a middle Friday when no
    leg ends between), measured so no two touch (a label that would is left out; its tall tick stays). */
function DateTicks({ pts, ti }: { pts: PayDay[]; ti: number }) {
  const [ref, W] = useWidth<HTMLDivElement>(true);
  const N = pts.length - 1, at = (i: number) => `calc(17px + (100% - 34px) * ${(i / N).toFixed(4)})`, few = N <= 8;
  const word = (i: number) => { const p = pts[i]; return i === 0 ? 'Today' : i === N ? (N <= 4 ? fullDay(p.iso) : mdDay(p.iso)) : few ? WD3[dowOf(p.iso)] : mdDay(p.iso); };
  const lbs = (() => {
    const exs = pts.map((p, i) => (i > 0 && i < N && p.ends.length > 0 ? i : -1)).filter((i) => i > 0);
    const fr = pts.map((p, i) => (p.fri && i > 0 && i < N ? i : -1)).filter((i) => i > 0);
    const mid = few ? pts.map((_, i) => i).slice(1, N) : exs.length ? exs : fr.length > 2 ? [fr[Math.floor(fr.length / 2)]] : [];
    // 12px labels: about 6.6px a character, 6px between.
    const wd = (i: number) => word(i).length * 6.6, x = (i: number) => 17 + (W - 34) * (i / N);
    const out = [0];
    let right = wd(0);
    const end = W - wd(N);
    for (const i of mid) { const a = x(i) - wd(i) / 2, b = x(i) + wd(i) / 2; if (a >= right + 6 && b <= end - 6) { out.push(i); right = b; } }
    return N > 0 ? [...out, N] : out;
  })();
  return (
    <div ref={ref} aria-hidden="true" style={{ position: 'relative', height: 28, marginTop: -6 }}>
      {pts.map((p, i) => {
        const ex = p.ends.length > 0;
        if (!few && !p.fri && !ex && i !== N) return null;
        return <span key={'k' + i} style={{ position: 'absolute', top: 0, left: at(i), width: 1, height: ex ? 8 : p.fri ? 6 : 4, background: ex ? 'rgba(245,245,247,.7)' : 'rgba(255,255,255,.22)' }} />;
      })}
      {lbs.map((i) => (
        <span key={'b' + i} className="tnum" style={{ position: 'absolute', top: 11, left: i === 0 ? 0 : i === N ? '100%' : at(i), transform: `translateX(${i === 0 ? '0' : i === N ? '-100%' : '-50%'})`,
          fontSize: 12, lineHeight: '14px', color: i === ti ? K : MU, whiteSpace: 'nowrap' }}>{word(i)}</span>
      ))}
    </div>
  );
}

const GLASS_BTN: CSSProperties = {
  background: 'linear-gradient(160deg,rgba(255,255,255,.24) 0%,rgba(255,255,255,.10) 50%,rgba(255,255,255,.18) 100%)',
  boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.35),inset 1px 1px 0 -.5px rgba(255,255,255,.5),0 2px 6px rgba(0,0,0,.3)',
};
/** Range ±N% with Reset once moved, the target button and its popover, the range slider. */
function RangeBox({ S0, xr, setXr, tg, setTarget }: { S0: number; xr: number; setXr: (x: number) => void; tg: number | null; setTarget: (x: number | null) => void }) {
  const [open, setOpen] = useState(false);
  const btn = useRef<HTMLButtonElement>(null);
  return (
    <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
      <TargetPop open={open} S0={S0} tg={tg} close={(back) => { setOpen(false); if (back) btn.current?.focus(); }} set={(x) => { setTarget(x); setOpen(false); btn.current?.focus(); }} />
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: '6px 8px', minHeight: 28 }}>
        <span className="tnum" style={{ fontSize: 14, lineHeight: '20px', whiteSpace: 'nowrap' }}><span style={{ color: MU }}>Range </span><span style={{ fontWeight: 600 }}>±{xr}%</span></span>
        <span style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 6 }}>
          {xr !== XR0 && (
            <button type="button" className="bare" onClick={() => setXr(XR0)} aria-label={`Reset the range to plus or minus ${XR0}%`}
              style={{ padding: '1px 10px', borderRadius: 999, fontSize: 12, lineHeight: '18px', fontWeight: 600, color: K, ...GLASS_BTN }}>Reset</button>
          )}
          <button ref={btn} type="button" className="bare" onClick={() => setOpen(!open)} aria-haspopup="dialog" aria-expanded={open} title="Target price"
            aria-label={tg != null ? `Target ${price(tg)}, change it` : 'Set a target price'}
            style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6, height: 28, minWidth: 28, boxSizing: 'border-box', padding: tg != null ? '0 11px 0 9px' : 0,
              borderRadius: 999, fontSize: 12, lineHeight: '16px', fontWeight: 600, color: K, ...tnum, ...GLASS_BTN }}>
            <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style={{ flex: 'none' }}>
              <circle cx="7" cy="7" r="5.8" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.4 }} /><circle cx="7" cy="7" r="2.4" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.4 }} />
            </svg>{tg != null ? price(tg) : ''}
          </button>
        </span>
      </div>
      <Slider label="Price range of the chart" min={XMIN} max={XMAX} value={xr} onPick={setXr} text={`Plus or minus ${xr} percent`} />
      <div aria-hidden="true" style={{ display: 'flex', justifyContent: 'space-between', marginTop: -6, paddingTop: 11, fontSize: 12, lineHeight: '14px', color: MU }}><span>±{XMIN}%</span><span>±{XMAX}%</span></div>
    </div>
  );
}

/** Set target (round 168): a glass popover over the range. Type a price; Set target or Enter sets it, Clear takes it
    off, Escape or the X closes. The field keeps its own state, so the chart does not redraw while typing. */
function TargetPop({ open, S0, tg, close, set }: { open: boolean; S0: number; tg: number | null; close: (back: boolean) => void; set: (x: number | null) => void }) {
  const rm = useReducedMotion();
  const [txt, setTxt] = useState('');
  const [bad, setBad] = useState(false);
  const inp = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (!open) return;
    setTxt((tg ?? S0).toFixed(2)); setBad(false);
    const id = setTimeout(() => { inp.current?.focus(); inp.current?.select(); }, 40);
    return () => clearTimeout(id);
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps
  const val = (() => { const x = parseFloat(txt.replace(/[$,\s]/g, '')); return x > 0 && Number.isFinite(x) ? x : null; })();
  const go = () => { if (val == null) { setBad(true); inp.current?.focus(); return; } set(+val.toFixed(2)); };
  const ch = val != null ? val / S0 - 1 : 0;
  return (
    <div role="dialog" aria-label="Target price" aria-hidden={!open} onKeyDown={(e) => { if (e.key === 'Escape') { e.preventDefault(); close(true); } }}
      style={{ position: 'absolute', right: 0, bottom: 'calc(100% + 10px)', zIndex: 6, width: 300, maxWidth: 'calc(100vw - 32px)', boxSizing: 'border-box', padding: 18, borderRadius: 22,
        display: 'flex', flexDirection: 'column', gap: 14, background: 'rgba(36,36,40,.8)', backdropFilter: 'blur(24px) saturate(1.6)', WebkitBackdropFilter: 'blur(24px) saturate(1.6)',
        boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.28),inset 1px 1px 0 -.5px rgba(255,255,255,.4),0 18px 48px rgba(0,0,0,.6)',
        opacity: open ? 1 : 0, transform: open || rm ? 'none' : 'translateY(6px) scale(.97)', visibility: open ? 'visible' : 'hidden', pointerEvents: open ? 'auto' : 'none', transformOrigin: '100% 100%',
        transition: rm ? `opacity .18s ease, visibility 0s linear ${open ? '0s' : '.18s'}` : `opacity .18s ease, transform .26s cubic-bezier(.34,1.36,.64,1), visibility 0s linear ${open ? '0s' : '.18s'}` }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
          <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600 }}>Target price</span>
          <span style={{ fontSize: 13, lineHeight: '18px', color: MU, textWrap: 'pretty' }}>Marks the price on the chart and reads your P&amp;L there.</span>
        </span>
        <button type="button" className="bare" onClick={() => close(true)} aria-label="Close" tabIndex={open ? 0 : -1}
          style={{ flex: 'none', width: 28, height: 28, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#C7C7CC', ...GLASS_BTN }}>
          <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M1.5 1.5l7 7M8.5 1.5l-7 7" style={{ stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round' }} /></svg>
        </button>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 2, width: 132, height: 40, boxSizing: 'border-box', padding: '0 12px', borderRadius: 12, background: 'rgba(118,118,128,.24)',
          boxShadow: bad ? 'inset 0 0 0 1.5px #FF6961' : 'none' }}>
          <span style={{ fontSize: 17, lineHeight: '22px', color: MU }}>$</span>
          <input ref={inp} type="text" inputMode="decimal" autoComplete="off" aria-label="Target price in dollars" value={txt} tabIndex={open ? 0 : -1}
            onChange={(e) => { setTxt(e.target.value); setBad(false); }} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); go(); } }}
            style={{ all: 'unset', width: '100%', minWidth: 0, fontFamily: 'inherit', fontSize: 17, lineHeight: '22px', fontWeight: 600, color: K, ...tnum }} />
        </span>
        <span className="tnum" style={{ fontSize: 13, lineHeight: '18px', color: MT, whiteSpace: 'nowrap' }}>
          {val == null ? '' : Math.abs(ch) < 0.0005 ? 'today’s price' : `${fromToday(val, S0)} from today`}
        </span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', gap: 8 }}>
        <button type="button" className="bare swp-press" onClick={go} tabIndex={open ? 0 : -1}
          style={{ height: 38, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600, color: '#000000', background: K, boxShadow: '0 2px 8px rgba(0,0,0,.3)' }}>Set target</button>
        <button type="button" className="bare swp-press" onClick={() => set(null)} tabIndex={open ? 0 : -1}
          style={{ height: 38, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600, color: K, ...GLASS_BTN }}>Clear</button>
      </div>
    </div>
  );
}

/** The iOS slider (round 168): a 4 px track, a white 34 × 22 capsule thumb that turns glass while dragged (a spring,
    .22 s); a press or drag anywhere on it moves there. Keys: arrows one step, Page Up and Down five, Home and End. */
function Slider({ label, min, max, value, onPick, text }: { label: string; min: number; max: number; value: number; onPick: (v: number) => void; text: string }) {
  const rm = useReducedMotion();
  const [drag, setDrag] = useState(false);
  const last = useRef<number | null>(null);
  const at = (e: React.PointerEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect(), f = Math.max(0, Math.min(1, (e.clientX - r.left - 17) / Math.max(1, r.width - 34)));
    return Math.round(min + f * (max - min));
  };
  const put = (v: number) => { if (last.current === v) return; last.current = v; onPick(v); };
  const f = max > min ? (Math.max(min, Math.min(max, value)) - min) / (max - min) : 0, x = `calc(17px + (100% - 34px) * ${f.toFixed(4)})`;
  const end = () => { setDrag(false); last.current = null; };
  return (
    <div role="slider" tabIndex={0} aria-label={label} aria-valuemin={min} aria-valuemax={max} aria-valuenow={value} aria-valuetext={text} className="swp-slider"
      onPointerDown={(e) => { try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* old browsers */ } setDrag(true); last.current = null; put(at(e)); }}
      onPointerMove={(e) => { if (drag) put(at(e)); }} onPointerUp={end} onPointerCancel={end} onLostPointerCapture={end}
      onKeyDown={(e) => {
        const st = ({ ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1, PageUp: 5, PageDown: -5 } as Record<string, number>)[e.key];
        const hm = e.key === 'Home' ? min : e.key === 'End' ? max : null;
        if (st == null && hm == null) return;
        e.preventDefault();
        onPick(hm ?? Math.max(min, Math.min(max, value + st)));
      }}
      style={{ position: 'relative', height: 36, cursor: 'pointer', touchAction: 'pan-y', userSelect: 'none', WebkitUserSelect: 'none', outline: 'none', borderRadius: 10 }}>
      <span style={{ position: 'absolute', left: 0, right: 0, top: 16, height: 4, borderRadius: 2, background: 'rgba(118,118,128,.32)' }} />
      <span style={{ position: 'absolute', left: 0, top: 16, height: 4, borderRadius: 2, width: x, background: K }} />
      <span style={{ position: 'absolute', left: x, top: 18, width: 34, height: 22, borderRadius: 999, transform: `translate(-50%,-50%) scale(${drag && !rm ? 1.16 : 1})`,
        background: drag ? 'rgba(255,255,255,.2)' : K, backdropFilter: drag ? 'blur(6px) saturate(1.6)' : 'none', WebkitBackdropFilter: drag ? 'blur(6px) saturate(1.6)' : 'none',
        boxShadow: drag ? 'inset 0 0 0 .5px rgba(255,255,255,.6),inset 1px 1px 0 -.5px rgba(255,255,255,.75),0 4px 14px rgba(0,0,0,.45)' : '0 1px 2px rgba(0,0,0,.3),0 3px 10px rgba(0,0,0,.35)',
        transition: rm ? 'none' : 'transform .22s cubic-bezier(.34,1.36,.64,1),background .2s ease,box-shadow .2s ease' }} />
    </div>
  );
}

/** The Payoff hover (round 168, OptionStrat's crosshair): a line at that price starting under the price and % from
    today on top, a dot on the curve, the P&L beside it on the curve's open side (green or red, a dark halo, no box).
    A finger reads while it is down. A move with no movement (the page scrolled under a still mouse) is ignored. */
function PayHover({ f, setF, read }: { f: number | null; setF: (f: number | null) => void; read: (f: number, full: boolean) => { y: number; top: string; val: string; c: string } }) {
  const touch = useRef(false);
  const at = (e: React.PointerEvent<HTMLDivElement>) => { const r = e.currentTarget.getBoundingClientRect(); if (r.width) setF(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width))); };
  const off = () => { touch.current = false; setF(null); };
  const h = f == null ? null : read(f, true);
  let vt = 'none';
  if (h && f != null) {
    // Below the dot when the curve climbs that way, or when the dot is up under the price read on top.
    const nb = read(Math.max(0, Math.min(1, f + (f > 0.6 ? -0.08 : 0.08))), false), below = nb.y < h.y || h.y < 18;
    vt = `translate(${f > 0.6 ? 'calc(-100% - 10px)' : '10px'},${below ? '6px' : 'calc(-100% - 6px)'})`;
  }
  const x = f == null ? '0%' : `${(f * 100).toFixed(2)}%`;
  return (
    <div aria-hidden="true" onPointerDown={(e) => { if (e.pointerType === 'touch') touch.current = true; at(e); }}
      onPointerMove={(e) => { if (e.pointerType === 'touch' ? !touch.current : e.movementX === 0 && e.movementY === 0) return; at(e); }}
      onPointerUp={(e) => { if (e.pointerType === 'touch') off(); }} onPointerCancel={off} onPointerLeave={off}
      style={{ position: 'absolute', inset: 0, cursor: 'crosshair', touchAction: 'pan-y', userSelect: 'none', WebkitUserSelect: 'none' }}>
      {h && (
        <div style={{ position: 'absolute', left: 0, right: 0, top: 10, bottom: 10, pointerEvents: 'none' }}>
          <span style={{ position: 'absolute', top: 12, bottom: -10, left: x, borderLeft: '1px solid rgba(245,245,247,.85)' }} />
          <span style={{ position: 'absolute', top: -10, left: x, transform: `translateX(${f! < 0.14 ? '0' : f! > 0.86 ? '-100%' : '-50%'})`, padding: '0 2px',
            textShadow: '0 1px 2px rgba(0,0,0,.9),0 0 10px rgba(0,0,0,.85)', fontSize: 13, lineHeight: '18px', fontWeight: 600, color: K, whiteSpace: 'nowrap', ...tnum }}>{h.top}</span>
          <span style={{ position: 'absolute', left: x, top: `${h.y.toFixed(2)}%`, width: 11, height: 11, margin: '-5.5px 0 0 -5.5px', borderRadius: '50%', background: '#FFFFFF', boxShadow: '0 0 8px rgba(255,255,255,.35)' }} />
          <span style={{ position: 'absolute', left: x, top: `${h.y.toFixed(2)}%`, transform: vt, padding: '0 2px', textShadow: '0 0 2px #060807,0 0 4px #060807,0 0 10px rgba(6,8,7,.95)',
            fontSize: 17, lineHeight: '22px', fontWeight: 700, color: h.c, whiteSpace: 'nowrap', ...tnum }}>{h.val}</span>
        </div>
      )}
    </div>
  );
}

const SP = [10, 7.5, 5, 2.5, 0, -2.5, -5, -7.5, -10];
/** P&L for prices ↑10% to ↓10% in 2.5% steps (and the target as its own row) against today and each Friday the grid
    reaches; the slider's day lit. A tap moves the slider there, up to its end; later columns look past it. */
function PayTable({ t, pr, set, pts, ti, pick, mask, tg, chg }: { t: string; pr: Pricer; set: PLeg[]; pts: PayDay[]; ti: number; pick: (i: number) => void; mask: (s: string) => string; tg: number | null; chg: boolean }) {
  const S0 = pr.m.S0, segs = pr.m.segments();
  const cols = [segs[0], ...segs.filter((s, i) => i > 0 && s.friday)].slice(0, 7).map((c, j) => {
    const idx = j === 0 ? 0 : pts.findIndex((p, i) => i > 0 && p.iso === c.iso);
    return { c, idx, D: (j === 0 ? pr.m.today : { tt: c.tt, row: c.row }) as DPt };
  });
  const rows: { p: number; x: number; tg: boolean }[] = SP.map((p) => ({ p, x: S0 * (1 + p / 100), tg: false }));
  if (tg != null) { const hit = rows.find((r) => Math.abs(r.x - tg) < 0.005); if (hit) hit.tg = true; else rows.push({ p: (tg / S0 - 1) * 100, x: tg, tg: true }); }
  rows.sort((a, b) => b.x - a.x);
  const grid = rows.map((r) => cols.map((c) => pr.pl(set, r.x, c.D)));
  const gmx = Math.max(1, ...grid.map((r) => Math.max(...r.map(Math.abs))));
  const tpl = `128px repeat(${cols.length},minmax(0,1fr))`;
  const later = cols.some((c) => c.idx < 0);
  return (
    <div className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <div style={{ display: 'grid', gridTemplateColumns: tpl, gap: 2, borderBottom: '1px solid rgba(255,255,255,.14)' }}>
        <span style={{ ...kicker, padding: '6px 0' }}>If {t} is at</span>
        {cols.map(({ c, idx }) => {
          const on = idx >= 0 && idx === ti;
          return (
            <button key={c.i} type="button" className="bare" onClick={() => { if (idx >= 0) pick(idx); }} aria-pressed={on} aria-disabled={idx < 0}
              style={{ textAlign: 'center', padding: '6px 0', fontSize: 13, lineHeight: '18px', fontWeight: on ? 700 : 500, color: on ? K : idx < 0 ? MU : MT,
                boxShadow: `inset 0 -2px 0 ${on ? K : 'transparent'}`, cursor: idx < 0 ? 'default' : 'pointer' }}>{c.label}</button>
          );
        })}
      </div>
      {rows.map((r, ri) => (
        <div key={r.x.toFixed(2) + (r.tg ? 't' : '')} style={{ display: 'grid', gridTemplateColumns: tpl, gap: 2 }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 6, padding: '4px 0' }}>
            <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: r.tg || Math.abs(r.p) < 0.0005 ? 700 : 500 }}>{price(r.x)}</span>
            <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{r.tg ? 'target' : Math.abs(r.p) < 0.0005 ? 'today' : `${r.p > 0 ? '↑' : '↓'}${Math.round(Math.abs(r.p) * 10) / 10}%`}</span>
          </span>
          {grid[ri].map((val, j) => {
            const a = Math.min(1, Math.abs(val) / gmx), z = Math.abs(val) < 0.5, col = cols[j], on = col.idx >= 0 && col.idx === ti;
            return (
              <button key={j} type="button" className="bare swp-cell" onClick={() => { if (col.idx >= 0) pick(col.idx); }}
                aria-label={`${price(r.x)} by ${col.c.label}, ${mask(money(val))}${val < 0 ? ' loss' : ''}`}
                style={{ textAlign: 'center', padding: '4px 0', borderRadius: 6, fontSize: 13, lineHeight: '18px', fontWeight: on || r.tg ? 700 : 500,
                  color: z ? MU : val > 0 ? G : R, background: z ? 'transparent' : `${val > 0 ? 'rgba(101,196,102,' : 'rgba(255,105,97,'}${(0.05 + a * 0.18).toFixed(3)})`,
                  boxShadow: on ? 'inset 0 0 0 1.5px rgba(245,245,247,.8)' : r.tg ? 'inset 0 0 0 1px rgba(245,245,247,.35)' : 'none', cursor: col.idx < 0 ? 'default' : 'pointer' }}>{z ? '$0' : mask(money(val))}</button>
            );
          })}
        </div>
      ))}
      <span style={{ paddingTop: 6, fontSize: 12, lineHeight: '16px', color: MU }}>
        P&amp;L from today’s marks{chg ? ', with your changes' : ''}. Tap a column to move the date there{later ? '; later columns look past the expiry' : ''}.{tg != null ? ' Your target is its own row.' : ''}
      </span>
    </div>
  );
}


/* ── Scrub (the Price chart) ───────────────────────────────────────────── */
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
