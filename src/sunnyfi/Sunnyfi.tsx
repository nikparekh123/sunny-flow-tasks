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
import { lazy, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import './sunnyfi.css';
import RequireAuth from './components/RequireAuth';

const Landing      = lazy(() => import('./pages/Landing'));
const Dashboard    = lazy(() => import('./pages/Dashboard'));
const AuthCallback = lazy(() => import('./pages/AuthCallback'));
const Index        = lazy(() => import('./pages/Index'));
const Reader       = lazy(() => import('./pages/Reader'));
const TagArea      = lazy(() => import('./pages/TagArea'));

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
      …
    </div>
  );
}

export default function Sunnyfi() {
  return (
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
      </Routes>
    </Suspense>
  );
}
