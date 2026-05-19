import { computePutProtection, fmtCompact, fmtUSD, type PortfolioTotals, type PutProtectionRow } from './types';
import type { StrategyBucket } from './usePositions';

const BUCKET_META: Record<StrategyBucket, { name: string; tone: string; blurb: string }> = {
  income: { name: 'Income',     tone: 'income', blurb: 'covered calls' },
  invest: { name: 'Investment', tone: 'invest', blurb: 'growth holds' },
  yield:  { name: 'Yield',      tone: 'yield',  blurb: 'puts + dividends' },
};
const BUCKETS: StrategyBucket[] = ['income', 'invest', 'yield'];

interface Props {
  portfolio: PortfolioTotals;
  overlayByTicker: Map<string, StrategyBucket>;
  putProtectionByTicker: Map<string, PutProtectionRow>;
}

/**
 * Two stacked strips above the positions table:
 *   A — net realized hero + by-source (S/C/P) + Put cost
 *   B — three strategy cards
 */
export function RealizedSummary({ portfolio, overlayByTicker, putProtectionByTicker }: Props) {
  // Per-strategy aggregates derived once.
  const byStrategy: Record<StrategyBucket, {
    realized: { stock: number; call: number; put: number; total: number };
    put_cost: number;
    put_per_week: number;
    market_value: number;
    count: number;
  }> = {
    income: { realized: { stock: 0, call: 0, put: 0, total: 0 }, put_cost: 0, put_per_week: 0, market_value: 0, count: 0 },
    invest: { realized: { stock: 0, call: 0, put: 0, total: 0 }, put_cost: 0, put_per_week: 0, market_value: 0, count: 0 },
    yield:  { realized: { stock: 0, call: 0, put: 0, total: 0 }, put_cost: 0, put_per_week: 0, market_value: 0, count: 0 },
  };
  for (const r of portfolio.rows) {
    const b = overlayByTicker.get(r.ticker);
    if (!b) continue;
    const s = byStrategy[b];
    s.realized.stock += r.realized.stock;
    s.realized.call  += r.realized.call;
    s.realized.put   += r.realized.put;
    s.realized.total += r.realized.total;
    s.put_cost       += r.put_cost;
    s.market_value   += r.market_value;
    s.count          += 1;
    // Per-week put cost: each contract's total_cost / days_to_expiry × 7,
    // summed across the bucket. Matches the table the user shared.
    const pp = putProtectionByTicker.get(r.ticker);
    if (pp) {
      const calc = computePutProtection(pp);
      if (calc.has && !calc.expired && calc.cost_per_day > 0) {
        s.put_per_week += calc.cost_per_day * 7;
      }
    }
  }

  return (
    <>
      {/* Strip A — by source */}
      <div className="np-realized-strip">
        <div className="np-realized-cell total">
          <div className="np-realized-label">Net realized</div>
          <div className={'np-realized-value ' + (portfolio.net_realized < 0 ? 'down' : 'up')}>
            {fmtUSD(portfolio.net_realized)}
          </div>
          <div className="np-realized-sub">
            realized {fmtCompact(portfolio.realized_total)}{' '}
            <span className="dim">−</span> put cost {fmtCompact(portfolio.total_put_cost)}
          </div>
        </div>
        <div className="np-realized-cell">
          <div className="np-realized-label">
            <span className="rchip rk-s rchip-static">S</span>Stock
          </div>
          <div className={'np-realized-value ' + (portfolio.realized.stock < 0 ? 'down' : 'up')}>
            {fmtUSD(portfolio.realized.stock)}
          </div>
        </div>
        <div className="np-realized-cell">
          <div className="np-realized-label">
            <span className="rchip rk-c rchip-static">C</span>Call
          </div>
          <div className={'np-realized-value ' + (portfolio.realized.call < 0 ? 'down' : 'up')}>
            {fmtUSD(portfolio.realized.call)}
          </div>
        </div>
        <div className="np-realized-cell">
          <div className="np-realized-label">
            <span className="rchip rk-p rchip-static">P</span>Put
          </div>
          <div className={'np-realized-value ' + (portfolio.realized.put < 0 ? 'down' : 'up')}>
            {fmtUSD(portfolio.realized.put)}
          </div>
        </div>
        <div className="np-realized-cell">
          <div className="np-realized-label">
            Put cost{' '}
            <span className="np-realized-protect">protect</span>
          </div>
          <div className="np-realized-value down">
            {portfolio.total_put_cost > 0 ? '−' + fmtUSD(portfolio.total_put_cost) : <span className="muted">—</span>}
          </div>
        </div>
      </div>

      {/* Strip B — by strategy */}
      <div className="np-strategy-strip">
        {BUCKETS.map((k) => {
          const s = byStrategy[k];
          if (s.count === 0) return null;
          const meta = BUCKET_META[k];
          const net = s.realized.total - s.put_cost;
          return (
            <div key={k} className={'np-strat-cell st-' + k}>
              <div className="np-strat-hd">
                <span className={'np-strat-badge st-' + k}>{meta.name}</span>
                <span className="np-strat-blurb">{meta.blurb}</span>
              </div>
              <div className={'np-strat-value ' + (net < 0 ? 'down' : 'up')}>
                {fmtUSD(net)}
              </div>
              <div className="np-strat-detail">
                <span className="np-strat-detail-item">
                  <span className="k">realized</span>{fmtCompact(s.realized.total)}
                </span>
                <span className="np-strat-detail-item">
                  <span className="k">put cost</span>−{fmtCompact(s.put_cost)}
                </span>
                {s.put_per_week > 0 && (
                  <span className="np-strat-detail-item" title="Sum of (put cost ÷ days to expiry) × 7 across active contracts in this bucket">
                    <span className="k">per wk</span>−{fmtCompact(s.put_per_week)}
                  </span>
                )}
                <span className="np-strat-detail-item">
                  <span className="k">mkt val</span>{fmtCompact(s.market_value)}
                </span>
                <span className="np-strat-detail-item">
                  <span className="k">pos</span>{s.count}
                </span>
              </div>
            </div>
          );
        })}
      </div>
    </>
  );
}
