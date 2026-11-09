// Home's account block (README 1, items 2 to 4): the account value counting up, the change lines, the 260 tall
// chart with its hover, the ranges and the stats row. The hover paints straight into the page through refs (the
// design's DH.amv / DH.aml), so a mouse, trackpad or finger never re-renders React.
import { useEffect, useMemo, useRef, useState, type PointerEvent } from 'react';
import { CountUp } from '../../components/CountUp';
import type { J } from '../../lib/data';
import { C, dollars, money } from '../../lib/format';
import { useWeb } from '../../lib/state';
import { changeText, chartModel, RANGES, rangeView, stats, WORDS, type Line, type Range } from './model';

const HAIR = '1px solid rgba(255,255,255,.08)';

export function AccountChart({ payload, moment }: { payload: J; moment: Line[] }) {
  const { mask, privacy, setTvOpen } = useWeb();
  const m = useMemo(() => chartModel(payload), [payload]);
  const [pick, setPick] = useState<Range>('1M');
  // A range the history does not reach falls back to All (the phone's onAppear rule).
  const range: Range = m && !m.available(pick) ? 'All' : pick;
  const shown = RANGES.filter((r) => (m ? m.available(r) : r === 'All'));
  const v = useMemo(() => (m ? rangeView(m, range) : null), [m, range]);
  const value = payload?.account?.value ?? (m ? m.nav(m.n - 1) : 0);
  const LC = v ? v.color : C.green;

  // The lines under the value: the range's change (deposits out), money paid in or out, then the moment's lines.
  const lines: Line[] = [];
  if (v) {
    lines.push({ k: 'r', v: changeText(v.change, v.Sv), c: LC, l: WORDS[range] });
    const dep = v.deps[v.deps.length - 1];
    // The phone's deposit line (AccountChart.depositLine): a deposit is not a gain, so it is named on its own.
    if (Math.abs(dep) >= 1) lines.push({ k: 'd', v: money(dep), c: C.ink, l: `${dep > 0 ? 'deposited' : 'withdrawn'} ${WORDS[range]}` });
  }
  lines.push(...moment);

  // ── The hover: everything it touches is found through refs and written directly ──
  const box = useRef<HTMLDivElement>(null);
  const valEl = useRef<HTMLSpanElement>(null), hvalEl = useRef<HTMLSpanElement>(null);
  const linesEl = useRef<HTMLDivElement>(null), hlEl = useRef<HTMLSpanElement>(null);
  const lineEl = useRef<HTMLSpanElement>(null), dateEl = useRef<HTMLSpanElement>(null), dotEl = useRef<HTMLSpanElement>(null);
  const live = useRef({ v, privacy, mask });
  live.current = { v, privacy, mask };

  const move = (e: PointerEvent<HTMLDivElement>) => {
    const { v: r, mask: mk } = live.current, b = box.current;
    if (!r || !b) return;
    const rc = b.getBoundingClientRect();
    if (!rc.width) return;
    const f = Math.max(0, Math.min(1, (e.clientX - rc.left) / rc.width)), k = r.ser.length;
    // The line and the dot follow the pointer exactly; the numbers are the nearest day's close.
    const fi = f * Math.max(0, k - 1), i0 = Math.min(Math.max(0, k - 2), Math.floor(fi)), t = fi - i0;
    const y = k > 1 ? r.ys[i0] + (r.ys[i0 + 1] - r.ys[i0]) * t : r.ys[0];
    const j = Math.round(fi), val = r.ser[j], ch = val - r.Sv - r.deps[j], x = (f * 100).toFixed(3) + '%';
    const ln = lineEl.current, dt = dateEl.current, dot = dotEl.current;
    if (ln) { ln.style.left = x; ln.style.opacity = '1'; }
    if (dot) { dot.style.left = x; dot.style.top = `calc(14px + (100% - 28px) * ${(y / 100).toFixed(4)})`; dot.style.opacity = '1'; }
    if (dt) { dt.textContent = r.labs[j]; dt.style.transform = `translateX(${f > 0.85 ? '-100%' : f < 0.15 ? '0%' : '-50%'})`; }
    if (valEl.current) valEl.current.style.display = 'none';
    if (hvalEl.current) { hvalEl.current.textContent = mk(dollars(val)); hvalEl.current.style.display = 'inline'; }
    if (linesEl.current) linesEl.current.style.display = 'none';
    const hl = hlEl.current;
    if (hl) {
      const a = hl.firstElementChild as HTMLSpanElement | null, b2 = hl.lastElementChild as HTMLSpanElement | null;
      if (a) { a.textContent = mk(changeText(ch, r.Sv)); a.style.color = ch >= 0 ? C.green : C.red; }
      if (b2) b2.textContent = r.labs[j];
      hl.style.display = 'block';
    }
  };
  const leave = () => {
    if (lineEl.current) lineEl.current.style.opacity = '0';
    if (dotEl.current) dotEl.current.style.opacity = '0';
    if (valEl.current) valEl.current.style.display = 'inline';
    if (hvalEl.current) hvalEl.current.style.display = 'none';
    if (linesEl.current) linesEl.current.style.display = 'flex';
    if (hlEl.current) hlEl.current.style.display = 'none';
  };
  // A new range or a new book while the pointer rests: start clean.
  useEffect(() => { leave(); }, [range, payload?.chart]);

  const st = stats(payload, m, range);

  return (
    <>
      <span style={{ marginTop: 6, fontSize: 52, lineHeight: '58px', fontWeight: 700, letterSpacing: '-.035em' }}>
        <span ref={valEl}><CountUp v={mask(dollars(value))} /></span>
        <span ref={hvalEl} className="tnum" style={{ display: 'none' }} />
      </span>
      <span ref={hlEl} className="tnum" style={{ display: 'none', marginTop: 4, fontSize: 15 }}>
        <span style={{ fontWeight: 600 }} /> <span style={{ color: C.ink2 }} />
      </span>
      <div ref={linesEl} className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 2, marginTop: 4 }}>
        {lines.map((x) => (
          <span key={x.k} style={{ fontSize: 15 }}>
            <span style={{ fontWeight: 600, color: x.c }}>{mask(x.v)}</span> <span style={{ color: C.ink2 }}>{x.l}</span>
          </span>
        ))}
      </div>

      <div ref={box} onPointerMove={move} onPointerDown={move} onPointerLeave={leave} onPointerCancel={leave}
        style={{ position: 'relative', height: 260, marginTop: 20, cursor: 'crosshair', touchAction: 'pan-y', userSelect: 'none', WebkitUserSelect: 'none' }}>
        {v && (
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true"
            style={{ position: 'absolute', left: 0, top: 14, width: '100%', height: 'calc(100% - 28px)', overflow: 'visible', pointerEvents: 'none' }}>
            <line x1="0" y1={v.y0.toFixed(2)} x2="400" y2={v.y0.toFixed(2)}
              style={{ stroke: 'rgba(255,255,255,.18)', strokeWidth: 1, strokeDasharray: '2 5', vectorEffect: 'non-scaling-stroke' }} />
            <path d={v.path} style={{ fill: 'none', stroke: v.up ? 'rgba(101,196,102,.18)' : 'rgba(255,105,97,.18)', strokeWidth: 10, vectorEffect: 'non-scaling-stroke' }} />
            <path d={v.path} style={{ fill: 'none', stroke: LC, strokeWidth: 2, strokeLinejoin: 'round', vectorEffect: 'non-scaling-stroke' }} />
          </svg>
        )}
        <span ref={lineEl} style={{ position: 'absolute', left: 0, top: 0, bottom: 0, borderLeft: '1px solid rgba(255,255,255,.35)', pointerEvents: 'none', opacity: 0 }}>
          <span ref={dateEl} style={{ position: 'absolute', top: -6, left: 0, fontSize: 12, fontWeight: 500, color: C.ink3, whiteSpace: 'nowrap', padding: '0 6px' }} />
        </span>
        <span ref={dotEl} style={{ position: 'absolute', left: 0, top: 0, width: 11, height: 11, margin: '-5.5px 0 0 -5.5px', borderRadius: '50%',
          background: LC, boxShadow: '0 0 0 3px rgba(0,0,0,.6)', pointerEvents: 'none', opacity: 0 }} />
      </div>

      <div role="tablist" aria-label="Chart range" style={{ display: 'flex', gap: 26, borderBottom: '1px solid rgba(255,255,255,.14)' }}>
        {shown.map((r) => {
          const on = r === range;
          return (
            <button key={r} type="button" role="tab" aria-selected={on} className="bare swa-rg" onClick={() => setPick(r)}
              style={{ padding: '10px 0 9px', fontSize: 14, fontWeight: on ? 600 : 500, color: on ? LC : C.ink2, boxShadow: on ? `inset 0 -2px 0 ${LC}` : 'none' }}>
              {r}
            </button>
          );
        })}
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', rowGap: 14, padding: '18px 0', borderBottom: HAIR }}>
        {st.map((x, i) => {
          const style = { cursor: x.tv ? 'pointer' : 'default', display: 'flex', flexDirection: 'column' as const, gap: 2,
            padding: `0 24px 0 ${i ? '24px' : '0'}`, borderLeft: i ? HAIR : 'none' };
          const inner = (
            <>
              <span style={{ fontSize: 12, color: C.ink2, whiteSpace: 'nowrap' }}>{x.l}</span>
              <span className="tnum" style={{ fontSize: 19, lineHeight: '24px', fontWeight: 600, color: x.c }}>{mask(x.v)}</span>
            </>
          );
          // Time value opens its sheet (README 5); its value is what is left to earn.
          return x.tv
            ? <button key={x.k} type="button" className="bare" onClick={() => setTvOpen(true)} aria-label={`Time value, left to earn, ${mask(x.v)}`} style={style}>{inner}</button>
            : <div key={x.k} style={style}>{inner}</div>;
        })}
      </div>
      <style>{'.sw .swa-rg:hover{color:#F5F5F7!important}'}</style>
    </>
  );
}
