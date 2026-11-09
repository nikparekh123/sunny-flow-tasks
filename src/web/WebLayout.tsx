// The frame every signed-in page sits in: the page background and glow, the shared SVG gradients, the fixed header,
// and the Time value sheet on top when it is open.
import { lazy, Suspense } from 'react';
import { Outlet } from 'react-router-dom';
import './web.css';
import { Header } from './components/Header';
import { WebStateProvider, useWeb } from './lib/state';

const TimeValueSheet = lazy(() => import('./sheets/TimeValueSheet'));

function Sheet() {
  const { tvOpen } = useWeb();
  if (!tvOpen) return null;
  return <Suspense fallback={null}><TimeValueSheet /></Suspense>;
}

export default function WebLayout() {
  return (
    <WebStateProvider>
      <div className="sw">
        <div className="sw-ambient" aria-hidden="true" />
        {/* The payoff fills every chart shares (README "Payoff fills"). */}
        <svg width="0" height="0" aria-hidden="true" style={{ position: 'absolute' }}>
          <defs>
            <linearGradient id="sunGU" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#65C466" stopOpacity=".42" /><stop offset="1" stopColor="#65C466" stopOpacity=".02" /></linearGradient>
            <linearGradient id="sunGD" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FF6961" stopOpacity=".02" /><stop offset="1" stopColor="#FF6961" stopOpacity=".42" /></linearGradient>
          </defs>
        </svg>
        <Header />
        <div className="sw-page">
          <Outlet />
        </div>
        <Sheet />
      </div>
    </WebStateProvider>
  );
}

/** Content width under 1180 px: the Positions rail leaves the side for the main column (README 1). */
export const NARROW_QUERY = '(max-width: 1275px)';
