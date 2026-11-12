// The position bar (handoff 2026-11-11-sd-whatif-totals, App Explorations 145b; Web Dark v2 under the Positions
// title): one slim strip, one view (the old Paid · Value now · Time value switch and the click-to-cycle are gone).
// The whole book on top, the name on screen under it; each piece's value, and under it the gain or loss in $ and %.
//
// Pieces follow Nik's grouping rule (totals.ts): LONG Shares · HEDGE Calls, Puts · INCOME Calls, Puts.
//   Shares, Hedge:  value now; gain = now less paid; % on paid.
//   Income:         collected, the time value left in brackets ($13.5K ($9.6K)); kept = collected less the cost to
//                   close now; % on collected.
// Under 860 px the strip scrolls sideways; nothing overlaps at any width.
import { money, pct } from '../lib/format';
import { PIECES, ROLES, gainOf, pctOfFig, type Cell, type Row } from './totals';
import { G, K, MU, R } from './ui';

const RULE = '1px solid rgba(255,255,255,.08)';
const LABEL = '#AEAEB2';
/** 96 px row labels; Long's one piece and Hedge's two at least 96 px; Income's two 1.25× wide, at least 120 px. */
const COLS = '96px ' + PIECES.map((p) => (p.role === 'income' ? 'minmax(120px,1.25fr)' : 'minmax(96px,1fr)')).join(' ');
/** The first piece of each group after the first carries the group's border and 10 px after it. */
const starts = new Set(ROLES.slice(1).map((r) => PIECES.findIndex((p) => p.role === r.k)));

interface Shown { v: string; c: string; tv: string | null; g: string | null; gc: string; aria: string }

function show(c: Cell, income: boolean, mask: (s: string) => string, what: string): Shown {
  if (!c) return { v: 'None', c: MU, tv: null, g: null, gc: MU, aria: what + ', none' };
  const g = gainOf(c, income), x = pctOfFig(c, income);
  const v = mask(money(income ? c.paid : c.now)), tv = income ? mask(money(c.tv ?? 0)) : null, gs = mask(money(g)) + ' · ' + pct(x);
  const up = g > 0 ? (income ? 'kept ' : 'up ') : g < 0 ? (income ? 'lost ' : 'down ') : '';
  const aria = income
    ? `${what}, collected ${v}, time value left ${tv}, ${up}${mask(money(g))}, ${pct(x)}`
    : `${what}, ${v}, ${up}${mask(money(g))}, ${pct(x)}`;
  return { v, c: K, tv, g: gs, gc: g > 0 ? G : g < 0 ? R : K, aria };
}

export function PositionBar({ book, name, t, mask }: { book: Row; name: Row | null; t: string | null; mask: (s: string) => string }) {
  const rows: { k: string; l: string; me: boolean; row: Row | null }[] = [
    { k: 'b', l: 'Whole book', me: false, row: book },
    ...(t ? [{ k: 't', l: t, me: true, row: name }] : []),
  ];
  return (
    <div aria-label="Book totals" className="sw-bar tnum"
      style={{ overflowX: 'auto', scrollbarWidth: 'none', borderTop: '1px solid rgba(255,255,255,.14)', borderBottom: RULE }}>
      <div style={{ display: 'grid', gridTemplateColumns: COLS, minWidth: 860, padding: '12px 0 2px' }}>
        <span />
        {ROLES.map((r, i) => {
          const n = PIECES.filter((p) => p.role === r.k).length;
          return (
            <div key={r.k} style={{ gridColumn: `span ${n}`, padding: `0 0 2px ${i ? 10 : 0}px`, borderLeft: i ? RULE : 'none' }}>
              <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 700, letterSpacing: '.05em', textTransform: 'uppercase', color: MU }}>{r.h}</span>
            </div>
          );
        })}
        <span />
        {PIECES.map((p, i) => (
          <span key={p.key} style={{ padding: starts.has(i) ? '0 8px 8px 10px' : '0 8px 8px 0', borderLeft: starts.has(i) ? RULE : 'none',
            fontSize: 12, lineHeight: '16px', color: LABEL, whiteSpace: 'nowrap' }}>{p.l}</span>
        ))}
        {rows.map((r) => (
          <div key={r.k} style={{ display: 'contents' }}>
            <span aria-hidden="true" style={{ gridColumn: '1 / -1', height: 1, background: 'rgba(255,255,255,.08)' }} />
            <span style={{ padding: '8px 8px 8px 0', fontSize: 13, lineHeight: '20px', fontWeight: r.me ? 600 : 400, color: r.me ? K : MU, whiteSpace: 'nowrap' }}>{r.l}</span>
            {PIECES.map((p, i) => {
              const role = ROLES.find((x) => x.k === p.role)!.h;
              const x = show(r.row ? r.row[p.key] : null, p.role === 'income', mask, `${r.l}, ${role} ${p.l.toLowerCase()}`);
              return (
                <div key={p.key} role="group" aria-label={x.aria} style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 1,
                  padding: starts.has(i) ? '8px 8px 8px 10px' : '8px 8px 8px 0', borderLeft: starts.has(i) ? RULE : 'none' }}>
                  <span style={{ display: 'flex', alignItems: 'baseline', gap: 4, whiteSpace: 'nowrap' }}>
                    <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: x.c }}>{x.v}</span>
                    {x.tv && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 500, color: LABEL }}>({x.tv})</span>}
                  </span>
                  {x.g && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap', color: x.gc }}>{x.g}</span>}
                </div>
              );
            })}
          </div>
        ))}
      </div>
      <style>{`.sw .sw-bar::-webkit-scrollbar{display:none}`}</style>
    </div>
  );
}
