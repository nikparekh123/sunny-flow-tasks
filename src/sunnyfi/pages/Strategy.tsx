/**
 * Strategy — SWM-style bucket dashboard.
 *
 * v2 note: /strategy/gains has been retired. The gains log is moving to
 * /positions in the Positions v2 redesign. This route just renders the
 * bucket dashboard and the cadence + back-to-dashboard appbar.
 */
import { useSearchParams } from 'react-router-dom';
import { useStrategy } from '../strategy/useStrategy';
import StrategyDashboard from '../strategy/pages/StrategyDashboard';
import type { Cadence } from '../strategy/calc';
import '@/sunnyfi/strategy.css';

const CADENCES: Cadence[] = ['month', 'quarter', 'year'];
const CADENCE_LABEL: Record<Cadence, string> = {
  month: 'Month',
  quarter: 'Quarter',
  year: 'Year',
};

export default function Strategy() {
  const s = useStrategy();
  const [params, setParams] = useSearchParams();

  const cadenceParam = (params.get('cadence') as Cadence) || 'quarter';
  const cadence: Cadence = CADENCES.includes(cadenceParam) ? cadenceParam : 'quarter';

  if (s.isLoading) {
    return (
      <div className="swm-app">
        <div className="swm-appbar">
          <span className="brand">
            Sunnyfi<span className="cursor" />
          </span>
          <span className="crumb">Strategy</span>
        </div>
        <div style={{ padding: 32, color: 'var(--navi-fg3)' }}>Loading…</div>
      </div>
    );
  }

  const setCadence = (c: Cadence) => {
    const p = new URLSearchParams(params);
    p.set('cadence', c);
    setParams(p, { replace: true });
  };

  return (
    <div className="swm-app">
      <div className="swm-appbar">
        <span className="brand">
          Sunnyfi<span className="cursor" />
        </span>
        <span className="crumb">Strategy</span>
        <div className="right">
          <div className="view-toggle" role="group" aria-label="Cadence">
            {CADENCES.map((c) => (
              <button
                key={c}
                className={cadence === c ? 'on' : ''}
                onClick={() => setCadence(c)}
              >
                {CADENCE_LABEL[c]}
              </button>
            ))}
          </div>
          <span className="live-dot">Live</span>
        </div>
      </div>

      <StrategyDashboard cadence={cadence} />
    </div>
  );
}
