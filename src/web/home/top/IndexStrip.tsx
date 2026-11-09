// The index strip (README 1, item 5). Market data: never masked.
import { C } from '../../lib/format';
import { Runs, splitHeadline } from './spans';
import type { Strip } from './strip';

const HAIR = '1px solid rgba(255,255,255,.08)';

export function IndexStrip({ strip, mask }: { strip: Strip; mask: (s: string) => string }) {
  const h = strip.headline ? splitHeadline(strip.headline) : null;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '18px 0 20px', borderBottom: HAIR }}>
      <span className="kicker">{strip.kicker}</span>
      {h && (
        <span style={{ fontSize: 17, lineHeight: '24px', fontWeight: 600, letterSpacing: '-.01em' }}>
          <Runs spans={h.thick} mask={mask} bold={600} />
          {h.thin.length > 0 && <> <span style={{ fontWeight: 400, color: 'rgba(245,245,247,.72)' }}><Runs spans={h.thin} mask={mask} bold={400} /></span></>}
        </span>
      )}
      {strip.cols.length > 0 && (
        <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(6,minmax(0,1fr))' }}>
          {strip.cols.map((x, i) => (
            <div key={x.k} style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, paddingLeft: i ? 22 : 0, borderLeft: i ? HAIR : 'none' }}>
              <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: '.04em', color: C.ink2 }}>{x.t}</span>
              <span style={{ fontSize: 20, lineHeight: '26px', fontWeight: 500 }}>{x.v}</span>
              <span style={{ fontSize: 13, fontWeight: 600, color: x.c }}>{x.m}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
