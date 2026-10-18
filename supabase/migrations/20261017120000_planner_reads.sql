-- NKE WEEKLY RULE, step 2 (Nik, 17 Oct 2026): the server works out the reads each
-- day (docs/STRATEGIES.md "NKE weekly rule (trial)"). Written by ticker-technicals.
-- Market data, not personal: readable by any signed-in login.

alter table public.ticker_technicals
  add column if not exists hv20_ex numeric,   -- realised volatility, 20 sessions, earnings report day + next session left out (the IV check)
  add column if not exists high5   numeric,   -- highest high of the last 5 sessions (breakout week: sell above it)
  add column if not exists reads   jsonb;     -- that day's reads {factor: {read, line}}; written on the latest day only, a past day never changes

create table if not exists public.ticker_fundamentals (
  ticker         text not null,
  day            date not null,
  analyst_target numeric,                    -- Nasdaq consensus price target
  analyst_low    numeric,
  analyst_high   numeric,
  n_buy          int, n_hold int, n_sell int,
  model_value    numeric,                    -- Nik's weekly model number (fair value screenshot), carried until the next one
  model_day      date,                       -- the day that model number was given
  updated_at     timestamptz not null default now(),
  primary key (ticker, day)
);

alter table public.ticker_fundamentals enable row level security;
create policy "ticker_fundamentals: signed-in read" on public.ticker_fundamentals for select to authenticated using (true);
