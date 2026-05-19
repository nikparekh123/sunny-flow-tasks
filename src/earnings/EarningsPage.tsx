import { Route, Routes } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { useEarnings } from './useEarnings';
import { EarningsFeed } from './EarningsFeed';
import { TickerHub } from './TickerHub';
import { EventDetail } from './EventDetail';
import { Link, useLocation } from 'react-router-dom';
import './earnings.css';
import '../positions/positions.css'; // shared np-* design tokens (buttons, inputs, hero)

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';

export default function EarningsPage() {
  const { user, loading } = useAuth();
  if (loading) {
    return (
      <div className="np-app" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <p style={{ color: 'var(--navi-fg3)', fontSize: 13 }}>Loading…</p>
      </div>
    );
  }
  if (!user) return <Auth />;
  return <EarningsShell />;
}

function EarningsShell() {
  const { upcomingFeed, isLoading } = useEarnings();
  const loc = useLocation();
  // Active-nav helper: highlight the matching top-link.
  const isEarnings = loc.pathname.startsWith('/earnings');

  return (
    <div className="np-app">
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <Link to="/positions" className={'np-crumb-link' + (!isEarnings ? ' on' : '')}>
            POSITIONS
          </Link>
          <span className="np-crumb-sep">/</span>
          <Link to="/earnings" className={'np-crumb-link' + (isEarnings ? ' on' : '')}>
            EARNINGS
          </Link>
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
