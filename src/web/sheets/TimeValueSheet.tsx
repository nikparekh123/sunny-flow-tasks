// The Time value sheet (README 5): from the right, 580 wide, sheet glass over a scrim. The total left to earn counts
// up over what was collected, the share captured, Ready to roll (under $0.05 a share left, 90% captured, or in the
// money; in the money first), then one row per name, most left first. Data: the book's REAL sold legs still open,
// brief.timeValue (sunny-home brief.ts; the phone's TimeValueSheet reads the same). Scrim, ✕ or Escape closes.
import { useEffect, useMemo, useRef } from 'react';
import { CountUp } from '../components/CountUp';
import { useHome } from '../lib/data';
import { C, money, price } from '../lib/format';
import { useWeb } from '../lib/state';
import { readyToRoll, strike, tvLegs, type TvLeg } from '../home/rail/model';

const MU = '#98989D';

/** "4 strikes · 109, 107, 108, 112 calls", "3 strikes · 40 calls, 40 puts, 42.5 calls": the legs in the book's order,
    strikes of the same kind run together. */
function strikesLine(ls: TvLeg[]): string {
  const runs: { put: boolean; ks: string[] }[] = [];
  for (const l of ls) {
    const last = runs[runs.length - 1];
    if (last && last.put === l.put) last.ks.push(strike(l.K)); else runs.push({ put: l.put, ks: [strike(l.K)] });
  }
  return `${ls.length} strike${ls.length === 1 ? '' : 's'} · ` + runs.map((r) => r.ks.join(', ') + (r.put ? ' puts' : ' calls')).join(', ');
}

