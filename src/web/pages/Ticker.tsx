// Ticker page (README "4 · Ticker page"): opened from a heatmap or map tile of a book or watchlist name, with
// state.from = 'home' | 'positions' for the back link. One name's price over a range, with layers that never move
// the chart: the scale already spans every layer.
//
// Data: sunny-chart (useTicker), as the phone's ticker chart reads it. Positions: the book's strikes in this name
// (sold solid, bought dotted), book names only. Technicals: the 20 and 50-day averages, worked out here from the
// closes as the phone does. Walls: the nearest weekly's Ceiling and Floor, and the move priced by Friday shaded
// after today when the reply carries it. Targets: sunny-chart sends no analyst targets, so the layer reads n/a.
import { useMemo, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { useTicker, type J } from '../lib/data';
import { C, arrow, pct, price } from '../lib/format';
import { useWeb } from '../lib/state';
import { RANGES, positionLines, series, sma, spread, spreadAround, wallLines, type Range } from '../ticker/model';

const H = 440;
const SG = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';
type Layer = 'pos' | 'tech' | 'walls' | 'tgt';
const LAYERS: [Layer, string][] = [['pos', 'Positions'], ['tech', 'Technicals'], ['walls', 'Walls'], ['tgt', 'Targets']];

export default function Ticker() {
  const { ticker = '' } = useParams();
  const t = ticker.toUpperCase();
  return <TickerPage key={t} t={t} />;
}

function TickerPage({ t }: { t: string }) {
  const loc = useLocation();
  const nav = useNavigate();
  const { book } = useWeb();
  const from = (loc.state as { from?: string } | null)?.from === 'positions' ? 'positions' : 'home';
  const back = () => (loc.key !== 'default' ? nav(-1) : nav(from === 'positions' ? '/positions' : '/home'));
  // Asked once the book is known, so the reply carries the book's legs in this name.
  const q = useTicker(book ? t : null, book);
  const d: J = q.data;
  const [rg, setRg] = useState<Range>('3M');
  const [pick, setPick] = useState<Record<Layer, boolean> | null>(null);

  const closes: number[] = useMemo(() => ((d?.closes ?? []) as number[]).map(Number), [d]);
  const dates: string[] = d?.dates ?? [];
  const ma = useMemo(() => ({ m20: sma(closes, 20), m50: sma(closes, 50) }), [closes]);
  const pos = useMemo(() => positionLines(d?.positions ?? []), [d]);
  const walls = useMemo(() => wallLines(d?.walls ?? []), [d]);
  const ok: Record<Layer, boolean> = { pos: pos.length > 0, tech: closes.length >= 20, walls: walls.length > 0, tgt: false };
  const on: Record<Layer, boolean> = pick ?? { pos: ok.pos, tech: false, walls: false, tgt: false };
  const s = useMemo(() => series(closes, dates, rg, ma), [closes, dates, rg, ma]);

  const px = Number(d?.price ?? 0), prev = Number(d?.prev ?? 0);
  const mv = prev > 0 ? ((px - prev) / prev) * 100 : 0;
  const first = s.pts[0] ?? 0, last = s.pts.at(-1) ?? 0, dff = last - first, dffP = first > 0 ? (dff / first) * 100 : 0;
  const lc = dff >= 0 ? C.green : C.red;
  const sd = d?.sd != null && Number(d.sd) > 0 ? Number(d.sd) : null;
  const band = sd != null ? [px * (1 + sd / 100), px * (1 - sd / 100)] : null;

  // The scale spans every layer, on or off, so turning one on never moves the chart (the design's `all`).
  const g = useMemo(() => {
    const vals = [...s.pts, px, ...pos.map((l) => l.k), ...walls.map((l) => l.k), ...(band ?? []),
      ...(s.m20.filter((v) => v != null) as number[]), ...(s.m50.filter((v) => v != null) as number[])].filter((v) => Number.isFinite(v) && v > 0);
    let lo = Math.min(...vals), hi = Math.max(...vals);
    const pd = (hi - lo) * 0.06 || px * 0.02 || 1;
    lo -= pd; hi += pd;
    const yf = (v: number) => (hi - v) / (hi - lo);
    const n = s.pts.length, X = (i: number) => (n > 1 ? (i / (n - 1)) * 352 : 0).toFixed(2);
    const line = (a: (number | null)[]) => {
      let p = '', mv0 = true;
      a.forEach((v, i) => { if (v == null) { mv0 = true; return; } p += (mv0 ? 'M' : 'L') + X(i) + ' ' + (yf(v) * 100).toFixed(2) + ' '; mv0 = false; });
      return p.trim();
    };
    return { yf, d: line(s.pts), m20: line(s.m20), m50: line(s.m50) };
  }, [s, px, pos, walls, band?.[0], band?.[1]]); // eslint-disable-line react-hooks/exhaustive-deps

  const tp = (v: number) => (g.yf(v) * 100).toFixed(2) + '%';
  const hl = [
    ...(on.pos ? pos.map((l) => ({ k: 'p' + l.k, v: l.k, l: l.label, bd: `1.5px ${l.solid ? 'solid' : 'dotted'} rgba(245,245,247,.72)`, right: false })) : []),
    ...(on.walls ? walls.map((l) => ({ k: 'w' + l.label, v: l.k, l: l.label, bd: `2px dashed rgba(245,245,247,${l.floor ? '.42' : '.72'})`, right: true })) : []),
  ];
  const side = (r: boolean) => {
    const xs = hl.filter((x) => x.right === r);
    const y0 = xs.map((x) => g.yf(x.v) * H);
    const ys = r ? spreadAround(y0, 11, H - 8, g.yf(px) * H) : spread(y0, 11, H - 8);
    return xs.map((x, i) => ({ ...x, ly: ys[i] }));
  };
  const tags = [...side(false), ...side(true)];
  const toggle = (k: Layer) => setPick({ ...on, [k]: !on[k] });
  const note = ok.pos ? 'Positions draws your strikes (sold solid, bought dotted).'
    : d?.watch === false ? 'No positions to draw.' : 'A watchlist name: no positions to draw.';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, maxWidth: 1240 }}>
      <button type="button" className="bare sw-tkb" onClick={back} style={{ alignSelf: 'flex-start', fontSize: 14, color: C.ink2 }}>
        ‹ {from === 'positions' ? 'Positions' : 'Home'}
      </button>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, flexWrap: 'wrap' }}>
        <span style={{ fontSize: 34, lineHeight: '40px', fontWeight: 700, letterSpacing: '-.025em' }}>{t}</span>
        {d && <span style={{ fontSize: 28, lineHeight: '34px', fontWeight: 500 }}>{price(px)}</span>}
        {d && <span style={{ fontSize: 16, fontWeight: 600, color: mv < 0 ? C.red : C.green }}>{arrow(mv)} {pct(mv)} today</span>}
      </div>
      <span style={{ fontSize: 15, minHeight: 18 }}>
        {d && s.pts.length > 1 && <><span style={{ fontWeight: 600, color: lc }}>{arrow(dff)} {price(dff)} · {pct(dffP)}</span> <span style={{ color: C.ink2 }}>{s.phrase}</span></>}
      </span>

      <div style={{ position: 'relative', height: H, marginTop: 6 }}>
        {!d && (
          <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: C.ink2 }}>
            {q.isError ? `Could not load ${t}. Try again in a moment.` : ''}
          </span>
        )}
        {d && s.pts.length > 1 && (
          <>
            {on.walls && band && (
              <span style={{ position: 'absolute', left: '88%', right: 0, top: tp(band[0]), height: ((g.yf(band[1]) - g.yf(band[0])) * 100).toFixed(2) + '%',
                boxSizing: 'content-box', background: 'rgba(134,168,240,.08)', borderTop: '1px dashed rgba(134,168,240,.4)', borderBottom: '1px dashed rgba(134,168,240,.4)' }} />
            )}
            <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', left: 0, top: 0, width: '100%', height: '100%' }}>
              {on.tech && <path d={g.m20} style={{ fill: 'none', stroke: C.teal, strokeWidth: 1.5, strokeDasharray: '4 3', vectorEffect: 'non-scaling-stroke' }} />}
              {on.tech && <path d={g.m50} style={{ fill: 'none', stroke: C.teal, strokeWidth: 1.5, strokeDasharray: '9 4', vectorEffect: 'non-scaling-stroke' }} />}
              <path d={g.d} style={{ fill: 'none', stroke: lc, strokeWidth: 9, opacity: 0.15, vectorEffect: 'non-scaling-stroke' }} />
              <path d={g.d} style={{ fill: 'none', stroke: lc, strokeWidth: 2.5, vectorEffect: 'non-scaling-stroke' }} />
            </svg>
            {hl.map((x) => (
              <span key={x.k} style={{ position: 'absolute', left: 0, right: x.right ? 0 : '12%', top: tp(x.v), borderTop: x.bd }} />
            ))}
            {tags.map((x) => (
              <span key={'l' + x.k} style={{ position: 'absolute', zIndex: 1, left: x.right ? 'auto' : 8, right: x.right ? 8 : 'auto', top: x.ly - 11,
                background: 'rgba(6,8,7,.92)', borderRadius: 6, padding: '1px 7px', fontSize: 12, fontWeight: 600, whiteSpace: 'nowrap' }}>{x.l}</span>
            ))}
            <span style={{ position: 'absolute', zIndex: 2, left: '88%', top: tp(px), transform: 'translate(-50%,-50%)', background: '#F5F5F7', color: '#000000',
              borderRadius: 999, padding: '2px 9px', fontSize: 12, fontWeight: 700, whiteSpace: 'nowrap' }}>{price(px)}</span>
          </>
        )}
      </div>
      <div style={{ position: 'relative', boxSizing: 'content-box', height: 16, fontSize: 12, color: C.ink2, borderTop: '1px solid rgba(255,255,255,.08)', paddingTop: 6 }}>
        <span style={{ position: 'absolute', left: 0 }}>{d ? s.x0 : ''}</span>
        <span style={{ position: 'absolute', left: '88%', transform: 'translateX(-50%)' }}>Today</span>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16, flexWrap: 'wrap', paddingTop: 10, borderBottom: '1px solid rgba(255,255,255,.14)' }}>
        <div role="radiogroup" aria-label="Range" style={{ display: 'flex', gap: 26 }}>
          {RANGES.map((r) => (
            <button key={r} type="button" role="radio" aria-checked={r === rg} className="bare" onClick={() => setRg(r)}
              style={{ padding: '10px 0 9px', fontSize: 14, fontWeight: r === rg ? 700 : 400, color: r === rg ? '#F5F5F7' : C.ink2,
                boxShadow: `inset 0 -2px 0 ${r === rg ? '#F5F5F7' : 'transparent'}` }}>{r}</button>
          ))}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, paddingBottom: 8 }}>
          {LAYERS.map(([k, l]) => {
            const can = !!d && ok[k], sel = can && on[k];
            return (
              <button key={k} type="button" className="bare sw-tkl" aria-pressed={sel} aria-disabled={!can} onClick={can ? () => toggle(k) : undefined}
                style={{ padding: '6px 14px', borderRadius: 999, fontSize: 14, lineHeight: '18px', fontWeight: sel ? 600 : 500,
                  color: !can ? 'rgba(255,255,255,.3)' : sel ? '#FFFFFF' : '#F5F5F7', background: sel ? 'rgba(255,255,255,.20)' : 'transparent',
                  boxShadow: sel ? SG : 'none', outline: '1px solid rgba(255,255,255,.14)', outlineOffset: -1, whiteSpace: 'nowrap', cursor: can ? 'pointer' : 'default' }}>
                {can || !d ? l : `${l} · n/a`}
              </button>
            );
          })}
        </div>
      </div>
      <span style={{ fontSize: 13, lineHeight: '20px', color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>
        {note} Technicals: the 20 and 50-day averages. Walls: this week’s Ceiling and Floor, the priced move shaded after today. The scale already spans every layer, so turning one on never moves the chart.
      </span>
      <style>{`.sw .sw-tkb:hover{color:#F5F5F7!important}.sw .sw-tkl:focus-visible{outline:2px solid #86A8F0!important;outline-offset:2px!important}`}</style>
    </div>
  );
}
