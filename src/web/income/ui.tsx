// Income's shared pieces (SunnyIncome.dc.html): the logo disc (the banner, the calendar), the rung row and the delta
// line (Income today, README §1.2 `rung` need). Dark only, as the rest of the web.
import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';
import { Dot } from '../lib/focus';
import { wordOf } from '../lib/format';
import { ln, MU, RED, type Flip, type Line } from './model';

/** A white disc with the company's logo at 60% (public/logos/TICKER.png); the ticker in the circle when there is no
    logo file. `ring` is an inset shadow, so a dot pinned to the disc never moves. */
export function Disc({ t, size, fs, ring, pct = 60, style, children }: { t: string; size: number; fs: number; ring?: string; pct?: number; style?: CSSProperties; children?: ReactNode }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  return (
    <span aria-hidden="true" style={{ position: 'relative', flex: 'none', width: size, height: size, boxSizing: 'border-box', borderRadius: '50%', background: '#FAFAFA',
      boxShadow: ring, display: 'flex', alignItems: 'center', justifyContent: 'center', ...style }}>
      {bad
        ? <span style={{ fontSize: fs, lineHeight: 1, fontWeight: 400, color: '#171717' }}>{t}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" draggable={false} onError={() => setBad(true)}
            style={{ width: `${pct}%`, height: `${pct}%`, objectFit: 'contain', pointerEvents: 'none' }} />}
      {children}
    </span>
  );
}

/** A warning dot hung 7 px before a big figure, outside its column (in the card's padding), so the figure keeps
    its place (focus §2.3). The figure's span is `position: relative`. */
function Pin({ k }: { k: 'r' | 'g' }) {
  return <span aria-hidden="true" style={{ position: 'absolute', right: '100%', top: '50%', transform: 'translateY(-50%)', display: 'flex' }}><Dot k={k} /></span>;
}

/** One rung, one row: the big kept % (64 px column, 52 narrow; a five-character −661% widens its own row rather
    than run into the title, a −61% runs into the gap as before), then the title with its date and the action on one
    line (the action wraps under it when narrow), and the grey line when there is something to do. The focus look
    (handoff 2026-11-25-focus §2): the words neutral, a dot before the % of a rung in the money (red) or ready to roll
    (green), a − on a loss. */
export function RungRow({ x, narrow }: { x: Line; narrow: boolean }) {
  return (
    <div role="listitem" aria-label={x.aria} className="tnum"
      style={{ display: 'grid', gridTemplateColumns: `${x.big.length > 4 ? `minmax(${narrow ? 52 : 64}px,max-content)` : `${narrow ? 52 : 64}px`} minmax(0,1fr)`, gap: `0 ${narrow ? 12 : 24}px`, alignItems: 'center', padding: '10px 0', borderTop: `1px solid ${ln(0.06)}` }}>
      <span style={{ position: 'relative', fontSize: narrow ? 22 : 26, lineHeight: 1.05, fontWeight: 800, letterSpacing: '-.03em', color: wordOf(x.bigC, 22), whiteSpace: 'nowrap' }}>{x.dot && <Pin k={x.dot} />}{x.big}</span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
        <span style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'baseline', justifyContent: 'space-between', gap: '2px 12px' }}>
          <span style={{ fontSize: narrow ? 14 : 16, lineHeight: narrow ? '19px' : '22px', fontWeight: 500, color: x.titleC }}>
            {x.title}<span style={{ fontWeight: 400, color: MU }}> · {x.date}</span>
          </span>
          {x.act && <span style={{ fontSize: narrow ? 13 : 14, lineHeight: narrow ? '18px' : '21px', fontWeight: narrow ? 400 : 500, color: wordOf(x.actC, 14), textWrap: 'pretty' } as CSSProperties}>{x.act}</span>}
        </span>
        {x.grey && <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>{x.grey}</span>}
      </span>
    </div>
  );
}

/** The delta line's body: the big ↑% (in ink; inside 3% a red dot before it from 20 px, focus §2.3), then the plain
    words and one grey line of why. */
export function FlipBody({ f, size }: { f: Flip; size: number }) {
  return (
    <span style={{ display: 'grid', gridTemplateColumns: 'auto minmax(0,1fr)', gap: '2px 14px', alignItems: 'center' }}>
      <span className="tnum" style={{ position: 'relative', fontSize: size, lineHeight: 1.1, fontWeight: size >= 20 ? 700 : 500, letterSpacing: '-.02em', color: wordOf(f.bigC, size), whiteSpace: 'nowrap' }}>{f.bigC === RED && size >= 20 && <Pin k="r" />}{f.big}</span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
        <span className="tnum" style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500, textWrap: 'pretty' } as CSSProperties}>{f.a}</span>
        {f.b ? <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>{f.b}</span> : null}
      </span>
    </span>
  );
}
