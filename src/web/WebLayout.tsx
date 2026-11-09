// The frame every signed-in page sits in: the page background and glow, the shared SVG gradients, the fixed header,
// and the Time value sheet on top when it is open. It also reads every page's code ahead, and keeps the scroll:
// a new page opens at its top, Back returns to where that page was left, and a name switch inside a page stays put.
import { lazy, Suspense, useEffect, useLayoutEffect, useRef } from 'react';
import { Outlet, useLocation, useNavigationType } from 'react-router-dom';
import './web.css';
import { Header } from './components/Header';
import { WebStateProvider, useWeb } from './lib/state';
import { page, preloadPages } from './pages/load';

const TimeValueSheet = lazy(page.TimeValue);

/** Scroll per history entry: Back and Forward return to it; opening another page starts at its top; moving
    inside one page (one name to the next on Positions) keeps the place. */
function useScrollKeeper() {
  const loc = useLocation();
  const how = useNavigationType();
  const at = useRef(new Map<string, number>());
  const cur = useRef(loc.key);
  const seg = useRef(loc.pathname.split('/')[1]);
  // One listener; it writes to the entry on screen. The entry changes in the commit (below), so a scroll the browser
  // makes after a page change is the new page's, never the one just left.
  useEffect(() => {
    try { window.history.scrollRestoration = 'manual'; } catch { /* older browsers */ }
    const save = () => at.current.set(cur.current, window.scrollY);
    window.addEventListener('scroll', save, { passive: true });
    return () => window.removeEventListener('scroll', save);
  }, []);
  useLayoutEffect(() => {
    if (cur.current === loc.key) return;
    const s = loc.pathname.split('/')[1], moved = s !== seg.current;
    seg.current = s;
    cur.current = loc.key;
    const y = at.current.get(loc.key);
    if (how === 'POP' && y != null) window.scrollTo(0, y);
    else if (moved) window.scrollTo(0, 0);
  }, [loc.key]); // eslint-disable-line react-hooks/exhaustive-deps
}

function Sheet() {
  const { tvOpen } = useWeb();
  if (!tvOpen) return null;
  return <Suspense fallback={null}><TimeValueSheet /></Suspense>;
}

export default function WebLayout() {
  useScrollKeeper();
  useEffect(() => {
    const w = window as unknown as { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number };
    const go = () => (w.requestIdleCallback ? w.requestIdleCallback(preloadPages, { timeout: 3000 }) : preloadPages());
    const tm = setTimeout(go, 800);
    return () => clearTimeout(tm);
  }, []);
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
