// The economy readings (Web Dark v2, `b.isEcon`, soft tiles): the filter "All 12 · Worth watching · 3 · New since
// yesterday · 2" with its note, then three soft tiles a row, each the reading's name and flag, the latest value,
// its last four readings as bars (the latest in ink) with a reference line where the doc names one, the values and
// dates under them, the trend and what it means. Data: the brief doc's `economy.indicators` (all twelve, FRED via
// econ-sync, worth watching first then new since yesterday), falling back to the card's own featured readings.
import { useState } from 'react';
import type { J } from '../../lib/data';
import { C, clean } from '../../lib/format';
import { isNeg, numOf, unsign } from './util';

type Filter = 'all' | 'w' | 'n';
const SEG_ON = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';
/** The readings that cross zero are drawn from a zero line (the design's 'zero' kind). */
const ZERO = new Set(['curve_10y3m', 'stress_index', 'sahm', 'lending_standards']);

const flagOf = (e: J): Filter | null => (e.tagStyle === 'yellow' || /worth watching/i.test(e.tag ?? '') ? 'w' : /new since/i.test(e.tag ?? '') ? 'n' : null);

export function readings(doc: J, card: J): J[] {
  const all: J[] = doc?.economy?.indicators?.length ? doc.economy.indicators : card?.indicators ?? [];
  const rank = (e: J) => (flagOf(e) === 'w' ? 0 : flagOf(e) === 'n' ? 1 : 2);
  return all.map((e, i) => ({ e, i })).sort((a, b) => rank(a.e) - rank(b.e) || a.i - b.i).map((x) => x.e);
}

export default function Economy({ list }: { list: J[] }) {
  const [f, setF] = useState<Filter>('all');
  const nW = list.filter((e) => flagOf(e) === 'w').length, nN = list.filter((e) => flagOf(e) === 'n').length;
  const chips: [Filter, string][] = [['all', `All ${list.length}`], ...(nW ? [['w', `Worth watching · ${nW}`] as [Filter, string]] : []), ...(nN ? [['n', `New since yesterday · ${nN}`] as [Filter, string]] : [])];
  const shown = list.filter((e) => f === 'all' || flagOf(e) === f);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
        <div role="radiogroup" aria-label="Readings" style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
          {chips.map(([k, l]) => {
            const on = f === k;
            return (
              <button key={k} type="button" role="radio" aria-checked={on} className="bare swb-chip" onClick={() => setF(k)}
                style={{ padding: '6px 14px', borderRadius: 999, fontSize: 14, lineHeight: '18px', fontWeight: on ? 600 : 500, color: on ? '#FFFFFF' : C.ink,
                  background: on ? 'rgba(255,255,255,.20)' : 'transparent', boxShadow: on ? SEG_ON : 'none', whiteSpace: 'nowrap' }}>
                {l}
              </button>
            );
          })}
        </div>
        <span style={{ fontSize: 13, color: C.ink2 }}>Worth watching first, then what is new since yesterday</span>
      </div>
      <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12 }}>
        {shown.map((e) => <Tile key={e.id ?? e.name} e={e} />)}
      </div>
    </div>
  );
}

