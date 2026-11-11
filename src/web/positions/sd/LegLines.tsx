// The three lines on a leg's row (App Explorations 139a, web): right-aligned, line 1 15/20 700 (ink, orange when the
// leg needs a look), line 2 12/16 muted (empty in the money), line 3 12/16 muted (orange on a sold leg under 70%).
import type { CSSProperties } from 'react';
import { L_MU, L_OR, type LegLines } from './legs';

export function LegSdLines({ v, style }: { v: LegLines; style?: CSSProperties }) {
  return (
    <span style={{ flex: 'none', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap', ...style }}>
      <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 700, color: v.c1 }}>{v.l1}</span>
      {v.l2 && <span style={{ fontSize: 12, lineHeight: '16px', color: L_MU }}>{v.l2}</span>}
      <span style={{ fontSize: 12, lineHeight: '16px', color: v.c3 }}>{v.l3}</span>
    </span>
  );
}

/** Try a trade's one line, 12/16 muted: `$9.40 away · 0.90 SD by Nov 20 · 80.0% expires worthless`, with the same
    orange: the first part when the trade would need a look, the last on a sale under 70%. */
export function TradeSdLine({ v, style }: { v: LegLines; style?: CSSProperties }) {
  return (
    // Each part stays whole; a narrow panel breaks the line only after a " · ".
    <span className="tnum" style={{ fontSize: 12, lineHeight: '16px', color: L_MU, ...style }}>
      <span style={{ whiteSpace: 'nowrap', color: v.look ? L_OR : undefined }}>{v.l1}</span>
      {v.l2 && <>{' · '}<span style={{ whiteSpace: 'nowrap' }}>{v.l2}</span></>}
      {' · '}
      <span style={{ whiteSpace: 'nowrap', color: v.c3 }}>{v.l3}</span>
    </span>
  );
}
