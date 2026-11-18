// The Overview's small shared pieces (SunnyOverview, dark): colours, the section title, the logo disc.
import { useEffect, useState, type ReactNode } from 'react';
import { C } from '../lib/format';

/** Lines between rows (the web's line between sections). */
export const LINE = '1px solid rgba(255,255,255,.14)';
/** The selected range pill and the segmented track. */
export const CHIP = 'rgba(118,118,128,.24)';
/** Green made, red lost, grey neither (half a dollar either side is neither). */
export const cl = (v: number) => (v > 0.5 ? C.green : v < -0.5 ? C.red : C.ink2);

export function H2({ children }: { children: ReactNode }) {
  return <h2 style={{ margin: 0, fontSize: 22, lineHeight: '28px', fontWeight: 700, letterSpacing: '-.01em' }}>{children}</h2>;
}

/** A company logo (public/logos/TICKER.png) at 70% of a 28 px white disc; the ticker when there is no logo. */
export function Logo({ t }: { t: string }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  return (
    <span aria-hidden="true" style={{ width: 28, height: 28, borderRadius: '50%', background: '#FFFFFF', boxShadow: '0 0 0 .5px rgba(0,0,0,.12)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      {bad
        ? <span style={{ fontSize: 8, lineHeight: '10px', fontWeight: 700, color: '#1D1D1F' }}>{t.slice(0, 4)}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" draggable={false} onError={() => setBad(true)}
            style={{ width: '70%', height: '70%', objectFit: 'contain', pointerEvents: 'none' }} />}
    </span>
  );
}
