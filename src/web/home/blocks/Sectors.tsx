// Sectors (Web Dark v2, `b.isSecbar` and `b.isMaps`): the All 11 sectors table (Sector · Weight · Move on a bar
// centred on zero · Leads · Trails · Your names), then a heat map per sector, three a row (two when narrow):
// a squarified treemap of its biggest names by weight, tiles coloured by move with the text in the tile's own
// colour, labels only when they fit, the book's names ringed, a tooltip and aria-label on every tile, and a tile
// of a book or watchlist name opening its ticker page. Data: the brief doc's sectors card (`maps`, one per sector,
// each with its tiles: ticker, name, move, weight). Leads and Trails are the best and worst movers among those tiles.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { J } from '../../lib/data';
import { C, clean, pct } from '../../lib/format';
import { NARROW_QUERY } from '../../WebLayout';
import { pmove, tileColors } from './util';

const HAIR = '1px solid rgba(255,255,255,.08)';
const COLS = 'minmax(0,1.1fr) 60px 220px minmax(0,1fr) minmax(0,1fr) 100px';

interface Item { t: string; nm: string; p: number; v: number }
interface Sec { id: string; t: string; w: string; mv: number; items: Item[]; ld?: Item; tr?: Item; yours: string[] }

export function useNarrow() {
  const q = () => (typeof window !== 'undefined' && window.matchMedia ? window.matchMedia(NARROW_QUERY).matches : false);
  const [n, setN] = useState(q);
  useEffect(() => {
    const m = window.matchMedia?.(NARROW_QUERY);
    if (!m) return;
    const f = () => setN(m.matches);
    f();
    m.addEventListener('change', f);
    return () => m.removeEventListener('change', f);
  }, []);
  return n;
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-');

export function sectorsOf(card: J, held: Set<string>): Sec[] {
  return (card.maps ?? []).map((m: J) => {
    const items: Item[] = (m.tiles ?? []).map((x: J) => ({ t: clean(x.ticker), nm: clean(x.name) || clean(x.ticker), p: +x.move || 0, v: +x.weight || 0 }));
    const srt = items.slice().sort((a, b) => b.p - a.p);
    const mv = m.moveSigned != null ? +m.moveSigned : (m.moveColor === 'red' ? -1 : 1) * parseFloat(m.move);
    return { id: slug(clean(m.title)), t: clean(m.title), w: clean(m.weightOfSP500), mv: mv || 0, items, ld: srt[0], tr: srt[srt.length - 1], yours: items.filter((q) => held.has(q.t)).map((q) => q.t) };
  });
}

/** The table. `onRow` opens that sector's map (none before the bell: the maps are not on the page then). */
export function SectorTable({ secs, sub, onRow }: { secs: Sec[]; sub: string; onRow?: (id: string) => void }) {
  const rows = secs.slice().sort((a, b) => b.mv - a.mv);
  const mx = Math.max(...rows.map((x) => Math.abs(x.mv)), 0) || 1;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 16, borderTop: '1px solid rgba(255,255,255,.14)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, paddingBottom: 10 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>All {secs.length} sectors</span>
        <span style={{ fontSize: 13, color: C.ink2 }}>{sub}</span>
      </div>
      <div className="tnum kicker" style={{ display: 'grid', gridTemplateColumns: COLS, gap: 12, padding: '6px 0 8px' }}>
        <span>Sector</span><span>Weight</span><span>Move</span><span>Leads</span><span>Trails</span><span>Your names</span>
      </div>
      {rows.map((x) => {
        const wd = Math.abs(x.mv) / mx * 50, up = x.mv >= 0;
        const inner = (
          <>
            <span style={{ fontSize: 15, lineHeight: '19px' }}>{x.t}</span>
            <span style={{ fontSize: 14, color: C.ink2 }}>{x.w}</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ flex: 'none', position: 'relative', width: 130, height: 6, borderRadius: 3, background: 'rgba(255,255,255,.06)' }}>
                <span style={{ position: 'absolute', left: '50%', top: -4, bottom: -4, borderLeft: '1px solid rgba(255,255,255,.3)' }} />
                <span style={{ position: 'absolute', top: 0, height: '100%', left: (up ? 50 : 50 - wd).toFixed(1) + '%', width: wd.toFixed(1) + '%', background: up ? C.green : C.red, borderRadius: 3 }} />
              </span>
              <span style={{ fontSize: 14, fontWeight: 600, color: up ? C.green : C.red, whiteSpace: 'nowrap' }}>{pmove(x.mv)}</span>
            </span>
            <span style={{ fontSize: 13, color: x.ld ? (x.ld.p >= 0 ? C.green : C.red) : C.ink2 }}>{x.ld ? `${x.ld.nm} ${pmove(x.ld.p)}` : ''}</span>
            <span style={{ fontSize: 13, color: x.tr ? (x.tr.p >= 0 ? C.green : C.red) : C.ink2 }}>{x.tr ? `${x.tr.nm} ${pmove(x.tr.p)}` : ''}</span>
            <span style={{ fontSize: 13, fontWeight: 600, color: x.yours.length ? C.ink : C.ink2 }}>{x.yours.length ? x.yours.join(' · ') : 'none'}</span>
          </>
        );
        const style = { boxSizing: 'border-box' as const, width: '100%', display: 'grid', gridTemplateColumns: COLS, gap: 12, alignItems: 'center', padding: '11px 0', borderTop: HAIR };
        return onRow
          ? <button key={x.id} type="button" className="bare tnum swb-row" onClick={() => onRow(x.id)} aria-label={`${x.t}, ${x.mv < 0 ? 'down' : 'up'} ${pct(x.mv)}. Show its map`} style={{ ...style, cursor: 'pointer' }}>{inner}</button>
          : <div key={x.id} className="tnum swb-row" style={style}>{inner}</div>;
      })}
    </div>
  );
}

