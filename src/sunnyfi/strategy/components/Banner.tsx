import type { PortfolioCalc } from '../calc';
import { fmt$, fmtK } from '../calc';
import { TOTAL_CAPITAL } from '../types';
import type { WeekBucket } from './weeklyHistory';

interface Props {
  portfolio: PortfolioCalc;
  cadence: 'month' | 'quarter' | 'year';
  weeklyHistory: WeekBucket[];
}

const fmtKSigned = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function Banner({ portfolio, cadence, weeklyHistory }: Props) {
  const cadenceLabel = cadence === 'month' ? 'month' : cadence === 'year' ? 'year' : 'quarter';
  const weeksPer = cadence === 'month' ? 4.33 : cadence === 'year' ? 52 : 13;
  const weeklyTarget = portfolio.target / weeksPer;
  const cashAvailable = TOTAL_CAPITAL - portfolio.cost;

  const max = Math.max(weeklyTarget * 1.1, ...weeklyHistory.map((w) => w.premium), 1);
  const thisWeek = weeklyHistory[weeklyHistory.length - 1];
  const lastWeek = weeklyHistory[weeklyHistory.length - 2];
  const wow = lastWeek && lastWeek.premium > 0
    ? ((thisWeek.premium - lastWeek.premium) / lastWeek.premium) * 100
    : 0;

  const statusLabel = portfolio.verdict === 'behind' ? 'Behind'
    : portfolio.verdict === 'ahead' ? 'Ahead' : 'On track';

  return (
    <div className="banner">
      <div className="banner-top">
        <span className="label">Premium · {cadenceLabel}</span>
        <span className={'status-pill ' + portfolio.verdict}>
          {statusLabel} · {(portfolio.onTrack * 100).toFixed(0)}% of pace
        </span>
      </div>

      <div className="banner-mid">
        <div className="hero-block">
          <div className="hero">{fmt$(portfolio.collected)}</div>
          <div className="hero-row">
            <span>of {fmtK(portfolio.target)} target</span>
            <span className={'wow ' + (wow >= 0 ? '' : 'neg')}>
              <span className="arrow">{wow >= 0 ? '↑' : '↓'}</span>
              <span className="v">{Math.abs(wow).toFixed(1)}%</span> vs last wk
            </span>
          </div>
        </div>

        <div className="chart-block">
          <div className="chart-head">
            <span className="label">Weekly premium · 13 wks</span>
            <span className="legend">
              target <span className="dash" /> {fmt$(weeklyTarget)}
            </span>
          </div>
          <div className="bar-chart">
            {weeklyHistory.map((w, i) => {
              const isThis = i === weeklyHistory.length - 1;
              const r = weeklyTarget > 0 ? w.premium / weeklyTarget : 0;
              const cls = isThis ? 'this' : r >= 1 ? 'good' : r >= 0.7 ? 'warn' : 'bad';
              const heightPct = (w.premium / max) * 100;
              return (
                <div
                  key={w.w}
                  className={'bar ' + cls}
                  style={{ height: heightPct + '%' }}
                  title={`${w.w}: ${fmt$(w.premium)}`}
                />
              );
            })}
            <span
              className="target-line"
              style={{ bottom: (weeklyTarget / max) * 100 + '%' }}
            />
          </div>
        </div>
      </div>

      <div className="banner-bottom">
        <div className="stat">
          <div className="k">This week</div>
          <div className="v neon">{fmt$(thisWeek.premium)}</div>
          <div className="sub">premium collected</div>
        </div>
        <div className="stat">
          <div className="k">Share P&amp;L</div>
          <div className={'v ' + (portfolio.sharePL >= 0 ? 'pos' : 'neg')}>
            {fmtKSigned(portfolio.sharePL)}
          </div>
          <div className="sub">+{fmtK(portfolio.realizedGains || 0)} realized</div>
        </div>
        <div className="stat">
          <div className="k">Total profit</div>
          <div className={'v ' + (portfolio.total >= 0 ? 'pos' : 'neg')}>
            {fmtKSigned(portfolio.total)}
          </div>
          <div className="sub">premium + shares</div>
        </div>
        <div className="stat">
          <div className="k">Capital deployed</div>
          <div className="v">{fmtK(portfolio.cost)}</div>
          <div className="sub">{fmtK(cashAvailable)} dry powder</div>
        </div>
      </div>
    </div>
  );
}
