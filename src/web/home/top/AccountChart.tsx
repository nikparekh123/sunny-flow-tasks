// Home's account block (README 1, items 2 to 4): the account value counting up, the change lines, the 260 tall
// chart with its hover, the ranges and the stats row. The hover paints straight into the page through refs (the
// design's DH.amv / DH.aml), so a mouse, trackpad or finger never re-renders React.
// The read never jumps (handoff 2026-11-18 §3.1): it is one line laid over the lines under the value, which hide
// but keep their room. It never reads while the page scrolls (§5.1): any scroll ends it; the mouse moves a browser
// sends in the 250 ms after a scroll, and moves that did not move, are ignored; a finger starts it after a 160 ms
// hold or a sideways drag past 8 px, a vertical drag is a scroll and cancels it, and lifting the finger ends it.
import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent } from 'react';
import { CountUp } from '../../components/CountUp';
import type { J } from '../../lib/data';
import { C, dollars, money, sgn, wordOf } from '../../lib/format';
import { estWords } from '../../lib/clock';
import { useWeb } from '../../lib/state';
import { changeText, chartModel, RANGES, rangeView, stats, WORDS, type Line, type Range } from './model';
import { acctParts, changeParts, startingOn, statPart, type StatPart } from './parts';

const HAIR = '1px solid rgba(255,255,255,.08)';
/** A stat red for a loss (and grey or ink otherwise) now carries a − instead (handoff 2026-11-25-focus §2.2). */
const loss = (c: string, s: string) => (c === C.red ? sgn(-1, s) : s);

