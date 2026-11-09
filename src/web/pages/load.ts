// Each signed-in page's code. A page loads on first use, and every page is read ahead once the first one is up
// (WebLayout), so moving between pages never waits on code (Nik, 9 Nov 2026: smooth, "do a lazy load").
export const page = {
  Home: () => import('./Home'),
  Positions: () => import('./Positions'),
  Overview: () => import('./Overview'),
  Ticker: () => import('./Ticker'),
  TimeValue: () => import('../sheets/TimeValueSheet'),
};

export function preloadPages() {
  for (const f of Object.values(page)) void f().catch(() => { /* loads again on first use */ });
}
