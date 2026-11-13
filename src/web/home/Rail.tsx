// The Positions rail on Home (handoff 2026-11-12-positions-rail, Explorations 148a; Nik 12 Nov 2026): today, live, for
// every leg in the book. The header and See all, the Time value line, a glass By ticker | By leg control, then one
// glass card per name (By ticker) or per kind (By leg: Shares, Hedges, Income). Every leg is its own row: what it is,
// a bar from a centre line (the longest in the card sets the scale) and today's dollars. Builder A places it: sticky
// on the right at 340, or under the main column when `narrow`. A card or row opens Positions on that name.
import { useMemo, type CSSProperties } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePrefetchFromHome, type BookId, type J } from '../lib/data';
import { money } from '../lib/format';
import { useWeb } from '../lib/state';
import { inSessionOrder, railNames, tvLegs } from './rail/model';
import { railToday, type RailRow } from './rail/today';

const MU = '#98989D', G = '#65C466', R = '#FF6961', INK = '#F5F5F7';
const cl = (v: number) => (Math.round(v) === 0 ? MU : v > 0 ? G : R);
const pc = (x: number) => { const a = Math.abs(x); return (x >= 0 ? '↑ ' : '↓ ') + (a > 0 && a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%'; };
const GLASS: CSSProperties = {
  boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 10, padding: '14px 16px', borderRadius: 20,
  background: 'linear-gradient(160deg,rgba(255,255,255,.07) 0%,rgba(255,255,255,.025) 55%,rgba(255,255,255,.05) 100%)',
  boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08),inset 1px 1px 0 -.5px rgba(255,255,255,.16)',
};
const CSS = `.sw-rc{transition:background .2s}.sw-rc:hover{background:linear-gradient(160deg,rgba(255,255,255,.11) 0%,rgba(255,255,255,.04) 55%,rgba(255,255,255,.08) 100%)!important}
.sw-rr:hover .sw-rr-l{text-decoration:underline}.sw-rail-see:hover{color:${INK}!important}`;

export default function Rail({ payload, book, narrow }: { payload: J; book: BookId; narrow: boolean }) {
  const { mask, railView, setRailView, setTvOpen } = useWeb();
  const nav = useNavigate();
  // The session order Home has drawn the names in (they never re-sort as prices move).
  const order = useMemo(() => inSessionOrder(book, railNames(payload)).map((n) => n.t), [payload, book]);
  const rt = useMemo(() => railToday(payload, order), [payload, order]);
  const tv = useMemo(() => {
    const legs = tvLegs(payload);
    return { calls: Number(payload?.brief?.totals?.tv?.sc ?? 0), ready: legs.filter((l) => l.ready).length };
  }, [payload]);
  // Once Home is up, read ahead what a click here opens: each name on Positions, in the rail's order.
  const ahead = useMemo(() => {
    const held = new Set(((payload?.brief?.names ?? []) as J[]).map((n) => String(n.t)));
    return order.filter((t) => held.has(t));
  }, [order, payload]);
  usePrefetchFromHome(book, ahead, ahead.length > 0);

  const open = (t: string) => nav('/positions/' + encodeURIComponent(t));
  const dl = rt.week ? 'This week' : 'Today', dw = rt.week ? 'this week' : 'today';
  const upd = (v: number) => (v < 0 ? 'down ' : 'up ') + mask(money(v));
  const byLeg = railView === 'leg';
  const note = (rt.noSold.length ? `Nothing sold this week: ${rt.noSold.join(', ')}. ` : '')
    + `Shares: ${rt.week ? 'this week, from last Friday’s close' : 'today, from yesterday’s close'}. Options: since each was opened; the bar is what was paid or collected, green gained, red lost, grey still to go.`;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      <style>{CSS}</style>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, paddingBottom: 6 }}>
        <span style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.01em' }}>Positions</span>
        <button type="button" className="bare sw-rail-see" onClick={() => nav('/positions')} style={{ fontSize: 13, color: MU }}>See all ›</button>
      </div>
      {rt.names.length > 0 && (
        <button type="button" className="bare" onClick={() => setTvOpen(true)}
          style={{ display: 'flex', justifyContent: 'space-between', gap: 10, padding: '4px 0 14px', fontSize: 13, borderBottom: '1px solid rgba(255,255,255,.14)' }}>
          <span style={{ fontWeight: 600, color: G }}>{mask(money(tv.calls))} left to earn</span>
          <span style={{ color: '#FF9F0A', fontWeight: 600 }}>{tv.ready ? `${tv.ready} ready to roll ›` : 'None ready to roll ›'}</span>
        </button>
      )}
      {rt.names.length === 0 ? (
        // A book with nothing held (the cousin's, until he trades): the phone's one line (PositionsScreen).
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, paddingTop: 14 }}>
          <span style={{ fontSize: 15, fontWeight: 600 }}>Nothing held yet</span>
          <span style={{ fontSize: 13, color: MU }}>Each name you hold shows here once IBKR reports it.</span>
        </div>
      ) : (
        <div className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 14 }}>
          <Seg value={byLeg ? 'leg' : 'ticker'} set={setRailView} />
          {!byLeg ? rt.names.map((n) => {
            // The same rows as By leg (Nik, 13 Nov 2026): options since opened, shares today.
            const sh = n.rows.filter((x) => !x.since && x.l === 'Shares'), opt = n.rows.filter((x) => x.l !== 'Shares');
            const mx = Math.max(1, ...sh.map((x) => Math.abs(x.v)));
            const optPl = opt.reduce((a, x) => a + (x.since?.pl ?? 0), 0), shToday = sh.reduce((a, x) => a + x.v, 0);
            const head = opt.length ? { l: 'Options since opened', v: optPl } : { l: dl, v: shToday };
            return (
              <button key={n.t} type="button" className="bare sw-rc" onClick={() => open(n.t)}
                aria-label={`${n.t}, ${head.l.toLowerCase()} ${upd(head.v)}${opt.length && sh.length ? `, shares ${dw} ${upd(shToday)}` : ''}, opens Positions`}
                style={{ ...GLASS, cursor: 'pointer', textAlign: 'left' }}>
                <span style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10 }}>
                  <span style={{ fontSize: 17, fontWeight: 700 }}>{n.t}</span>
                  <span style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                    <span style={{ fontSize: 16, fontWeight: 500 }}>${n.px.toFixed(2)}</span>
                    <span style={{ fontSize: 13, fontWeight: 600, color: n.mv >= 0 ? G : R }}>{pc(n.mv)}</span>
                  </span>
                </span>
                <span style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
                  <span style={{ fontSize: 13, color: MU }}>{head.l}</span>
                  <span style={{ fontSize: 17, fontWeight: 700, color: cl(head.v) }}>{mask(money(head.v))}</span>
                </span>
                {sh.map((x) => <Row key={x.k} x={{ ...x, s: `${x.s} · ${dw}` }} mx={mx} mask={mask} />)}
                {opt.map((x) => <SinceRow key={x.k} x={{ ...x, l: x.l.replace(/ (sold|bought)$/, '') }} mask={mask} />)}
              </button>
            );
          }) : rt.kinds.map((g) => {
            const mx = Math.max(1, ...g.parts.flatMap((u) => u.rows.map((x) => Math.abs(x.v))));
            return (
              <div key={g.k} style={GLASS}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10 }}>
                  <span style={{ fontSize: 17, fontWeight: 700 }}>{g.h}</span>
                  <span style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                    <span style={{ fontSize: 18, fontWeight: 700, color: cl(g.total) }}>{mask(money(g.total))}</span>
                    <span style={{ fontSize: 13, color: MU }}>{g.since ? 'since opened' : dw}</span>
                  </span>
                </div>
                {g.parts.map((u) => (
                  <div key={u.k} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                    {g.heads && (
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10, paddingTop: 6 }}>
                        <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 600, color: MU }}>{u.h}</span>
                        <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 600, color: cl(u.total) }}>{mask(money(u.total))}</span>
                      </div>
                    )}
                    {u.rows.map((x) => (
                      <button key={x.k} type="button" className="bare sw-rr" onClick={() => open(x.t)} style={{ cursor: 'pointer', textAlign: 'left' }}
                        aria-label={g.since && x.since
                          ? `${g.h} ${u.h.toLowerCase()}, ${x.l}, ${x.since.s}, ${x.since.pl < 0 ? 'lost' : g.h === 'Income' ? 'kept' : 'gained'} ${mask(money(x.since.pl))}, ${pctOf(x.since)}, opens Positions`
                          : `${g.h} ${u.h.toLowerCase()}, ${x.l}, ${x.s}, ${dw} ${upd(x.v)}, opens Positions`}>
                        {g.since ? <SinceRow x={x} mask={mask} /> : <Row x={x} mx={mx} mask={mask} />}
                      </button>
                    ))}
                  </div>
                ))}
              </div>
            );
          })}
          <span style={{ padding: '0 2px', fontSize: 13, lineHeight: '18px', color: MU, textWrap: 'pretty' } as CSSProperties}>{note}</span>
        </div>
      )}
      {narrow && <span aria-hidden="true" />}
    </div>
  );
}

