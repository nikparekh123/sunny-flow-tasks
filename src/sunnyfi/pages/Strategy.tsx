/**
 * Strategy — SWM-style bucket dashboard.
 *
 * Header matches Positions: np-app shell, np-top breadcrumbs with
 * Sunnyfi-wordmark linking back to the dashboard. Cadence is fixed at
 * 'quarter'; the previous month/quarter/year toggle + Live dot were
 * removed.
 */
import { useStrategy } from '../strategy/useStrategy';
import StrategyDashboard from '../strategy/pages/StrategyDashboard';
import '@/positions/positions.css';
import '@/sunnyfi/strategy.css';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';

export default function Strategy() {
  const s = useStrategy();

  return (
    <div className="np-app">
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">STRATEGY</span>
        </div>
      </header>

      <div className="np-stage">
        {s.isLoading ? (
          <div style={{ padding: 32, color: 'var(--navi-fg3)' }}>Loading…</div>
        ) : (
          <StrategyDashboard cadence="quarter" />
        )}
      </div>
    </div>
  );
}
