// The Positions rail on Home (README 1b): the header with the view switch and See all, the button row into the Time
// value sheet, then every name as a Rails card or a tile. Builder A places it: sticky on the right at 340, or inside
// the main column when `narrow` (the Tiles grid then shows more tiles a row). Picking a card or tile opens Positions
// on that name. The view is remembered per computer (railView; Nik approved, default Rails).
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { BookId, J } from '../lib/data';
import { money } from '../lib/format';
import { useWeb } from '../lib/state';
import { inSessionOrder, railNames, tvLegs } from './rail/model';
import { RAIL_CSS, RailCard, RailTile, TileTip, ViewSwitch, type TipAt } from './rail/parts';

const MU = '#98989D';

export default function Rail({ payload, book, narrow }: { payload: J; book: BookId; narrow: boolean }) {
  const { mask, railView, setRailView, setTvOpen } = useWeb();
  const nav = useNavigate();
  const names = useMemo(() => inSessionOrder(book, railNames(payload)), [payload, book]);
  const tv = useMemo(() => {
    const legs = tvLegs(payload);
    return { calls: Number(payload?.brief?.totals?.tv?.sc ?? 0), ready: legs.filter((l) => l.ready).length };
  }, [payload]);
  const [tip, setTip] = useState<TipAt | null>(null);
  // A hover readout never outlives a scroll or a change of view.
  useEffect(() => {
    if (!tip) return;
    const off = () => setTip(null);
    window.addEventListener('scroll', off, true);
    return () => window.removeEventListener('scroll', off, true);
  }, [tip]);
  useEffect(() => setTip(null), [railView, narrow, book]);

  const tiles = railView === 'tiles';
  const open = (t: string) => nav('/positions/' + encodeURIComponent(t));

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      <style>{RAIL_CSS}</style>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, paddingBottom: 6 }}>
        <span style={{ fontSize: 20, fontWeight: 600, letterSpacing: '-.01em' }}>Positions</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <ViewSwitch view={railView} set={setRailView} />
          <button type="button" className="bare sw-rail-see" onClick={() => nav('/positions')} style={{ fontSize: 13, color: MU }}>See all ›</button>
        </div>
      </div>
      {names.length > 0 && (
        <button type="button" className="bare" onClick={() => setTvOpen(true)}
          style={{ display: 'flex', justifyContent: 'space-between', gap: 10, padding: '4px 0 14px', fontSize: 13, borderBottom: '1px solid rgba(255,255,255,.14)' }}>
          <span style={{ fontWeight: 600, color: '#65C466' }}>{mask(money(tv.calls))} left to earn</span>
          <span style={{ color: '#FF9F0A', fontWeight: 600 }}>{tv.ready ? `${tv.ready} ready to roll ›` : 'None ready to roll ›'}</span>
        </button>
      )}
      {names.length === 0 ? (
        // A book with nothing held (the cousin's, until he trades): the phone's one line (PositionsScreen).
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, paddingTop: 14 }}>
          <span style={{ fontSize: 15, fontWeight: 600 }}>Nothing held yet</span>
          <span style={{ fontSize: 13, color: MU }}>Each name you hold shows here once IBKR reports it.</span>
        </div>
      ) : tiles ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 14 }}>
          <div style={{ display: 'grid', fontVariantNumeric: 'tabular-nums', gridTemplateColumns: 'repeat(auto-fill,minmax(100px,1fr))', gap: 10 }}>
            {names.map((n) => <RailTile key={n.t} n={n} go={() => open(n.t)} tip={setTip} />)}
          </div>
          <span style={{ padding: '4px 2px 0', fontSize: 12, lineHeight: '17px', color: MU }}>
            Each tile: price and today’s move, then where the position stands by Friday from ↓10% to ↑10% (the dashed line is today). A dot: short (red) or thin (orange) at the priced move.
          </span>
          <TileTip at={tip} />
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 14 }}>
          {names.map((n) => <RailCard key={n.t} n={n} mask={mask} go={() => open(n.t)} />)}
          <span style={{ padding: '4px 2px 0', fontSize: 12, lineHeight: '17px', color: MU }}>
            The line under each name: where the position stands by Friday. A dot: short (red) or thin (orange) at the priced move. So far counts shares and options since you opened them.
          </span>
        </div>
      )}
    </div>
  );
}
