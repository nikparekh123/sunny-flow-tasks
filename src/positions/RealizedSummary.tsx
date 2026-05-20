import { fmtCompact, fmtUSD, type OptionTrade, type PortfolioTotals } from './types';
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
  realizedByTicker: Map<string, number>;
  liveByTicker: Map<string, Array<{ open: OptionTrade; remaining_contracts: number }>>;
}

/**
 * Two stacked strips above the positions table:
 *   A — net realized hero + open contracts breakdown
 *   B — three strategy cards (Income / Investment / Yield)
 *
 * "Realized" is now Σ closed-pair P&L on option_trades — gains and expenses
 * are not separate anymore.
 */
export function RealizedSummary({ portfolio, overlayByTicker, realizedByTicker, liveByTicker }: Props) {
  // Per-strategy aggregates derived once.
  const byStrategy: Record<StrategyBucket, {
    realized: number;
    open_put_obligation: number;
    live_options: number;
    market_value: number;
    count: number;
  }> = {
    income: { realized: 0, open_put_obligation: 0, live_options: 0, market_value: 0, count: 0 },
    invest: { realized: 0, open_put_obligation: 0, live_options: 0, market_value: 0, count: 0 },
    yield:  { realized: 0, open_put_obligation: 0, live_options: 0, market_value: 0, count: 0 },
  };
  for (const r of portfolio.rows) {
    const b = overlayByTicker.get(r.ticker);
    if (!b) continue;
    const s = byStrategy[b];
    s.realized        += realizedByTicker.get(r.ticker) ?? 0;
    s.market_value    += r.market_value;
    s.count           += 1;
    const live = liveByTicker.get(r.ticker) ?? [];
    s.live_options += live.length;
    for (const lo of live) {
      if (lo.open.option_type === 'put' && lo.open.direction === 'short') {
        s.open_put_obligation += lo.remaining_contracts * 100 * lo.open.strike;
      }
    }
  }

  return (
    <>
      {/* Strip A — portfolio realized + open obligation */}
      <div className="np-realized-strip">
        <div className="np-realized-cell total">
          <div className="np-realized-label">Net realized</div>
          <div className={'np-realized-value ' + (portfolio.realized_pl < 0 ? 'down' : 'up')}>
            {portfolio.realized_pl >= 0 ? fmtUSD(portfolio.realized_pl) : '−' + fmtUSD(Math.abs(portfolio.realized_pl))}
          </div>
          <div className="np-realized-sub">closed option pairs</div>
        </div>
        <div className="np-realized-cell">
          <div className="np-realized-label">Open obligation</div>
          <div className="np-realized-value">
            {portfolio.open_put_obligation > 0
              ? fmtUSD(portfolio.open_put_obligation)
              : <span className="muted">—</span>}
          </div>
          <div className="np-realized-sub">short put strikes × contracts</div>
        </div>
        <div className="np-realized-cell">
          <div className="np-realized-label">Live contracts</div>
          <div className="np-realized-value">
            {Array.from(liveByTicker.values()).reduce((s, l) => s + l.length, 0)}
          </div>
          <div className="np-realized-sub">open positions across portfolio</div>
        </div>
      </div>

      {/* Strip B — by strategy bucket */}
      <div className="np-strategy-strip">
        {BUCKETS.map((k) => {
          const s = byStrategy[k];
          if (s.count === 0) return null;
          const meta = BUCKET_META[k];
          return (
            <div key={k} className={'np-strat-cell st-' + k}>
              <div className="np-strat-hd">
                <span className={'np-strat-badge st-' + k}>{meta.name}</span>
                <span className="np-strat-blurb">{meta.blurb}</span>
              </div>
              <div className={'np-strat-value ' + (s.realized < 0 ? 'down' : 'up')}>
                {s.realized >= 0 ? fmtUSD(s.realized) : '−' + fmtUSD(Math.abs(s.realized))}
              </div>
              <div className="np-strat-detail">
                <span className="np-strat-detail-item">
                  <span className="k">live</span>{s.live_options}
                </span>
                {s.open_put_obligation > 0 && (
                  <span className="np-strat-detail-item">
                    <span className="k">put oblig</span>{fmtCompact(s.open_put_obligation)}
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
