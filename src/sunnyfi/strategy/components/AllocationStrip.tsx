import type { CSSProperties } from 'react';
import type { BucketCalc, PortfolioCalc } from '../calc';
import { fmtK } from '../calc';
import type { Bucket } from '../types';

interface Props {
  buckets: Record<Bucket, BucketCalc>;
  portfolio: PortfolioCalc;
}

const ORDER: Bucket[] = ['income', 'invest', 'yield'];

export function AllocationStrip({ buckets, portfolio }: Props) {
  return (
    <div className="alloc-strip">
      {ORDER.map((key) => {
        const b = buckets[key];
        const currentPct = portfolio.cost > 0 ? (b.cost / portfolio.cost) * 100 : 0;
        const style = { '--accent': `var(--b-${key})` } as CSSProperties;
        return (
          <div key={key} className={`alloc-cell b-${key}`} style={style}>
            <div className="head">
              <div className="name">{b.name}</div>
              <div className="meta">
                {b.count} positions
              </div>
            </div>
            <div className="nums">
              <div className="num">
                <div className="k">allocated</div>
                <div className="v">{currentPct.toFixed(1)}%</div>
              </div>
              <div className="num">
                <div className="k">cost basis</div>
                <div className="v">{fmtK(b.cost)}</div>
              </div>
              <div className="num">
                <div className="k">premium · qtr</div>
                <div className="v" style={{ color: 'var(--navi-neon)' }}>
                  {fmtK(b.collected)}
                </div>
              </div>
            </div>
            <div className="progress">
              <i style={{ width: Math.min(100, currentPct) + '%' }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}
