import type { DragEvent, MouseEvent } from 'react';
import type { StrategyPosition } from '../types';
import { fmtK, fmtPx } from '../calc';
import { encodeDrag, type DragKind } from './dragdrop';

interface Props {
  items: StrategyPosition[];
  onDragStart: (kind: DragKind, ticker: string) => void;
  onDragEnd: () => void;
  onCardClick: (p: StrategyPosition) => void;
}

export function UnassignedStrip({ items, onDragStart, onDragEnd, onCardClick }: Props) {
  return (
    <div className="unassigned-strip">
      <div className="head">
        <span className="title">Unassigned</span>
        <span className="count">{items.length} positions · from Positions</span>
        <span className="hint">drag onto a bucket below to assign · or click to set strategy</span>
      </div>
      <div className="unassigned-row">
        {items.map((p) => (
          <UnassignedCard
            key={p.ticker}
            p={p}
            onDragStart={onDragStart}
            onDragEnd={onDragEnd}
            onClick={onCardClick}
          />
        ))}
        {items.length === 0 && (
          <div
            style={{
              padding: 24,
              textAlign: 'center',
              color: 'var(--navi-fg3)',
              fontSize: 11,
              letterSpacing: 1.2,
              textTransform: 'uppercase',
            }}
          >
            no unassigned positions · everything is in a bucket
          </div>
        )}
      </div>
    </div>
  );
}

function UnassignedCard({
  p,
  onDragStart,
  onDragEnd,
  onClick,
}: {
  p: StrategyPosition;
  onDragStart: (kind: DragKind, ticker: string) => void;
  onDragEnd: () => void;
  onClick: (p: StrategyPosition) => void;
}) {
  const qty = p.quantity ?? 0;
  const avg = p.avg_cost ?? 0;
  const cur = p.current_price ?? avg;
  const cost = qty * avg;
  const value = qty * cur;
  const sharePL = value - cost;
  const sharePLPct = cost > 0 ? (sharePL / cost) * 100 : 0;

  return (
    <div
      className="upcard"
      draggable
      onDragStart={(e: DragEvent<HTMLDivElement>) => {
        e.dataTransfer.setData('text/plain', encodeDrag('unassigned', p.ticker));
        e.dataTransfer.effectAllowed = 'move';
        onDragStart('unassigned', p.ticker);
        e.currentTarget.classList.add('dragging');
      }}
      onDragEnd={(e: DragEvent<HTMLDivElement>) => {
        e.currentTarget.classList.remove('dragging');
        onDragEnd();
      }}
      onClick={(_e: MouseEvent<HTMLDivElement>) => onClick(p)}
      title="drag onto a bucket to assign · click to view"
    >
      <div className="row">
        <span className="tk">{p.ticker}</span>
        <span className="sector">{p.sector}</span>
      </div>
      <div className="row">
        <span className="meta">
          {qty.toLocaleString('en-US')} sh · {fmtPx(avg)}
        </span>
        <span className={'pl ' + (sharePL >= 0 ? 'pos' : 'neg')}>
          {(sharePL >= 0 ? '+' : '−')}
          {fmtK(Math.abs(sharePL)).replace(/^−/, '')} ·{' '}
          {sharePLPct >= 0 ? '+' : ''}
          {sharePLPct.toFixed(1)}%
        </span>
      </div>
      <div className="assign-hint">drag → assign to bucket</div>
    </div>
  );
}