export default function TimeValueSheet() {
  const { book, setTvOpen, mask } = useWeb();
  const { data } = useHome(book);
  const p = data?.payload;
  const close = () => setTvOpen(false);
  const xRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const was = document.activeElement as HTMLElement | null;
    xRef.current?.focus({ preventScroll: true });
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') setTvOpen(false); };
    window.addEventListener('keydown', key);
    // The page behind stays put while the sheet is open.
    const html = document.documentElement, ov = html.style.overflow;
    html.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', key); html.style.overflow = ov; was?.focus?.({ preventScroll: true }); };
  }, [setTvOpen]);

  const m = useMemo(() => {
    const legs = tvLegs(p);
    const tv = p?.brief?.timeValue ?? {};
    const col = Number(tv.col ?? legs.reduce((a, l) => a + l.col, 0));
    const left = Number(tv.tvLeft ?? legs.reduce((a, l) => a + l.tvLeft, 0));
    const cap = Number(tv.tvCap ?? (col > 0 ? Math.round((1 - left / col) * 100) : 0));
    const by = new Map<string, TvLeg[]>();
    for (const l of legs) by.set(l.t, [...(by.get(l.t) ?? []), l]);
    const rows = [...by.values()].map((ls) => {
      const l = ls.reduce((a, x) => a + x.tvLeft, 0), c = ls.reduce((a, x) => a + x.col, 0);
      return { t: ls[0].t, name: ls[0].name, s: strikesLine(ls), left: l, col: c, cp: c > 0 ? Math.round((1 - l / c) * 100) : 0 };
    }).sort((a, b) => b.left - a.left);
    return { any: legs.length > 0, col, left, cap, ready: readyToRoll(legs), rows };
  }, [p]);

  const why = (l: TvLeg) => (l.itm ? { w: l.intr.toFixed(2) + ' ITM', c: C.red }
    : { w: (l.cap >= 90 ? l.cap + '% captured' : price(l.tvPer) + ' a share left'), c: C.orange });

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 30, display: 'flex', justifyContent: 'flex-end' }}>
      <button type="button" aria-label="Close" tabIndex={-1} className="bare scrim" onClick={close} style={{ position: 'absolute', inset: 0 }} />
      <div role="dialog" aria-modal="true" aria-label="Time value" className="glass-sheet"
        style={{ position: 'relative', width: 580, maxWidth: '100%', height: '100%', padding: '28px 30px', display: 'flex', flexDirection: 'column', gap: 20,
          overflowY: 'auto', overscrollBehavior: 'contain' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 28, fontWeight: 700, letterSpacing: '-.02em' }}>Time value</span>
          <button ref={xRef} type="button" onClick={close} aria-label="Close" className="xbtn"
            style={{ width: 32, height: 32, fontSize: 13, color: '#AEAEB2' }}>✕</button>
        </div>
        {!p ? null : !m.any ? (
          // An account with nothing sold: the phone's one line (TimeValueSheet, README 10), no zero bars.
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span style={{ fontSize: 20, fontWeight: 700 }}>Nothing sold yet</span>
            <span style={{ fontSize: 15, color: MU }}>Time value shows here once calls or puts are sold.</span>
          </div>
        ) : (
          <>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <span>
                <CountUp v={mask(money(m.left))} style={{ fontSize: 40, lineHeight: '44px', fontWeight: 700, letterSpacing: '-.025em' }} />{' '}
                <span style={{ fontSize: 15, color: MU }}>left of {mask(money(m.col))} collected</span>
              </span>
              <div style={{ height: 10, borderRadius: 5, background: 'rgba(255,255,255,.1)', overflow: 'hidden' }}>
                <div style={{ width: Math.max(0, Math.min(100, m.cap)) + '%', height: '100%', borderRadius: 5, background: C.green }} />
              </div>
              {/* Worth more than it was sold for: given back, in red without a minus sign (the phone's words). */}
              <span style={{ fontSize: 14, fontWeight: 600, color: m.cap < 0 ? C.red : C.green }}>{Math.abs(m.cap)}% {m.cap < 0 ? 'given back' : 'captured'}</span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontSize: 19, fontWeight: 600 }}>Ready to roll</span>
                {m.ready.length > 0 && <span style={{ fontSize: 13, color: MU }}>{m.ready.length} strike{m.ready.length === 1 ? '' : 's'}</span>}
              </div>
              <span style={{ fontSize: 13, color: MU }}>Under $0.05 a share left, or 90% captured</span>
            </div>
            {m.ready.length === 0 ? (
              <span style={{ fontSize: 15, color: MU }}>Nothing ready yet.</span>
            ) : (
              <div className="noscroll" style={{ flex: 'none', display: 'flex', gap: 10, overflowX: 'auto', margin: '0 -30px', padding: '0 30px 4px' }}>
                {m.ready.map((l, i) => {
                  const r = why(l);
                  return (
                    <div key={l.t + l.K + (l.put ? 'p' : 'c') + i} style={{ flex: 'none', width: 156, display: 'flex', flexDirection: 'column', gap: 8, padding: 14, borderRadius: 18,
                      background: 'rgba(255,255,255,.06)', boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.12)' }}>
                      <span style={{ width: 30, height: 30, borderRadius: '50%', background: 'rgba(255,255,255,.1)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                        fontSize: 9, fontWeight: 700 }}>{l.t}</span>
                      <span style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontSize: 15, fontWeight: 600 }}>{l.name}</span>
                        <span style={{ fontSize: 12, color: MU }}>{strike(l.K)} {l.put ? 'puts' : 'calls'} ×{l.q}</span>
                      </span>
                      <span><span style={{ fontSize: 22, fontWeight: 700 }}>{mask(money(l.tvLeft))}</span> <span style={{ fontSize: 12, color: MU }}>left</span></span>
                      <span style={{ fontSize: 12, fontWeight: 600, color: r.c }}>{r.w}</span>
                    </div>
                  );
                })}
              </div>
            )}
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              {m.rows.map((r) => (
                <div key={r.t} style={{ display: 'grid', fontVariantNumeric: 'tabular-nums', gridTemplateColumns: 'minmax(0,1fr) 100px', gap: 14, alignItems: 'center',
                  padding: '13px 0', borderTop: '1px solid rgba(255,255,255,.08)' }}>
                  <span style={{ display: 'flex', flexDirection: 'column', gap: 7, minWidth: 0 }}>
                    <span><span style={{ fontSize: 16, fontWeight: 600 }}>{r.name}</span> <span style={{ fontSize: 12, color: MU }}>· {r.s}</span></span>
                    <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ flex: 1, height: 6, borderRadius: 3, background: 'rgba(255,255,255,.1)', overflow: 'hidden' }}>
                        <span style={{ display: 'block', width: Math.max(0, Math.min(100, r.cp)) + '%', height: '100%', background: C.green }} />
                      </span>
                      <span style={{ fontSize: 12, fontWeight: 600, color: r.cp < 0 ? C.red : undefined }}>{Math.abs(r.cp)}%</span>
                    </span>
                  </span>
                  <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                    <span style={{ fontSize: 17, fontWeight: 600 }}>{mask(money(r.left))}</span>
                    <span style={{ fontSize: 12, color: MU }}>of {mask(money(r.col))}</span>
                  </span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
