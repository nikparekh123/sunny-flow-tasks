import type { CSSProperties, DragEvent } from 'react';
import type { StrategyPosition, Bucket } from '../types';
import type { PositionCalc } from '../calc';
import { fmt$, fmtK, fmtPx } from '../calc';
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
        <span className={`verdict-pill ${c.verdict}`}>{verdictLabel}</span>
      </div>

      <div className="pos-meta">
        {qty.toLocaleString('en-US')} sh · buy {fmtPx(avg)} · now {fmtPx(cur)}
      </div>

      <div className="nums">
        <div>
          <div className="k">unrealized</div>
          <div className={`v ${c.sharePL >= 0 ? 'pos' : 'neg'}`}>
            {fmtSignedK(c.sharePL)}
            <small>
              {c.sharePLPct >= 0 ? '+' : ''}
              {c.sharePLPct.toFixed(1)}%
            </small>
          </div>
        </div>
        <div>
          <div className="k">realized</div>
          <div
            className={
              'v ' +
              (c.realizedGains > 0 ? 'pos' : c.realizedGains < 0 ? 'neg' : 'muted')
            }
          >
            {c.realizedGains === 0 ? '—' : fmtSignedK(c.realizedGains)}
          </div>
        </div>
        {c.collected !== 0 && (
          <div>
            <div className="k">premium</div>
            <div className={`v ${c.collected >= 0 ? 'pos' : 'neg'}`}>
              {fmtSignedK(c.collected)}
            </div>
          </div>
        )}
      </div>

      {c.putCost > 0 && (
        <div className="nums">
          <div>
            <div className="k">put cost</div>
            <div className="v">
              {fmtK(c.putCost)}
              <small>
                {c.daysToExpiry > 0 ? `${c.daysToExpiry}d to expiry` : 'expired'}
              </small>
            </div>
          </div>
          <div>
            <div className="k">cost / trading day</div>
            <div className="v">
              {c.costPerTradingDay != null ? fmt$(c.costPerTradingDay) : '—'}
            </div>
          </div>
        </div>
      )}

      <div className="totalbar">
        <span className="label">overall</span>
        <span className={`total ${c.total >= 0 ? 'pos' : 'neg'}`}>
          {fmtSignedK(c.total)}
          <span className="breakdown">
            unrlz {fmtSignedK(c.sharePL)}
            {c.realizedGains !== 0 && <> · rlz {fmtSignedK(c.realizedGains)}</>}
            {c.collected !== 0 && <> · prem {fmtSignedK(c.collected)}</>}
            {c.putCost > 0 && <> · put −{fmtK(c.putCost)}</>}
          </span>
        </span>
      </div>
    </div>
  );
}

