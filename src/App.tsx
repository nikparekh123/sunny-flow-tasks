import { lazy, Suspense } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { Toaster as Sonner } from '@/components/ui/sonner';
import { Toaster } from '@/components/ui/toaster';
import { TooltipProvider } from '@/components/ui/tooltip';
import { AuthProvider } from '@/hooks/useAuth';
import Index from './pages/Index.tsx';
import RulesPage from './pages/RulesPage.tsx';
import NotFound from './pages/NotFound.tsx';

// One repo serves two apps via different subdomains:
//   todos.sunnyfi.co     → tasks (default)
//   positions.sunnyfi.co → positions
// Detected by hostname so users see clean URLs and never the other app.
const PositionsPage = lazy(() => import('./positions/PositionsPage'));

function isPositionsHost(): boolean {
  if (typeof window === 'undefined') return false;
  const h = window.location.hostname;
  if (h.startsWith('positions.')) return true;
  // Local dev: ?app=positions overrides so we can test without DNS.
  const params = new URLSearchParams(window.location.search);
  return params.get('app') === 'positions';
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
  const positions = isPositionsHost();

  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <BrowserRouter>
            {positions ? (
              <Suspense fallback={<SuspenseFallback />}>
                <Routes>
                  <Route path="*" element={<PositionsPage />} />
                </Routes>
              </Suspense>
            ) : (
              <Routes>
                <Route path="/" element={<Index />} />
                <Route path="/rules" element={<RulesPage />} />
                <Route path="*" element={<NotFound />} />
              </Routes>
            )}
          </BrowserRouter>
        </TooltipProvider>
      </AuthProvider>
    </QueryClientProvider>
  );
};

export default App;