export function AccountChart({ payload, moment }: { payload: J; moment: Line[] }) {
  const { mask, privacy, setTvOpen } = useWeb();
  const m = useMemo(() => chartModel(payload), [payload]);
  const [pick, setPick] = useState<Range>('1M');
  // A range the history does not reach falls back to All (the phone's onAppear rule).
  const range: Range = m && !m.available(pick) ? 'All' : pick;
  const shown = RANGES.filter((r) => (m ? m.available(r) : r === 'All'));
  const v = useMemo(() => (m ? rangeView(m, range) : null), [m, range]);
  const value = payload?.account?.value ?? (m ? m.nav(m.n - 1) : 0);
  const est = estWords(payload?.prices_est);
  /* Together (handoff 2026-11-24 §2.2): each account's value under the number, "Sunny $73.5K · Nicolay $108.9K". */
  const split = (Array.isArray(payload?.split) ? payload.split : []).filter((p: J) => p?.value != null) as { name: string; value: number }[];
  const LC = v ? v.color : C.green;
  /* Together: each account's part of the range's change and of every stat, from that account's own chart and
     figures, the range starting on the same close as the total's (Current Web `acct === 'tog'`). */
  const parts = useMemo(() => acctParts(payload), [payload]);
  const day0 = v && m ? m.days[v.s] : null;
  const pm = useMemo(() => (day0 ? parts.map((p) => ({ p, m: p.m ? startingOn(p.m, day0) : null })) : []), [parts, day0]);

  // The lines under the value: the range's change (deposits out), money paid in or out, then the moment's lines.
  const lines: Line[] = [];
  if (v) {
    const dep = v.deps[v.deps.length - 1];
    const pt = changeParts(parts, (p) => { const x = pm.find((q) => q.p === p)?.m; return x ? rangeView(x, range).change : null; });
    lines.push({ k: 'r', v: changeText(v.change, v.Sv, dep), c: LC, l: WORDS[range], pt });
    // No "$149K deposited past month" line (Nik, 24 Nov 2026: "Remove this"); the change % still counts money paid in.
  }
  lines.push(...moment);

  // ── The hover: everything it touches is found through refs and written directly ──
  const box = useRef<HTMLDivElement>(null);
  const valEl = useRef<HTMLSpanElement>(null), hvalEl = useRef<HTMLSpanElement>(null);
  const linesEl = useRef<HTMLDivElement>(null), hlEl = useRef<HTMLSpanElement>(null);
  const lineEl = useRef<HTMLSpanElement>(null), dateEl = useRef<HTMLSpanElement>(null), dotEl = useRef<HTMLSpanElement>(null);
  const live = useRef({ v, privacy, mask });
  live.current = { v, privacy, mask };
  /** When the page last scrolled (performance.now()), whether a read is on screen, and the finger being watched. */
  const scrolled = useRef(-1e9), reading = useRef(false);
  const finger = useRef<{ id: number; x0: number; y0: number; x: number; on: boolean; timer: number } | null>(null);

  const paint = (clientX: number) => {
    const { v: r, mask: mk } = live.current, b = box.current;
    if (!r || !b) return;
    const rc = b.getBoundingClientRect();
    if (!rc.width) return;
    reading.current = true;
    const f = Math.max(0, Math.min(1, (clientX - rc.left) / rc.width)), k = r.ser.length;
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
    // The lines keep their room while the hover's line sits over them (Nik, 13 Nov 2026: hiding "$498 today"
    // moved the chart under the pointer).
    if (linesEl.current) linesEl.current.style.visibility = 'hidden';
    const hl = hlEl.current;
    if (hl) {
      const a = hl.firstElementChild as HTMLSpanElement | null, b2 = hl.lastElementChild as HTMLSpanElement | null;
      if (a) a.textContent = mk(changeText(ch, r.Sv, r.deps[j]));
      if (b2) b2.textContent = r.labs[j];
      hl.style.display = 'block';
    }
  };
  // Refs only, so one function serves every render and the scroll listener.
  const leave = useCallback(() => {
    reading.current = false;
    if (lineEl.current) lineEl.current.style.opacity = '0';
    if (dotEl.current) dotEl.current.style.opacity = '0';
    if (valEl.current) valEl.current.style.display = 'inline';
    if (hvalEl.current) hvalEl.current.style.display = 'none';
    if (linesEl.current) linesEl.current.style.visibility = 'visible';
    if (hlEl.current) hlEl.current.style.display = 'none';
  }, []);
  const dropFinger = useCallback(() => {
    const t = finger.current;
    if (t) window.clearTimeout(t.timer);
    finger.current = null;
  }, []);
  // A new range or a new book while the pointer rests: start clean.
  useEffect(() => { leave(); }, [range, payload?.chart, leave]);
  // Any scroll (the page or anything in it) ends a read at once and starts the 250 ms the mouse is not listened to.
  useEffect(() => {
    const onScroll = () => {
      scrolled.current = performance.now();
      dropFinger();
      if (reading.current) leave();
    };
    document.addEventListener('scroll', onScroll, { capture: true, passive: true });
    return () => { document.removeEventListener('scroll', onScroll, { capture: true }); dropFinger(); };
  }, [leave, dropFinger]);

  const down = (e: PointerEvent<HTMLDivElement>) => {
    if (e.pointerType !== 'touch') { paint(e.clientX); return; }
    // A finger: wait for a 160 ms hold or a sideways drag before reading.
    dropFinger();
    const t = { id: e.pointerId, x0: e.clientX, y0: e.clientY, x: e.clientX, on: false, timer: 0 };
    t.timer = window.setTimeout(() => { if (finger.current === t) { t.on = true; paint(t.x); } }, 160);
    finger.current = t;
  };
  const move = (e: PointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'touch') {
      const t = finger.current;
      if (!t || t.id !== e.pointerId) return;
      t.x = e.clientX;
      if (!t.on) {
        const dx = Math.abs(e.clientX - t.x0), dy = Math.abs(e.clientY - t.y0);
        if (dy > 8 && dy >= dx) { dropFinger(); leave(); return; }   // a vertical drag is a scroll
        if (!(dx > 8 && dx > dy)) return;                              // not decided yet
        window.clearTimeout(t.timer);
        t.on = true;
      }
      paint(e.clientX);
      return;
    }
    // The mouse: moves right after a scroll, or with no movement, are the page sliding under a still cursor.
    if (performance.now() - scrolled.current < 250 || (!e.movementX && !e.movementY)) return;
    paint(e.clientX);
  };
  const up = (e: PointerEvent<HTMLDivElement>) => { if (e.pointerType === 'touch') { dropFinger(); leave(); } };
  const out = () => { dropFinger(); leave(); };

  const st = stats(payload, m, range);
  // Under each stat on Together, each account by its full name, one a line ("Sunny $4.9K" over "Nicolay $1.8K"): Nik,
  // 24 Nov 2026, did not read "S" and "N"; a column of 150 px holds a name and its figure, not both on one line.
  const stParts = useMemo(() => {
    const out = new Map<string, StatPart[]>();
    if (!pm.length) return out;
    const each = pm.map(({ p, m: x }) => ({ p, st: stats(p.payload, x, range) }));
    for (const k of ['r', 'o', 'tv', 'm', 'i', 'f']) {
      const ps = each.map(({ p, st: s2 }) => statPart(p.name, s2.find((y) => y.k === k)?.n ?? null));
      if (ps.every(Boolean)) out.set(k, ps as StatPart[]);
    }
    return out;
  }, [pm, range]);

  return (
    <>
      <span style={{ marginTop: 6, fontSize: 52, lineHeight: '58px', fontWeight: 700, letterSpacing: '-.035em' }}>
        <span ref={valEl}><CountUp v={mask(dollars(value))} /></span>
        <span ref={hvalEl} className="tnum" style={{ display: 'none' }} />
      </span>
      <div style={{ position: 'relative', marginTop: 4 }}>
        <span ref={hlEl} className="tnum" style={{ display: 'none', position: 'absolute', top: 0, left: 0, fontSize: 15, whiteSpace: 'nowrap' }}>
          <span style={{ fontWeight: 500 }} /> <span style={{ color: C.ink2 }} />
        </span>
        <div ref={linesEl} className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {split.length > 1 && (
            <span style={{ fontSize: 15, color: C.ink2 }}>{split.map((p) => `${p.name} ${mask(money(p.value))}`).join(' · ')}</span>
          )}
          {lines.map((x) => (
            <span key={x.k} style={{ fontSize: 15 }}>
              <span style={{ fontWeight: 500, color: wordOf(x.c, 15) }}>{mask(x.v)}</span> <span style={{ color: C.ink2 }}>{x.l}{x.pt ? ' · ' + mask(x.pt) : ''}</span>
            </span>
          ))}
          {/* Before the open and after the close: the value is priced from pre-market or after-hours trades. */}
          {est && <span style={{ fontSize: 13, lineHeight: '18px', color: C.ink3 }}>{est}</span>}
        </div>
      </div>

      <div ref={box} onPointerMove={move} onPointerDown={down} onPointerUp={up} onPointerLeave={out} onPointerCancel={out}
        style={{ position: 'relative', height: 260, marginTop: 20, cursor: 'crosshair', touchAction: 'pan-y', userSelect: 'none', WebkitUserSelect: 'none' }}>
        {v && (
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true"
            style={{ position: 'absolute', left: 0, top: 14, width: '100%', height: 'calc(100% - 28px)', overflow: 'visible', pointerEvents: 'none' }}>
            <line x1="0" y1={v.y0.toFixed(2)} x2="400" y2={v.y0.toFixed(2)}
              style={{ stroke: 'rgba(255,255,255,.18)', strokeWidth: 1, strokeDasharray: '2 5', vectorEffect: 'non-scaling-stroke' }} />
            {/* One plain 2 px line, as the Positions Price chart (Nik, 13 Nov 2026: no see-through outline under it). */}
            <path d={v.path} style={{ fill: 'none', stroke: LC, strokeWidth: 2, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
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
              style={{ padding: '10px 0 9px', fontSize: 14, fontWeight: 500, color: on ? wordOf(LC, 14) : C.ink2, boxShadow: on ? `inset 0 -2px 0 ${LC}` : 'none' }}>
              {r}
            </button>
          );
        })}
      </div>

      {/* The stats row is a grid (handoff 2026-11-24 §3): when it wraps, the rows line up (Current Web: auto-fill
          columns of at least 150, 16 by 24 apart). On Together each stat has its accounts' parts under it. */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(150px,1fr))', gap: '16px 24px', padding: '18px 0', borderBottom: HAIR }}>
        {st.map((x) => {
          const style = { cursor: x.tv ? 'pointer' : 'default', display: 'flex', flexDirection: 'column' as const, gap: 2, minWidth: 0, textAlign: 'left' as const };
          const pt = stParts.get(x.k);
          const inner = (
            <>
              <span style={{ fontSize: 12, color: C.ink2, whiteSpace: 'nowrap' }}>{x.l}</span>
              <span className="tnum" style={{ fontSize: 19, lineHeight: '24px', fontWeight: 500, color: wordOf(x.c, 19) }}>{loss(x.c, mask(x.v))}</span>
              {pt && (
                <span className="tnum" style={{ display: 'flex', flexDirection: 'column', fontSize: 12, lineHeight: '16px', color: '#8C8C8C', whiteSpace: 'nowrap' }}>
                  {pt.map((p) => <span key={p.ini}>{p.ini} <span style={{ color: wordOf(p.c, 12) }}>{loss(p.c, mask(p.v))}</span></span>)}
                </span>
              )}
            </>
          );
          const ptA = pt ? ', ' + pt.map((p) => `${p.ini} ${mask(p.v)}`).join(', ') : '';
          // Time value opens its receipt (README §3.5); its value is the receipt's time value left by Friday.
          return x.tv
            ? <button key={x.k} type="button" className="bare" onClick={() => setTvOpen(true)} aria-label={`Time value, ${mask(x.v)} left by Friday${ptA}, opens the receipt`} title="Left by Friday" style={style}>{inner}</button>
            : <div key={x.k} style={style}>{inner}</div>;
        })}
      </div>
      <style>{'.sw .swa-rg:hover{color:#F2F2F2!important}'}</style>
    </>
  );
}
