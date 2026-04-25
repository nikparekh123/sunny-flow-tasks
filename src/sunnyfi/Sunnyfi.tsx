/**
 * Entry point for the sunnyfi.co (research-hub) app inside the merged repo.
 * The hostname switch in App.tsx renders this when host is sunnyfi.co or
 * www.sunnyfi.co. Lazy-loaded so todos / positions don't pull this code or
 * its CSS bundle.
 */
import { Routes, Route } from 'react-router-dom';
import './sunnyfi.css';
import Landing from './pages/Landing';
import Dashboard from './pages/Dashboard';
import AuthCallback from './pages/AuthCallback';
import Index from './pages/Index';
import Reader from './pages/Reader';
import RequireAuth from './components/RequireAuth';

export default function Sunnyfi() {
  return (
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
        path="/research/reports/:id"
        element={
          <RequireAuth>
            <Reader />
          </RequireAuth>
        }
      />
    </Routes>
  );
}
