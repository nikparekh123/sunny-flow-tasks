import type { CSSProperties, DragEvent, MouseEvent } from 'react';
import type { StrategyPosition, Bucket } from '../types';
import type { PositionCalc } from '../calc';
import { fmtK, fmtPx } from '../calc';
import { encodeDrag, type DragKind } from './dragdrop';

interface Props {
  p: StrategyPosition;
  c: PositionCalc;
  bucket: Bucket;
  sizeClass?: '' | 'big' | 'wide';
  onDragStart: (kind: DragKind, ticker: string, from: Bucket) => void;
  onDragEnd: () => void;
  onClick: (p: StrategyPosition, bucket: Bucket) => void;
  onLogGain?: (p: StrategyPosition, bucket: Bucket) => void;
}

const fmtSignedK = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function PositionCard({
  p,
  c,
  bucket,
  sizeClass = '',
  onDragStart,
  onDragEnd,
  onClick,
  onLogGain,
}: Props) {
  const style = { '--accent': `var(--b-${bucket})` } as CSSProperties;
  const verdictLabel =
    c.verdict === 'good' ? 'On track' : c.verdict === 'warn' ? 'Slipping' : 'Behind';
  const qty = p.quantity ?? 0;
  const avg = p.avg_cost ?? 0;
  const cur = p.current_price ?? avg;

  return (
    <div
      className={
        'pcard ' + sizeClass + (c.underwater ? ' underwater' : '')
      }
      style={style}
      draggable
      onDragStart={(e: DragEvent<HTMLDivElement>) => {
        e.dataTransfer.setData('text/plain', encodeDrag('pos', p.ticker));
        e.dataTransfer.effectAllowed = 'move';
        onDragStart('pos', p.ticker, bucket);
        e.currentTarget.classList.add('dragging');
      }}
      onDragEnd={(e: DragEvent<HTMLDivElement>) => {
        e.currentTarget.classList.remove('dragging');
        onDragEnd();
      }}
      onClick={() => onClick(p, bucket)}
    >
      <div className="row">
        <div className="tk-block">
          <span className="tk">{p.ticker}</span>
          <span className="sector">{p.sector}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {onLogGain && (
            <button
              className="gain-pill"
              onClick={(e: MouseEvent<HTMLButtonElement>) => {
                e.stopPropagation();
                onLogGain(p, bucket);
              }}
              title="log a dividend or realized gain"
            >
              <span className="plus">+</span>$ gain
            </button>
          )}
          <span className={`verdict-pill ${c.verdict}`}>{verdictLabel}</span>
        </div>
      </div>

      <div className="pos-meta">
        {qty.toLocaleString('en-US')} sh @ {fmtPx(avg)} · now {fmtPx(cur)}
      </div>

      <div className="nums">
        <div>
          <div className="k">share P&amp;L</div>
          <div className={`v ${c.sharePL >= 0 ? 'pos' : 'neg'}`}>
            {fmtSignedK(c.sharePL)}
            <small>
              {c.sharePLPct >= 0 ? '+' : ''}
              {c.sharePLPct.toFixed(1)}% mark
            </small>
          </div>
        </div>
        <div>
          <div className="k">premium · {(c.onTrack * 100).toFixed(0)}% pace</div>
          <div className="v muted">
            {fmtK(c.collected)}
            <small>of {fmtK(c.target)} target</small>
          </div>
        </div>
      </div>

      <div className="totalbar">
        <span className="label">total profit</span>
        <span className={`total ${c.total >= 0 ? 'pos' : 'neg'}`}>
          {fmtSignedK(c.total)}
          <span className="breakdown">
            shares {fmtSignedK(c.sharePL)}
            {c.realizedGains > 0 && <> · realized +{fmtK(c.realizedGains)}</>}
            {' · prem +'}
            {fmtK(c.collected)}
          </span>
        </span>
      </div>
    </div>
  );
}