/** A leg: what it is 15/600 and its line 12 muted; an 80 px bar from a centre line, green right and red left, the
    longest in the card full; today's dollars 15/600 in 60 px, green or red, no minus sign. */
function Row({ x, mx, mask }: { x: RailRow; mx: number; mask: (s: string) => string }) {
  const wz = (Math.abs(x.v) / mx) * 50;
  return (
    <span style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 80px 60px', alignItems: 'center', gap: 8, paddingTop: 8, borderTop: '1px solid rgba(255,255,255,.08)' }}>
      <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <span className="sw-rr-l" style={{ fontSize: 15, lineHeight: '19px', fontWeight: 600, textWrap: 'pretty' } as CSSProperties}>{x.l}</span>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>{x.s}</span>
      </span>
      <span aria-hidden="true" style={{ position: 'relative', height: 14 }}>
        <span style={{ position: 'absolute', left: '50%', top: -3, bottom: -3, width: 1, background: 'rgba(255,255,255,.22)' }} />
        <span style={{ position: 'absolute', top: 3, bottom: 3, left: (x.v >= 0 ? 50 : 50 - wz) + '%', width: Math.max(wz, 0.8) + '%', borderRadius: 2, background: x.v >= 0 ? G : R }} />
      </span>
      <span style={{ textAlign: 'right', fontSize: 15, fontWeight: 600, color: cl(x.v) }}>{mask(money(x.v))}</span>
    </span>
  );
}

