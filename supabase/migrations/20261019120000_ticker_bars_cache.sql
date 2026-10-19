-- Daily price history cache for ticker-technicals (19 Oct 2026). Reading every held name's two years of
-- Polygon bars every 15 minutes hit Polygon's per-minute limit (429 after 6 names). Bars are fetched once
-- a day per name and kept here; the 15-minute runs add the live price as today's close.
create table if not exists public.ticker_bars (
  ticker     text primary key,
  asof       date not null,              -- New York date of the fetch
  bars       jsonb not null,             -- [[t_ms, o, h, l, c, v], ...] oldest first, split-adjusted
  fetched_at timestamptz not null default now()
);
alter table public.ticker_bars enable row level security;
