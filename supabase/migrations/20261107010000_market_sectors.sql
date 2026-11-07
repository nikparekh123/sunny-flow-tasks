-- New Home (handoff 6 Nov 2026, Pass 2): sectors, heat maps and the week's moves, from Yahoo via market-tape.
--
-- market_sectors: the 11 sector SPDRs and the 12 biggest names in each (tile area = market cap, colour = move).
-- Written by market-tape every 30 s with market_live; read by sunny-home (service role) only, so RLS is on with
-- no policy.
--
-- week_base / week_start on both tables: the last close before this week's Monday, so "The week" cards and the
-- week's heat maps read price / week_base - 1. market-tape refills it once a week per symbol.

create table if not exists public.market_sectors (
  symbol          text primary key,
  sector          text not null,
  etf             boolean not null default false,
  name            text not null,
  market_cap      numeric,
  price           numeric,
  prev_close      numeric,
  day_pct         numeric,
  market_state    text,
  regular_time    timestamptz,
  week_base       numeric,
  week_base_date  date,
  week_start      date,
  captured_at     timestamptz not null default now()
);
alter table public.market_sectors enable row level security;

alter table public.market_live add column if not exists week_base numeric;
alter table public.market_live add column if not exists week_base_date date;
alter table public.market_live add column if not exists week_start date;

-- Your names before the bell and after hours (kind 'name': the books' tickers, read from ticker_quotes_live),
-- and each quote's market cap (the Watchlist heat map's tile area).
alter table public.market_live add column if not exists market_cap numeric;
alter table public.market_live drop constraint if exists market_live_kind_check;
alter table public.market_live add constraint market_live_kind_check
  check (kind = any (array['index', 'vix', 'global', 'watch', 'future', 'name']));