const pctOf = (x: { base: number; pl: number }) => {
  const a = x.base > 0 ? Math.abs(x.pl / x.base) * 100 : 0;
  return (a > 0 && a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%';
};
/** An option leg since it was opened (Nik, 13 Nov 2026): the bar is what was collected (sold) or paid (bought), full
    width; green from the left for what it has gained or kept, red for what it has lost, the grey track the rest, still
    to go. On the right the dollars gained or lost (green or red, no minus) and their % of the bar. */
function SinceRow({ x, mask }: { x: RailRow; mask: (s: string) => string }) {
  const p = x.since, f = p && p.base > 0 ? Math.max(-1, Math.min(1, p.pl / p.base)) : 0;
  return (
    <span style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 80px 60px', alignItems: 'center', gap: 8, paddingTop: 8, borderTop: '1px solid rgba(255,255,255,.08)' }}>
      <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <span className="sw-rr-l" style={{ fontSize: 15, lineHeight: '19px', fontWeight: 600, textWrap: 'pretty' } as CSSProperties}>{x.l}</span>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>{p ? mask(p.s) : x.s}</span>
      </span>
      <span aria-hidden="true" style={{ position: 'relative', height: 8, borderRadius: 4, background: 'rgba(255,255,255,.14)', overflow: 'hidden' }}>
        {p && <span style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${Math.max(Math.abs(f) * 100, 2)}%`, borderRadius: 4, background: f >= 0 ? G : R }} />}
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
        <span style={{ fontSize: 15, fontWeight: 600, color: p ? cl(p.pl) : MU }}>{p ? mask(money(p.pl)) : '-'}</span>
        {p && <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{pctOf(p)}</span>}
      </span>
    </span>
  );
}

/** The glass By ticker | By leg control: a capsule track, a glass thumb that springs across (.42 s), 32 tall, 14 px,
    the picked one 600. */
function Seg({ value, set }: { value: 'ticker' | 'leg'; set: (v: 'ticker' | 'leg') => void }) {
  const items: ['ticker' | 'leg', string][] = [['ticker', 'By ticker'], ['leg', 'By leg']];
  return (
    <div role="radiogroup" aria-label="Group by"
      style={{ position: 'relative', display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
      <span aria-hidden="true" style={{ position: 'absolute', top: 2, left: 2, width: 'calc(50% - 2px)', height: 32, borderRadius: 999, background: 'rgba(255,255,255,.20)',
        boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)',
        transform: value === 'leg' ? 'translateX(100%)' : 'translateX(0)', transition: 'transform .42s cubic-bezier(.34,1.36,.64,1)' }} />
      {items.map(([k, l]) => (
        <button key={k} type="button" role="radio" aria-checked={value === k} className="bare" onClick={() => set(k)}
          style={{ position: 'relative', cursor: 'pointer', height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, fontWeight: value === k ? 600 : 500, color: INK }}>
          {l}
        </button>
      ))}
    </div>
  );
}
