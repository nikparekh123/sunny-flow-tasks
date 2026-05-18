import { useState } from 'react';
import type { StrategyPosition } from '../types';
import { BUCKET_META } from '../types';
import { fmtK } from '../calc';

interface Props {
  closed: StrategyPosition[];
}

const fmtSignedK = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function ClosedRow({ closed }: Props) {
  const [open, setOpen] = useState(false);
  const totals = closed.reduce(
    (a, p) => {
      const collected = p.entries
        .filter((e) => e.source === 'call')
        .reduce((s, e) => s + (e.amount || 0), 0);
      const realized = p.entries
        .filter((e) => e.source === 'stock')
        .reduce((s, e) => s + (e.amount || 0), 0);
      a.collected += collected;
      a.realized += realized;
      a.total += collected + realized;
      return a;
    },
    { collected: 0, realized: 0, total: 0 },
  );

  return (
    <div className="closed-row">
      <div className="head" onClick={() => setOpen((o) => !o)}>
        <span className="title">Closed positions</span>
        <span className="count">{closed.length} · YTD</span>
        <span className="totals">
          realized P&amp;L <span className="v">{fmtSignedK(totals.realized)}</span>
          {' · '}premium kept <span className="v">{fmtK(totals.collected)}</span>
          {' · '}total <span className="v">{fmtSignedK(totals.total)}</span>
        </span>
        <span className="toggle">{open ? '▼' : '▸'}</span>
      </div>
      {open && (
        <div className="closed-list">
          {closed.map((p) => {
            const collected = p.entries.reduce((s, e) => s + (e.options || 0), 0);
            const realized = p.entries.reduce((s, e) => s + (e.stock || 0), 0);
            const total = collected + realized;
            const bucket = p.overlay?.bucket;
            return (
              <div key={p.ticker} className="closed-card">
                <div className="row">
                  <span className="tk">{p.ticker}</span>
                  <span className={'val ' + (total >= 0 ? 'pos' : 'neg')}>
                    {fmtSignedK(total)}
                  </span>
                </div>
                <div className="row">
                  <span className="meta">
                    {bucket ? BUCKET_META[bucket].name : '—'} ·{' '}
                    {p.overlay?.days_held ?? 0}d
                  </span>
                  <span className="meta">{p.overlay?.updated_at?.slice(0, 10) ?? ''}</span>
                </div>
                <div className="breakdown">
                  realized {fmtSignedK(realized)} · premium +{fmtK(collected)}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