/** The design's squarified treemap (sqf): rows laid along the short side while they stay square. */
function sqf<T extends { v: number }>(items: T[], W: number, H: number) {
  const tot = items.reduce((a, b) => a + b.v, 0) || 1;
  const out: (T & { x: number; y: number; w: number; h: number })[] = [];
  let rest = items.map((it) => ({ it, a: it.v * W * H / tot })), x = 0, y = 0, w = W, hh = H;
  while (rest.length) {
    const sd = Math.min(w, hh);
    const worst = (r: { a: number }[]) => { const sm = r.reduce((a, b) => a + b.a, 0), mx = Math.max(...r.map((q) => q.a)), mn = Math.min(...r.map((q) => q.a)); return Math.max(sd * sd * mx / (sm * sm), sm * sm / (sd * sd * mn)); };
    const row = [rest[0]]; let i = 1;
    while (i < rest.length && worst(row.concat(rest[i])) <= worst(row)) { row.push(rest[i]); i++; }
    const sm = row.reduce((a, b) => a + b.a, 0), tk = sm / sd; let o = 0;
    row.forEach((q) => { const l = q.a / tk; out.push(Object.assign({}, q.it, w >= hh ? { x, y: y + o, w: tk, h: l } : { x: x + o, y, w: l, h: tk })); o += l; });
    if (w >= hh) { x += tk; w -= tk; } else { y += tk; hh -= tk; }
    rest = rest.slice(i);
  }
  return out;
}

const MW0 = 280, MH = 176;

/** The heat maps, biggest move first. */
export function SectorMaps({ secs, held, linked }: { secs: Sec[]; held: Set<string>; linked: Set<string> }) {
  const navigate = useNavigate();
  const narrow = useNarrow();
  const cols = narrow ? 2 : 3;
  const ref = useRef<HTMLDivElement>(null);
  const [cw, setCw] = useState(1000);
  useEffect(() => {
    const el = ref.current;
    if (!el || !window.ResizeObserver) return;
    const ro = new ResizeObserver(() => { const w = Math.round(el.clientWidth); if (w) setCw((p) => (Math.abs(w - p) > 4 ? w : p)); });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const MW = Math.max(160, cw / cols - 40);
  const maps = useMemo(() => secs.slice().sort((a, b) => Math.abs(b.mv) - Math.abs(a.mv)).map((x) => ({
    ...x, tiles: sqf(x.items.filter((q) => q.v > 0).sort((a, b) => b.v - a.v), MW0, MH),
  })), [secs]);
  return (
    <div ref={ref} className="tnum" style={{ display: 'grid', gridTemplateColumns: `repeat(${cols},minmax(0,1fr))` }}>
      {maps.map((x, i) => {
        const c = i % cols;
        return (
          <div key={x.id} data-sec={'map-' + x.id} style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, padding: `16px ${c === cols - 1 ? 0 : 20}px 22px ${c ? 20 : 0}px`, borderTop: HAIR, borderLeft: c ? HAIR : 'none' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
              <span style={{ fontSize: 15, fontWeight: 600 }}>{x.t}</span>
              <span style={{ fontSize: 15, fontWeight: 600, color: x.mv >= 0 ? C.green : C.red, whiteSpace: 'nowrap' }}>{pmove(x.mv)}</span>
            </div>
            <span style={{ fontSize: 12, color: C.ink2 }}>
              {x.w} of the S&amp;P 500
              {x.yours.length ? <> · <span style={{ color: C.ink, fontWeight: 600 }}>yours: {x.yours.join(', ')}</span></> : null}
            </span>
            <div style={{ position: 'relative', height: MH, marginTop: 10 }}>
              {x.tiles.map((q) => {
                const { bg, fg } = tileColors(q.p);
                const wpx = q.w / MW0 * MW, hpx = q.h, big = wpx > 70 && hpx > 44, fs = big ? 14 : 12;
                const p = pmove(q.p), tw = q.t.length * fs * 0.64 + 8, pw = p.length * 11 * 0.58 + 6;
                const showT = wpx >= tw && hpx > 17, showP = showT && wpx >= pw && hpx > 36;
                const ok = linked.has(q.t), aria = `${q.nm} ${p}`;
                return (
                  <button key={q.t} type="button" className="bare swb-heat" aria-label={aria} title={aria}
                    onClick={ok ? () => navigate('/t/' + q.t, { state: { from: 'home' } }) : undefined}
                    style={{ position: 'absolute', left: (q.x / MW0 * 100).toFixed(2) + '%', top: (q.y / MH * 100).toFixed(2) + '%', width: (q.w / MW0 * 100).toFixed(2) + '%', height: (q.h / MH * 100).toFixed(2) + '%', padding: 1.5, cursor: ok ? 'pointer' : 'default' }}>
                    <span style={{ boxSizing: 'border-box', width: '100%', height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 1,
                      border: held.has(q.t) ? '1.5px solid rgba(245,245,247,.6)' : '1px solid rgba(0,0,0,.28)', borderRadius: 5, background: bg, color: fg, overflow: 'hidden' }}>
                      {showT ? <span style={{ maxWidth: '100%', overflow: 'hidden', whiteSpace: 'nowrap', fontSize: fs, fontWeight: 600, lineHeight: 1.1 }}>{q.t}</span> : null}
                      {showP ? <span style={{ fontSize: 11, lineHeight: 1.15 }}>{p}</span> : null}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
