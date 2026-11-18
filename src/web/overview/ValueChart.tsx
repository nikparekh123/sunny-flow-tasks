// Overview §1 · both accounts as one line (SunnyOverview 165): "Together · Wed Nov 18", today's change, the value
// exact, the range's change (deposits inside the range left out) and each account's part; then the chart and the
// ranges. The line is drawn net of the money put in since the range's first point, so it never jumps when a book
// starts or a deposit lands; the figures above it stay the real totals.
// The read never runs while the page scrolls (§5.1): any scroll ends it; the mouse moves a browser sends in the
// 250 ms after a scroll, and moves that did not move, are ignored; a finger starts it after a 160 ms hold or a
// sideways drag past 8 px, a vertical drag is a scroll and cancels it, and lifting the finger ends it.
import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent } from 'react';
import { CountUp } from '../components/CountUp';
import { C, arrow, dollars, money, pct } from '../lib/format';
import { useWeb } from '../lib/state';
import { CHIP, cl } from './ui';
import { RANGES, WORDS, dayLabel, points, rangeStarts, rangeView, type Range, type Together } from './together';

export function TogetherChart({ t }: { t: Together }) {
  const { mask } = useWeb();
  const pts = useMemo(() => points(t), [t]);
  const starts = useMemo(() => rangeStarts(pts, t.today), [pts, t.today]);
  const [pick, setPick] = useState<Range>('1M');
  const rg: Range = starts[pick] != null ? pick : starts['1M'] != null ? '1M' : 'All';
  const v = useMemo(() => rangeView(pts, starts[rg] ?? 0), [pts, starts, rg]);
  const n = v.pts.length;

  // ── The read: the index under the pointer, or null ──
  const [at, setAt] = useState<number | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const nRef = useRef(n);
  nRef.current = n;
  const scrolled = useRef(-1e9);
  const finger = useRef<{ id: number; x0: number; y0: number; x: number; on: boolean; timer: number } | null>(null);
  const read = (clientX: number) => {
    const b = box.current;
    if (!b) return;
    const r = b.getBoundingClientRect();
    if (!r.width) return;
    const f = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
    setAt(Math.round(f * Math.max(0, nRef.current - 1)));
  };
  const drop = useCallback(() => {
    const f = finger.current;
    if (f) window.clearTimeout(f.timer);
    finger.current = null;
  }, []);
  useEffect(() => {
    const onScroll = () => { scrolled.current = performance.now(); drop(); setAt(null); };
    document.addEventListener('scroll', onScroll, { capture: true, passive: true });
    return () => { document.removeEventListener('scroll', onScroll, { capture: true }); drop(); };
  }, [drop]);
  useEffect(() => { setAt(null); }, [rg]);

  const down = (e: PointerEvent<HTMLDivElement>) => {
    if (e.pointerType !== 'touch') { read(e.clientX); return; }
    drop();
    const el = e.currentTarget, f = { id: e.pointerId, x0: e.clientX, y0: e.clientY, x: e.clientX, on: false, timer: 0 };
    f.timer = window.setTimeout(() => {
      if (finger.current !== f) return;
      f.on = true;
      try { el.setPointerCapture(f.id); } catch { /* gone */ }
      read(f.x);
    }, 160);
    finger.current = f;
  };
  const move = (e: PointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'touch') {
      const f = finger.current;
      if (!f || f.id !== e.pointerId) return;
      f.x = e.clientX;
      if (!f.on) {
        const dx = Math.abs(e.clientX - f.x0), dy = Math.abs(e.clientY - f.y0);
        if (dy > 8 && dy >= dx) { drop(); setAt(null); return; }   // a vertical drag is a scroll
        if (!(dx > 8 && dx > dy)) return;                           // not decided yet
        window.clearTimeout(f.timer);
        f.on = true;
        try { e.currentTarget.setPointerCapture(f.id); } catch { /* gone */ }
      }
      read(e.clientX);
      return;
    }
    // The mouse: moves right after a scroll, or with no movement, are the page sliding under a still cursor.
    if (performance.now() - scrolled.current < 250 || (!e.movementX && !e.movementY)) return;
    read(e.clientX);
  };
  const up = (e: PointerEvent<HTMLDivElement>) => { if (e.pointerType === 'touch') { drop(); setAt(null); } };
  const out = () => { drop(); setAt(null); };

  // ── The figures: the real totals at the point, the change net of the money put in since the first point ──
  const on = at != null && n > 0;
  const j = on ? Math.min(at!, n - 1) : n - 1;
  const p = v.pts[j], p0 = v.pts[0];
  const change = n ? v.net[j] - v.net[0] : 0;
  const lc = change >= 0 ? C.green : C.red;
  const yr = rg === '1Y' || rg === 'All';
  const today = t.live ? t.live.today : null;
  const head = on ? dayLabel(p.d, yr) : `Together · ${dayLabel(t.today)}`;
  const words = on ? `from ${dayLabel(p0.d, yr)}` : WORDS[rg];
  const parts = p ? t.names.map((nm, i) => ({ nm, v: p.per[i] })).filter((x) => x.v != null) : [];
  // The percentage is of the money at work: the first total plus what was put in after it (Nicolay's $49K, $50K
  // and $50K would otherwise read as a much bigger move).
  const den = p0 ? p0.v + v.cum[j] : 0;
  const chText = `${arrow(change)} ${money(change)} · ${pct(den ? (Math.abs(change) / Math.abs(den)) * 100 : 0)}`;
  const value = p ? p.v : 0;
  const hx = n > 1 ? ((j / (n - 1)) * 100).toFixed(2) + '%' : '100%';
  const hy = n ? v.y(v.net[j]).toFixed(2) + '%' : '0%';
  const shown = RANGES.filter((r) => starts[r] != null);
  const aria = n ? `Both accounts together, ${WORDS[rg]}: ${mask(dollars(p0.v))} to ${mask(dollars(v.pts[n - 1].v))}. Drag to read a day.` : '';

  return (
    <section aria-label="Both accounts together" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: C.ink2 }}>{head}</span>
          {today != null && (
            <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 600, color: cl(today), whiteSpace: 'nowrap' }}>
              {mask(`${arrow(today)} ${money(today)} today`)}
            </span>
          )}
        </div>
        <span style={{ fontSize: 34, lineHeight: '40px', fontWeight: 800, letterSpacing: '-.02em' }}>
          {/* The count-up stays mounted under a read, so ending a read never counts up again. */}
          <span style={{ display: on ? 'none' : 'inline' }}><CountUp v={mask(dollars(value))} /></span>
          {on && <span>{mask(dollars(value))}</span>}
        </span>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500, color: C.ink2 }}>
          <span style={{ fontWeight: 700, color: lc }}>{mask(chText)}</span> {words}
        </span>
        <span style={{ display: 'flex', flexWrap: 'wrap', gap: '2px 16px', paddingTop: 2, fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2 }}>
          {parts.map((x) => (
            <span key={x.nm}>{x.nm} <span style={{ fontWeight: 600, color: C.ink }}>{mask(money(x.v))}</span></span>
          ))}
        </span>
      </div>

      <div ref={box} role="img" aria-label={aria} onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerLeave={out} onPointerCancel={out}
        style={{ position: 'relative', height: 'clamp(180px,24cqw,300px)', marginTop: 8, touchAction: 'pan-y', cursor: 'crosshair',
          userSelect: 'none', WebkitUserSelect: 'none' }}>
        {n > 0 && (
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true"
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible', pointerEvents: 'none' }}>
            <line x1="0" x2="400" y1={v.y(v.net[0]).toFixed(2)} y2={v.y(v.net[0]).toFixed(2)}
              style={{ stroke: C.ink2, strokeOpacity: 0.45, strokeWidth: 1.5, strokeDasharray: '0 5', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
            {on && <path d={v.path(j, n - 1)} style={{ fill: 'none', stroke: lc, strokeOpacity: 0.22, strokeWidth: 2, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />}
            <path d={v.path(0, j)} style={{ fill: 'none', stroke: lc, strokeWidth: 2, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
          </svg>
        )}
        {on && (
          <>
            <span aria-hidden="true" style={{ position: 'absolute', top: 0, bottom: 0, left: hx, borderLeft: `1px solid ${C.ink2}`, opacity: 0.35, pointerEvents: 'none' }} />
            <span aria-hidden="true" style={{ position: 'absolute', left: hx, top: hy, width: 10, height: 10, margin: '-5px 0 0 -5px', borderRadius: '50%',
              background: lc, boxShadow: '0 0 0 2.5px #000000', pointerEvents: 'none' }} />
          </>
        )}
      </div>

      {/* The ranges sit at the design's pitch (seven to 440 px); a range the closes do not reach is left out. */}
      <div role="radiogroup" aria-label="Range" style={{ display: 'grid', gridTemplateColumns: 'repeat(7,minmax(0,1fr))', maxWidth: 440, margin: '0 -6px' }}>
        {shown.map((r) => {
          const sel = r === rg;
          return (
            <button key={r} type="button" role="radio" aria-checked={sel} className="bare ov-rg" onClick={() => { setPick(r); setAt(null); }}
              style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 44 }}>
              <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minWidth: 40, height: 30, padding: '0 8px', borderRadius: 15,
                background: sel ? CHIP : 'transparent', fontSize: 13, lineHeight: '16px', fontWeight: sel ? 700 : 600, color: sel ? C.ink : C.ink2 }}>{r}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}
