import type { CSSProperties, ReactNode } from 'react';
import type { BucketCalc } from '../calc';
import { fmt$, fmtK } from '../calc';
import { decodeDrag } from './dragdrop';

interface Props {
  bucket: BucketCalc;
  variant?: 'treemap' | 'pipeline' | '';
  dropActive: boolean;
  onDrop: (data: { kind: 'watch' | 'unassigned' | 'pos'; ticker: string }, bucketKey: BucketCalc['key']) => void;
  children: ReactNode;
}

const fmtSignedK = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function BucketPanel({ bucket, variant = '', dropActive, onDrop, children }: Props) {
  const style = { '--accent': `var(--b-${bucket.key})` } as CSSProperties;
  const verdictLabel =
    bucket.verdict === 'good' ? 'On track' : bucket.verdict === 'warn' ? 'Slipping' : 'Behind';

  return (
    <div
      className={
        `bucket-panel b-${bucket.key} ${variant}` + (dropActive ? ' drop-active' : '')
      }
      data-bucket={bucket.key}
      style={style}
      onDragOver={(e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
      }}
      onDrop={(e) => {
        e.preventDefault();
        const decoded = decodeDrag(e.dataTransfer.getData('text/plain'));
        if (decoded) onDrop(decoded, bucket.key);
      }}
    >
      <div className="head">
        <div className="title">
          <span className="dot" />
          <span>{bucket.name}</span>
          <small>· {bucket.count} positions</small>
        </div>
        <div className={'verdict ' + bucket.verdict}>
          {verdictLabel} · {(bucket.onTrack * 100).toFixed(0)}%
        </div>
        <div className="stats">
          <div className="stat">
            <div className="k">cost overall</div>
            <div className="v">{fmtK(bucket.cost)}</div>
          </div>
          <div className="stat">
            <div className="k">share P&amp;L</div>
            <div className={'v ' + (bucket.sharePL >= 0 ? 'pos' : 'neg')}>
              {fmtSignedK(bucket.sharePL)}
            </div>
          </div>
          <div className="stat">
            <div className="k">cost of put</div>
            <div className="v">{fmtK(bucket.putCost)}</div>
          </div>
        </div>
        {bucket.shortfall > 50 ? (
          <div className="catch-up">
            <span>
              need <span className="need">{fmt$(bucket.catchUp)}/wk</span> to catch up
            </span>
            <span style={{ color: 'var(--navi-fg3)' }}>{bucket.count} positions</span>
          </div>
        ) : (
          <div className="catch-up">
            <span style={{ color: 'var(--navi-positive)' }}>
              +{fmt$(-bucket.shortfall)} ahead of pace
            </span>
            <span style={{ color: 'var(--navi-fg3)' }}>{bucket.count} positions</span>
          </div>
        )}
      </div>
      {children}
    </div>
  );
}
