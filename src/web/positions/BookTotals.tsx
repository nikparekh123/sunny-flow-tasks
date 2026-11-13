// Book totals (handoff 2026-11-13-positions §3.1, with Nik's D7: five cells, not six).
//   LONG Shares · HEDGE Calls (every call bought, LEAPS too), Puts · INCOME Calls, Puts.
//   Long, Hedge: value now; gain = now less paid; % on paid.
//   Income:      collected, the time value still left in brackets; kept = collected less the mark now; % on collected.
// Two rows: the Whole book (every name on the account) and the name on screen. "None" where a name holds none.
// Every number is the book engine's holdings() (totals.ts), the numbers Home's brief sends the phone.
// Under 860 px the strip scrolls sideways; nothing overlaps at any width.
import { money, pct } from '../lib/format';
import { PIECES, ROLES, gainOf, pctOfFig, type Cell, type Row } from './totals';
import { G, K, MT, MU, R } from './ui';

const RULE = '1px solid rgba(255,255,255,.08)';
const COLS = '96px ' + PIECES.map((p) => (p.role === 'income' ? 'minmax(120px,1.25fr)' : 'minmax(96px,1fr)')).join(' ');
const starts = new Set(ROLES.slice(1).map((r) => PIECES.findIndex((p) => p.role === r.k)));

function show(c: Cell, income: boolean, mask: (s: string) => string, what: string) {
  if (!c) return { v: 'None', c: MU, tv: null as string | null, g: null as string | null, gc: MU, aria: what + ', none' };
  const g = gainOf(c, income), x = pctOfFig(c, income);
  const v = mask(money(income ? c.paid : c.now)), tv = income ? mask(money(c.tv ?? 0)) : null, gs = mask(money(g)) + ' · ' + pct(x);
  const up = g > 0 ? (income ? 'kept ' : 'up ') : g < 0 ? (income ? 'lost ' : 'down ') : '';
  const aria = income
    ? `${what}, collected ${v}, time value left ${tv}, ${up}${mask(money(g))}, ${pct(x)}`
    : `${what}, ${v}, ${up}${mask(money(g))}, ${pct(x)}`;
  return { v, c: K, tv, g: gs, gc: g > 0 ? G : g < 0 ? R : K, aria };
}

export function BookTotals({ book, name, t, mask }: { book: Row; name: Row | null; t: string | null; mask: (s: string) => string }) {
  const rows: { k: string; l: string; me: boolean; row: Row | null }[] = [
    { k: 'b', l: 'Whole book', me: false, row: book },
    ...(t ? [{ k: 't', l: t, me: true, row: name }] : []),
  ];
  return (
    <div aria-label="Book totals" className="swp-scroll tnum" style={{ overflowX: 'auto', borderTop: '1px solid rgba(255,255,255,.14)', borderBottom: RULE }}>
      <div style={{ display: 'grid', gridTemplateColumns: COLS, minWidth: 760, padding: '12px 0 2px' }}>
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
            fontSize: 12, lineHeight: '16px', color: MT, whiteSpace: 'nowrap' }}>{p.l}</span>
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
                    {x.tv && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 500, color: MT }}>({x.tv})</span>}
                  </span>
                  {x.g && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap', color: x.gc }}>{x.g}</span>}
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}
