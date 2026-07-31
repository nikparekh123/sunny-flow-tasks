-- Technical stats per ticker for the Planner's Upside Room card.
-- ath/ath_date come from the full adjusted history; the trailing figures
-- (52w range, moving averages, RSI) are recomputed on each refresh.
create table if not exists public.ticker_stats (
  ticker     text primary key,
  high_52w   double precision,
  low_52w    double precision,
  ma50       double precision,
  ma200      double precision,
  rsi14      double precision,
  ath        double precision,
  ath_date   date,
  updated_at timestamptz not null default now()
);
alter table public.ticker_stats enable row level security;
drop policy if exists "read ticker_stats" on public.ticker_stats;
create policy "read ticker_stats" on public.ticker_stats
  for select using (auth.role() = 'authenticated');
