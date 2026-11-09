// The payoff chart (README 2, "Payoff chart"): the P&L at the picked date across today's price ± the zoom, green above
// zero and red below, the book as it is dashed when there are changes, the priced move as a soft band, today's line
// and dot, the orange "makes the most at" line, Walls or Technicals, the zoom capsule, and the axis under it.
// The hover (line, dot, G2 tooltip) paints straight into the page from refs: no React render per mouse move.
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { money, price } from '../lib/format';

export const ZS = [5, 8, 12, 18, 25, 35, 50];
export const FIT = 2;

export interface Line { k: string; x: number; label: string; kind: 'wall' | 'tech' }
interface Props {
  xs: number[]; vW: number[]; vB: number[]; chg: boolean; S0: number; v0: number;
  zi: number; widest: number; setZoom: (z: number) => void;
  band: { l: number; w: number; label: string } | null;
  short: { x: number; label: string } | null;
  lines: Line[];
  privacy: boolean;
}

const lerp = (xs: number[], ys: number[], x: number) => {
  const n = xs.length;
  if (x <= xs[0]) return ys[0];
  if (x >= xs[n - 1]) return ys[n - 1];
  let i = 0, j = n - 1;
  while (j - i > 1) { const k = (i + j) >> 1; if (xs[k] <= x) i = k; else j = k; }
  const w = xs[j] > xs[i] ? (x - xs[i]) / (xs[j] - xs[i]) : 0;
  return ys[i] + (ys[j] - ys[i]) * w;
};
const ud = (v: number, pv: boolean) => (v >= 0 ? 'Up ' : 'Down ') + (pv ? '$•••' : money(v));
const isTyping = (t: EventTarget | null) => {
  const el = t as HTMLElement | null;
  return !!el && (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
};

export function PayoffChart(p: Props) {
  const { xs, vW, vB, chg, S0, v0, zi, widest, setZoom, band, short, lines, privacy } = p;
  const ZR = ZS[zi] / 100, X0 = S0 * (1 - ZR), X1 = S0 * (1 + ZR);
  const g = useMemo(() => {
    let mn = Math.min(0, ...vB, ...vW), mx = Math.max(0, ...vB, ...vW);
    const pad = (mx - mn) * 0.1 || 1; mn -= pad; mx += pad;
    const fy = (v: number) => (mx - v) / (mx - mn), xp = (s: number) => (s - X0) / (X1 - X0);
    const path = (vs: number[]) => xs.map((s, i) => (i ? 'L' : 'M') + (xp(s) * 400).toFixed(1) + ' ' + (fy(vs[i]) * 100).toFixed(1)).join(' ');
    const zy = fy(0) * 100, dW = path(vW);
    return { mn, mx, fy, dW, dB: path(vB), zy, aW: dW + ' L400 ' + zy.toFixed(1) + ' L0 ' + zy.toFixed(1) + ' Z' };
  }, [xs, vW, vB, X0, X1]);

  // What the hover reads, kept current without a render.
  const hv = useRef({ xs, vW, vB, fy: g.fy, chg, S0, X0, X1, privacy });
  hv.current = { xs, vW, vB, fy: g.fy, chg, S0, X0, X1, privacy };
  const box = useRef<HTMLDivElement>(null), line = useRef<HTMLSpanElement>(null), dot = useRef<HTMLSpanElement>(null);
  const tip = useRef<HTMLSpanElement>(null), tPx = useRef<HTMLSpanElement>(null), tA = useRef<HTMLSpanElement>(null), tB = useRef<HTMLSpanElement>(null);
  const zoomRef = useRef({ zi, widest, setZoom });
  zoomRef.current = { zi, widest, setZoom };
  const step = (dz: number) => { const z = zoomRef.current; const k = Math.max(0, Math.min(z.widest, z.zi + dz)); if (k !== z.zi) z.setZoom(k); };

  // Two fingers on a touch screen: one step per 1.3× of the distance across (the phone's pinch).
  const touches = useRef(new Map<number, number>());
  const pinch = useRef<{ d0: number; z0: number } | null>(null);
  const across = () => { const v = [...touches.current.values()]; return v.length >= 2 ? Math.max(8, Math.abs(v[0] - v[1])) : null; };

  const paint = (clientX: number) => {
    const el = box.current, m = hv.current; if (!el) return;
    const r = el.getBoundingClientRect(); if (!r.width) return;
    const f = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
    const S = m.X0 + f * (m.X1 - m.X0), vw = lerp(m.xs, m.vW, S), vb = lerp(m.xs, m.vB, S), y = m.fy(vw), x = (f * 100).toFixed(3) + '%';
    if (line.current) { line.current.style.left = x; line.current.style.opacity = '1'; }
    if (dot.current) Object.assign(dot.current.style, { left: x, top: 'calc(10px + (100% - 20px) * ' + y.toFixed(4) + ')', opacity: '1', background: vw >= 0 ? '#65C466' : '#FF6961' });
    if (tip.current) tip.current.style.transform = f > 0.6 ? 'translateX(calc(-100% - 10px))' : 'translateX(10px)';
    if (tPx.current) tPx.current.textContent = price(S) + ' · ' + (S >= m.S0 ? '↑' : '↓') + Math.abs((S / m.S0 - 1) * 100).toFixed(1) + '%';
    if (tA.current) { tA.current.textContent = (m.chg ? 'With changes · ' : '') + ud(vw, m.privacy); tA.current.style.color = vw >= 0 ? '#65C466' : '#FF6961'; }
    if (tB.current) { tB.current.textContent = m.chg ? 'The book · ' + ud(vb, m.privacy) : ''; tB.current.style.color = vb >= 0 ? '#65C466' : '#FF6961'; tB.current.style.display = m.chg ? 'block' : 'none'; }
  };
  const hide = () => { if (line.current) line.current.style.opacity = '0'; if (dot.current) dot.current.style.opacity = '0'; };

  const onMove = (e: React.PointerEvent) => {
    if (e.pointerType === 'touch' && touches.current.has(e.pointerId)) touches.current.set(e.pointerId, e.clientX);
    if (pinch.current) {
      const d = across();
      if (d) { const z = pinch.current.z0 - Math.floor(Math.log(d / pinch.current.d0) / Math.log(1.3) + 0.5); step(z - zoomRef.current.zi); }
      return;
    }
    paint(e.clientX);
  };
  const onDown = (e: React.PointerEvent) => {
    if (e.pointerType === 'touch') {
      touches.current.set(e.pointerId, e.clientX);
      if (touches.current.size === 2) { pinch.current = { d0: across() ?? 8, z0: zoomRef.current.zi }; hide(); return; }
    }
    if (!pinch.current) paint(e.clientX);
  };
  const onUp = (e: React.PointerEvent) => {
    touches.current.delete(e.pointerId);
    if (touches.current.size === 0) pinch.current = null;
  };
  const onLeave = (e: React.PointerEvent) => { onUp(e); hide(); };

  // A trackpad pinch arrives as a wheel with ctrl held: one step per 1.3× of the gesture's scale.
  useEffect(() => {
    const el = box.current; if (!el) return;
    let acc = 0;
    const wheel = (e: WheelEvent) => {
      if (!e.ctrlKey) return;
      e.preventDefault();
      acc += -e.deltaY * 0.01;
      const L = Math.log(1.3);
      if (acc > L) { acc = 0; step(-1); } else if (acc < -L) { acc = 0; step(1); }
    };
    el.addEventListener('wheel', wheel, { passive: false });
    return () => el.removeEventListener('wheel', wheel);
  }, []);
  // − and + keys zoom out and in (not while typing in the What if, and not the browser's own ⌘ zoom).
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || isTyping(e.target)) return;
      if (e.key === '-' || e.key === '−' || e.key === '_') { e.preventDefault(); step(1); }
      else if (e.key === '+' || e.key === '=') { e.preventDefault(); step(-1); }
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, []);

  // Two labels that would overlap (walls 50¢ apart, say) take the next lane down, 24 under (the phone's lanes).
  const [bw, setBw] = useState(0);
  useLayoutEffect(() => {
    const el = box.current; if (!el) return;
    setBw(el.clientWidth);
    const ro = new ResizeObserver(() => setBw(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const lane = useMemo(() => {
    const out = new Map<string, number>(), placed: { ln: number; a: number; b: number }[] = [];
    for (const x of [...lines].sort((a, b) => a.x - b.x)) {
      const w = x.label.length * 6.4 + 14, c = x.x / 100 * bw, a = c - w / 2, b = c + w / 2;
      let ln = 0;
      while (placed.some((q) => q.ln === ln && a < q.b + 4 && b > q.a - 4)) ln++;
      placed.push({ ln, a, b }); out.set(x.k, ln);
    }
    return out;
  }, [lines, bw]);

  const xpc = (s: number) => ((s - X0) / (X1 - X0) * 100).toFixed(2) + '%';
  const svg = { position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible' } as const;
  const ns = { vectorEffect: 'non-scaling-stroke' } as const;
  const zOn = zi !== FIT;
  return (
    <>
      <div ref={box} onPointerMove={onMove} onPointerDown={onDown} onPointerUp={onUp} onPointerLeave={onLeave} onPointerCancel={onLeave}
        onDoubleClick={() => setZoom(FIT)}
        style={{ position: 'relative', height: 340, cursor: 'crosshair', touchAction: 'pan-y', userSelect: 'none' }}>
        {band && (
          <span style={{ position: 'absolute', top: 0, bottom: 0, left: band.l.toFixed(2) + '%', width: band.w.toFixed(2) + '%', pointerEvents: 'none',
            background: 'linear-gradient(180deg,rgba(255,255,255,0),rgba(255,255,255,.05) 20%,rgba(255,255,255,.05) 80%,rgba(255,255,255,0))' }}>
            <span style={{ position: 'absolute', left: 8, top: 6, fontSize: 11, color: '#98989D', whiteSpace: 'nowrap' }}>{band.label}</span>
          </span>
        )}
        <div style={{ position: 'absolute', left: 0, right: 0, top: 10, height: 'calc(100% - 20px)', pointerEvents: 'none' }}>
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ ...svg, clipPath: `inset(0 0 ${(100 - g.zy).toFixed(2)}% 0)` }}>
            <path d={g.aW} fill="url(#sunGU)" />
            <path d={g.dW} style={{ fill: 'none', stroke: '#65C466', strokeWidth: 2.5, strokeLinejoin: 'round', ...ns }} />
          </svg>
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ ...svg, clipPath: `inset(${g.zy.toFixed(2)}% 0 0 0)` }}>
            <path d={g.aW} fill="url(#sunGD)" />
            <path d={g.dW} style={{ fill: 'none', stroke: '#FF6961', strokeWidth: 2.5, strokeLinejoin: 'round', ...ns }} />
          </svg>
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={svg}>
            <line x1="0" y1={g.zy.toFixed(1)} x2="400" y2={g.zy.toFixed(1)} style={{ stroke: 'rgba(255,255,255,.3)', strokeWidth: 1, ...ns }} />
            <path d={g.dB} style={{ fill: 'none', stroke: 'rgba(255,255,255,.5)', strokeWidth: 1.75, strokeDasharray: '6 5', opacity: chg ? 1 : 0, ...ns }} />
          </svg>
        </div>
        <span style={{ position: 'absolute', left: '50%', top: 0, bottom: 0, borderLeft: '1px solid rgba(255,255,255,.26)', pointerEvents: 'none' }} />
        {short && (
          <span style={{ position: 'absolute', left: short.x.toFixed(2) + '%', top: 0, bottom: 0, width: 0, borderLeft: '1.5px dotted #FF9F0A', pointerEvents: 'none' }}>
            <span style={{ position: 'absolute', left: 0, bottom: 6, transform: 'translateX(-50%)', fontSize: 11, fontWeight: 600, color: '#FF9F0A',
              background: 'rgba(6,8,7,.9)', borderRadius: 6, padding: '2px 6px', whiteSpace: 'nowrap' }}>{short.label}</span>
          </span>
        )}
        {lines.map((x) => x.kind === 'wall' ? (
          <span key={x.k} style={{ position: 'absolute', left: x.x.toFixed(2) + '%', top: 0, bottom: 0, width: 0, borderLeft: '1.5px dashed #86A8F0', pointerEvents: 'none' }}>
            <span style={{ position: 'absolute', left: 0, top: 44 + 24 * (lane.get(x.k) ?? 0), transform: 'translateX(-50%)', fontSize: 11, fontWeight: 600, color: '#86A8F0',
              background: 'rgba(10,14,22,.92)', boxShadow: 'inset 0 0 0 1px rgba(134,168,240,.35)', borderRadius: 6, padding: '2px 7px', whiteSpace: 'nowrap' }}>{x.label}</span>
          </span>
        ) : (
          <span key={x.k} style={{ position: 'absolute', left: x.x.toFixed(2) + '%', top: 0, bottom: 0, width: 0, borderLeft: '1.5px dotted #4CC9D0', pointerEvents: 'none' }}>
            <span style={{ position: 'absolute', left: 0, top: 72 + 24 * (lane.get(x.k) ?? 0), transform: 'translateX(-50%)', fontSize: 11, color: '#4CC9D0',
              background: 'rgba(8,18,20,.92)', boxShadow: 'inset 0 0 0 1px rgba(76,201,208,.35)', borderRadius: 6, padding: '2px 7px', whiteSpace: 'nowrap' }}>{x.label}</span>
          </span>
        ))}
        <span style={{ position: 'absolute', left: '50%', top: 'calc(10px + (100% - 20px) * ' + g.fy(v0).toFixed(3) + ')', width: 14, height: 14, margin: '-7px 0 0 -7px',
          borderRadius: '50%', background: '#FFFFFF', boxShadow: '0 0 0 3px rgba(0,0,0,.6),0 0 16px rgba(255,255,255,.5)', pointerEvents: 'none' }} />
        <span ref={line} style={{ position: 'absolute', left: 0, top: 0, bottom: 0, borderLeft: '1px solid rgba(255,255,255,.4)', pointerEvents: 'none', opacity: 0 }}>
          <span ref={tip} className="g2" style={{ position: 'absolute', top: 12, left: 0, transform: 'translateX(10px)', borderRadius: 12, padding: '8px 12px',
            display: 'flex', flexDirection: 'column', gap: 1, whiteSpace: 'nowrap' }}>
            <span ref={tPx} style={{ fontSize: 12, color: '#98989D' }} />
            <span ref={tA} style={{ fontSize: 15, fontWeight: 600 }} />
            <span ref={tB} style={{ fontSize: 12, display: 'none' }} />
          </span>
        </span>
        <span ref={dot} style={{ position: 'absolute', left: 0, top: 0, width: 10, height: 10, margin: '-5px 0 0 -5px', borderRadius: '50%', background: '#FFFFFF',
          boxShadow: '0 0 0 3px rgba(0,0,0,.55)', pointerEvents: 'none', opacity: 0 }} />
        {/* A quick − − or + + must not read as the chart's double-click (which goes back to ±12%). */}
        <div className="g1" onDoubleClick={(e) => e.stopPropagation()}
          style={{ position: 'absolute', right: 0, top: 0, display: 'flex', alignItems: 'center', borderRadius: 999, cursor: 'default' }}>
          <button type="button" className="bare" aria-label="Zoom out" onClick={() => step(1)}
            style={{ padding: '0 12px', fontSize: 18, lineHeight: '30px', fontWeight: 500 }}>−</button>
          <span style={{ fontSize: 13, fontWeight: 600, padding: '0 2px', whiteSpace: 'nowrap' }}>±{ZS[zi]}%</span>
          <button type="button" className="bare" aria-label="Zoom in" onClick={() => step(-1)}
            style={{ padding: '0 12px', fontSize: 18, lineHeight: '30px', fontWeight: 500 }}>+</button>
          {zOn && (
            <button type="button" className="bare" onClick={() => setZoom(FIT)}
              style={{ padding: '0 12px', borderLeft: '1px solid rgba(255,255,255,.16)', fontSize: 13, lineHeight: '30px', fontWeight: 600 }}>Fit</button>
          )}
        </div>
      </div>
      <div style={{ position: 'relative', height: 16, marginTop: -6, borderTop: '1px solid rgba(255,255,255,.08)', paddingTop: 6 }}>
        {[-1, -0.5, 0, 0.5, 1].map((r, i) => (
          <span key={i} style={{ position: 'absolute', left: xpc(S0 * (1 + r * ZR)), transform: `translateX(${i === 0 ? '0' : i === 4 ? '-100%' : '-50%'})`,
            fontSize: 12, color: '#98989D', whiteSpace: 'nowrap' }}>{price(S0 * (1 + r * ZR))}</span>
        ))}
      </div>
    </>
  );
}