function Tile({ e }: { e: J }) {
  const fl = flagOf(e);
  const pts: J[] = e.chart?.points ?? [];
  const vals = pts.map((p) => numOf(p.value));
  const L = pts.length - 1;
  const mk = clean(e.chart?.marker);
  const refV = mk ? numOf(mk.split('·').pop()) : NaN;
  const ref = isFinite(refV) ? { v: refV, l: mk.replace(/([·]\s*)[+\-−](?=\d)/, '$1') } : null;
  const zero = ZERO.has(e.id) || vals.some((v) => v <= 0);
  const lines: { k: string; top: number; bd: string; l?: string; lt?: number }[] = [];
  let geo: [number, number][] = [];
  if (vals.length && vals.every(isFinite)) {
    if (zero) {
      const dmax = Math.max(0, ...vals, ref ? ref.v : 0), dmin = Math.min(0, ...vals, ref ? ref.v : 0);
      const yv = (x: number) => 10 + (dmax - x) / ((dmax - dmin) || 1) * 80, y0 = yv(0);
      lines.push({ k: 'z', top: y0, bd: '1px solid rgba(255,255,255,.28)' });
      if (ref) { const ry = yv(ref.v); lines.push({ k: 'r', top: ry, bd: '1px dashed rgba(255,255,255,.28)', l: ref.l, lt: ry < 30 ? 2 : -16 }); }
      geo = vals.map((x) => { const y = yv(x), hh = Math.abs(y - y0); return hh < 3 ? [y0 - 1.5, 3] : x > 0 ? [y, hh] : [y0, hh]; });
    } else {
      const lo = Math.min(...vals, ref ? ref.v : Infinity), hi = Math.max(...vals, ref ? ref.v : -Infinity);
      const hf = (x: number) => (hi === lo ? 55 : 22 + 66 * (x - lo) / (hi - lo));
      if (ref) { const ry = 96 - hf(ref.v); lines.push({ k: 'r', top: ry, bd: '1px dashed rgba(255,255,255,.28)', l: ref.l, lt: ry < 30 ? 2 : -16 }); }
      geo = vals.map((x) => [96 - hf(x), hf(x)]);
    }
  }
  const neg = isNeg(e.value);
  return (
    <div className="soft-econ" style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8, minHeight: 20 }}>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{clean(e.name ?? e.label)}</span>
        {fl ? (
          <span style={{ flex: 'none', borderRadius: 999, padding: '2px 9px', fontSize: 11, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap',
            background: fl === 'w' ? 'rgba(255,159,10,.16)' : 'rgba(255,255,255,.10)', color: fl === 'w' ? C.orange : C.ink }}>{clean(e.tag)}</span>
        ) : null}
      </div>
      <span style={{ fontSize: 30, lineHeight: '34px', fontWeight: 600, letterSpacing: '-.02em', color: neg ? C.red : C.ink }}>{unsign(e.value)}</span>
      {pts.length ? (
        <>
          <div role="img" aria-label={clean(e.chartAria)} style={{ position: 'relative', height: 56, borderBottom: '1px solid rgba(255,255,255,.12)' }}>
            {geo.map(([top, h], i) => (
              <span key={i} style={{ position: 'absolute', left: (i * 25 + 5) + '%', width: '15%', top: top.toFixed(1) + '%', height: h.toFixed(1) + '%', borderRadius: 3, background: i === L ? '#F5F5F7' : 'rgba(255,255,255,.16)' }} />
            ))}
            {lines.map((z) => (
              <span key={z.k} style={{ position: 'absolute', left: 0, right: 0, top: z.top.toFixed(1) + '%', borderTop: z.bd }}>
                {z.l ? <span style={{ position: 'absolute', right: 0, top: z.lt, fontSize: 11, lineHeight: '14px', color: C.ink3, background: 'rgba(6,8,7,.9)', borderRadius: 4, padding: '0 4px', whiteSpace: 'nowrap' }}>{z.l}</span> : null}
              </span>
            ))}
          </div>
          <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))' }} aria-hidden="true">
            {pts.map((p, i) => (
              <span key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', paddingLeft: '5%' }}>
                <span style={{ fontSize: 12, fontWeight: i === L ? 700 : 400, color: isNeg(p.value) ? C.red : C.ink }}>{unsign(p.value)}</span>
                <span style={{ fontSize: 11, color: C.ink2, whiteSpace: 'nowrap' }}>{clean(p.label)}</span>
              </span>
            ))}
          </div>
        </>
      ) : null}
      {e.trend ? <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 600 }}>{clean(e.trend)}</span> : null}
      {e.note ? <span style={{ fontSize: 13, lineHeight: '19px', color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>{clean(e.note)}</span> : null}
    </div>
  );
}

/** Out today (the doc's outToday: readings that landed today). The design's table wants each release's time,
    prior, forecast and actual, which the doc does not carry; the readings it does carry are drawn as the same
    soft tiles under the design's block head. */
export function OutToday({ card }: { card: J }) {
  const list: J[] = card.indicators ?? [];
  if (!list.length) return null;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, paddingTop: 16, borderTop: '1px solid rgba(255,255,255,.14)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>{clean(card.title) || 'Out today'}</span>
      </div>
      <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12 }}>
        {list.map((e) => <Tile key={e.id ?? e.name} e={e} />)}
      </div>
    </div>
  );
}
