import { Link, Route, Routes, useLocation } from 'react-router-dom';
import { useEarnings } from './useEarnings';
import { EarningsFeed } from './EarningsFeed';
import { TickerHub } from './TickerHub';
import { EventDetail } from './EventDetail';
import './earnings.css';
import '../positions/positions.css'; // shared np-* design tokens (buttons, inputs, hero shell)

const DASHBOARD_URL = '/dashboard';

/**
 * /earnings lives inside the Sunnyfi app (sunnyfi.co/earnings), alongside
 * /strategy and /snowball. Auth is enforced by RequireAuth in Sunnyfi.tsx,
 * so this component doesn't gate on user itself.
 */
export default function EarningsPage() {
  return <EarningsShell />;
}

function EarningsShell() {
  const { upcomingFeed, isLoading } = useEarnings();
  const loc = useLocation();
  const onLanding = loc.pathname === '/earnings' || loc.pathname === '/earnings/';

  return (
    <div className="np-app">
      <header className="np-top">
        <div className="np-brand-row">
          <Link className="np-brand" to={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </Link>
          <span className="np-crumb-sep">/</span>
          {onLanding ? (
            <span className="np-crumb">EARNINGS</span>
          ) : (
            <Link to="/earnings" className="np-crumb-link on">EARNINGS</Link>
          )}
        </div>
      </header>

      <div className="np-stage">
        <Routes>
          <Route index element={<EarningsFeed feed={upcomingFeed} loading={isLoading} />} />
          <Route path=":ticker" element={<TickerHub />} />
          <Route path=":ticker/:date" element={<EventDetail />} />
        </Routes>
      </div>
    </div>
  );
}
