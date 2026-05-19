import { lazy, Suspense } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { SpeedInsights } from '@vercel/speed-insights/react';
import { Toaster as Sonner } from '@/components/ui/sonner';
import { Toaster } from '@/components/ui/toaster';
import { TooltipProvider } from '@/components/ui/tooltip';
import { AuthProvider } from '@/hooks/useAuth';
import Index from './pages/Index.tsx';
const RulesPage = lazy(() => import('./pages/RulesPage.tsx'));
const NotFound = lazy(() => import('./pages/NotFound.tsx'));

// One repo serves three apps via different hostnames:
//   sunnyfi.co / www.sunnyfi.co → Sunnyfi (Landing, Dashboard, Research, …)
//   todos.sunnyfi.co            → Tasks (default)
//   positions.sunnyfi.co        → Positions
// Hostname is detected at first paint; each app is lazy-loaded so users
// only download the bundle for the host they're on.
const PositionsPage = lazy(() => import('./positions/PositionsPage'));
const EarningsPage = lazy(() => import('./earnings/EarningsPage'));
const Sunnyfi = lazy(() => import('./sunnyfi/Sunnyfi'));

type App = 'tasks' | 'positions' | 'sunnyfi';

function detectApp(): App {
  if (typeof window === 'undefined') return 'tasks';
  // Local dev: ?app=positions / ?app=sunnyfi overrides hostname detection.
  const override = new URLSearchParams(window.location.search).get('app');
  if (override === 'positions' || override === 'sunnyfi' || override === 'tasks') {
    return override;
  }
  const h = window.location.hostname;
  if (h.startsWith('positions.')) return 'positions';
  if (h.startsWith('todos.')) return 'tasks';
  if (h === 'sunnyfi.co' || h === 'www.sunnyfi.co') return 'sunnyfi';
  // Anything else (localhost, preview deploys) defaults to the tasks app.
  return 'tasks';
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, refetchOnWindowFocus: false },
  },
});

const SuspenseFallback = () => (
  <div
    className="flex min-h-screen items-center justify-center"
    style={{ backgroundColor: 'var(--owl-page)' }}
  >
    <p style={{ color: 'var(--owl-text-muted)', fontSize: 13 }}>Loading…</p>
  </div>
);

function TasksApp() {
  return (
    <Suspense fallback={<SuspenseFallback />}>
      <Routes>
        <Route path="/" element={<Index />} />
        <Route path="/rules" element={<RulesPage />} />
        <Route path="*" element={<NotFound />} />
      </Routes>
    </Suspense>
  );
}

const App = () => {
  const which = detectApp();

  let content: React.ReactNode;
  if (which === 'positions') {
    // The positions hostname serves /positions (default) and /earnings as
    // sibling routes. They share the same auth, hostname, and design tokens.
    content = (
      <Suspense fallback={<SuspenseFallback />}>
        <Routes>
          <Route path="/earnings/*" element={<EarningsPage />} />
          <Route path="*" element={<PositionsPage />} />
        </Routes>
      </Suspense>
    );
  } else if (which === 'sunnyfi') {
    content = (
      <Suspense fallback={<SuspenseFallback />}>
        <Sunnyfi />
      </Suspense>
    );
  } else {
    content = <TasksApp />;
  }

  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <BrowserRouter>{content}</BrowserRouter>
          <SpeedInsights />
        </TooltipProvider>
      </AuthProvider>
    </QueryClientProvider>
  );
};

export default App;
