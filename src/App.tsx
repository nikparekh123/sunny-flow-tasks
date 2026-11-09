// sunnyfi.co: the Sunny web (handoff 2026-11-08-web). Every older page (Dashboard, Income, Portfolio, the old
// Positions, Payoff, Ask, Health) was removed on 9 Nov 2026 (Nik); their code is in git history.
import { lazy, Suspense } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { SpeedInsights } from '@vercel/speed-insights/react';
import { RequireAuth } from './web/components/RequireAuth';

const Login = lazy(() => import('./web/pages/Login'));
const WebLayout = lazy(() => import('./web/WebLayout'));
const Home = lazy(() => import('./web/pages/Home'));
const Positions = lazy(() => import('./web/pages/Positions'));
const Overview = lazy(() => import('./web/pages/Overview'));
const Ticker = lazy(() => import('./web/pages/Ticker'));

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000, refetchOnWindowFocus: false, retry: 1 } },
});

const Blank = () => <div style={{ minHeight: '100vh', background: '#000000' }} />;

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Suspense fallback={<Blank />}>
          <Routes>
            <Route path="/" element={<Login />} />
            <Route element={<RequireAuth><WebLayout /></RequireAuth>}>
              <Route path="/home" element={<Home />} />
              <Route path="/positions" element={<Positions />} />
              <Route path="/positions/:t" element={<Positions />} />
              <Route path="/overview" element={<Overview />} />
              <Route path="/t/:ticker" element={<Ticker />} />
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Suspense>
      </BrowserRouter>
      <SpeedInsights />
    </QueryClientProvider>
  );
}
