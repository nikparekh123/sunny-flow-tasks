-- The 3-month and 12-month upside calls the Planner sizes (handoff 25, 16 Oct 2026).
-- chain-next writes the calls 5% to 50% out of the money on the monthly expiry
-- nearest 91 days (3m) and 365 days (12m) for every held name, every 15 min.
-- Its own table, so the weekly chain readers never see these expiries.
create table if not exists public.option_chain_upside (
  ticker      text        not null,
  tenor       text        not null check (tenor in ('3m', '12m')),
  expiry      date        not null,
  strike      numeric     not null,
  mid         numeric,
  delta       numeric,
  iv          numeric,
  spot        numeric,
  snapshot_at timestamptz not null default now(),
  primary key (ticker, tenor, strike)
);
alter table public.option_chain_upside enable row level security;
