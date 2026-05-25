/**
 * Entry point for the sunnyfi.co (research-hub) app inside the merged repo.
 * The hostname switch in App.tsx renders this when host is sunnyfi.co or
 * www.sunnyfi.co.
 *
 * Each sub-page is lazy-loaded so visiting /research doesn't pay the cost
 * of Reader / Dashboard / Landing / TagArea bundles, etc. Suspense shows a
 * tiny inline fallback during the chunk fetch (usually <100ms on a warm
 * cache).
 */
import { lazy, Suspense, Component, type ReactNode, type ErrorInfo } from 'react';
import { Routes, Route } from 'react-router-dom';
import './sunnyfi.css';
import RequireAuth from './components/RequireAuth';

/**
 * Surfaces unhandled render errors instead of blank-screening — invaluable
 * when a route's render throws and there's no other diagnostic.
 */
interface ErrorState { error: Error | null }
class ErrorBoundary extends Component<{ children: ReactNode }, ErrorState> {
  state: ErrorState = { error: null };
  static getDerivedStateFromError(error: Error): ErrorState { return { error }; }
  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[Sunnyfi ErrorBoundary]', error, info);
  }
  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div
        style={{
          minHeight: '100vh',
          padding: 40,
          background: 'var(--navi-dash-page, #061a10)',
          color: '#e0a060',
          fontFamily: 'var(--navi-font-mono, monospace)',
          fontSize: 13,
          lineHeight: 1.6,
        }}
      >
        <div style={{ fontSize: 11, letterSpacing: 2, textTransform: 'uppercase', color: '#7ab0a5', marginBottom: 16 }}>
          render error
        </div>
        <div style={{ fontSize: 16, color: '#e0a060', marginBottom: 12 }}>
          {this.state.error.name}: {this.state.error.message}
        </div>
        <pre style={{ whiteSpace: 'pre-wrap', fontSize: 11, color: '#7ab0a5', maxHeight: '60vh', overflow: 'auto' }}>
          {this.state.error.stack}
        </pre>
        <button
          onClick={() => { this.setState({ error: null }); window.location.assign('/'); }}
          style={{
            marginTop: 20, padding: '8px 16px', fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase',
            background: 'transparent', border: '1px solid #468278', borderRadius: 4, color: '#c8d7bf', cursor: 'pointer',
          }}
        >
          back to landing
        </button>
      </div>
    );
  }
}

const Landing      = lazy(() => import('./pages/Landing'));
const Dashboard    = lazy(() => import('./pages/Dashboard'));
const AuthCallback = lazy(() => import('./pages/AuthCallback'));
const Index        = lazy(() => import('./pages/Index'));
const Reader       = lazy(() => import('./pages/Reader'));
const TagArea      = lazy(() => import('./pages/TagArea'));
const Snowball     = lazy(() => import('./pages/Snowball'));
const Strategy     = lazy(() => import('./pages/Strategy'));
const NewStrategy  = lazy(() => import('./pages/NewStrategy'));
const MathPage     = lazy(() => import('./pages/Math'));

function PageFallback() {
  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'var(--navi-dash-page, #061a10)',
        color: 'var(--navi-fg3, #468278)',
        fontSize: 13,
        fontFamily: 'var(--navi-font-mono, monospace)',
      }}
    >
      chunk…
    </div>
  );
}

export default function Sunnyfi() {
  return (
    <ErrorBoundary>
    <Suspense fallback={<PageFallback />}>
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route
          path="/dashboard"
          element={
            <RequireAuth>
              <Dashboard />
            </RequireAuth>
          }
        />
        <Route
          path="/research"
          element={
            <RequireAuth>
              <Index />
            </RequireAuth>
          }
        />
        <Route
          path="/research/tags/:tag"
          element={
            <RequireAuth>
              <TagArea />
            </RequireAuth>
          }
        />
        <Route
          path="/research/reports/:id"
          element={
            <RequireAuth>
              <Reader />
            </RequireAuth>
          }
        />
        <Route
          path="/snowball"
          element={
            <RequireAuth>
              <Snowball />
            </RequireAuth>
          }
        />
        <Route
          path="/strategy"
          element={
            <RequireAuth>
              <Strategy />
            </RequireAuth>
          }
        />
        <Route
          path="/new-strategy"
          element={
            <RequireAuth>
              <NewStrategy />
            </RequireAuth>
          }
        />
        <Route
          path="/math"
          element={
            <RequireAuth>
              <MathPage />
            </RequireAuth>
          }
        />
      </Routes>
    </Suspense>
    </ErrorBoundary>
  );
}
