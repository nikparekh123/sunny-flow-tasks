import { lazy, Suspense } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { SpeedInsights } from '@vercel/speed-insights/react';
import { Toaster as Sonner } from '@/components/ui/sonner';
import { Toaster } from '@/components/ui/toaster';
import { TooltipProvider } from '@/components/ui/tooltip';
import { AuthProvider } from '@/hooks/useAuth';

// Every host renders the Sunnyfi app (sunnyfi.co, www.sunnyfi.co, localhost,
// preview deploys). The legacy positions.sunnyfi.co subdomain is bounced to
// www.sunnyfi.co/positions below; ?app=positions (local dev) still renders
// PositionsPage on its own. Each app is lazy-loaded.
const PositionsPage = lazy(() => import('./positions/PositionsPage'));
const Sunnyfi = lazy(() => import('./sunnyfi/Sunnyfi'));

type App = 'positions' | 'sunnyfi';

function detectApp(): App {
  if (typeof window === 'undefined') return 'sunnyfi';
  // Local dev: ?app=positions overrides hostname detection.
  if (new URLSearchParams(window.location.search).get('app') === 'positions') return 'positions';
  if (window.location.hostname.startsWith('positions.')) return 'positions';
  return 'sunnyfi';
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

const App = () => {
  const which = detectApp();

  // Positions has moved into the main app at sunnyfi.co/positions. Bounce the
  // legacy positions.sunnyfi.co subdomain there so there's one origin/shell.
  // (The ?app=positions local-dev override still renders PositionsPage directly.)
  if (
    which === 'positions' &&
    typeof window !== 'undefined' &&
    window.location.hostname.startsWith('positions.')
  ) {
    window.location.replace('https://www.sunnyfi.co/positions' + window.location.search);
    return null;
  }

  const content =
    which === 'positions' ? (
      <Suspense fallback={<SuspenseFallback />}>
        <Routes>
          <Route path="*" element={<PositionsPage />} />
        </Routes>
      </Suspense>
    ) : (
      <Suspense fallback={<SuspenseFallback />}>
        <Sunnyfi />
      </Suspense>
    );

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
