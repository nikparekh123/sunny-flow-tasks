-- The hedge rungs (Nik, 26 Oct 2026): hedge calls and insurance puts sit on two monthly expiries, a near rung
-- 45 to 90 days out and a far rung 90 to 180 days out, any monthly. chain-next writes every monthly 40 to 185 days
-- out for every held name, calls 1x to 1.8x the price and puts 0.6x to 1x, from one Theta request per name.
-- Its own table, so the weekly chain readers never see these expiries.
create table if not exists public.option_chain_hedge (
  ticker      text        not null,
  expiry      date        not null,
  side        text        not null check (side in ('call', 'put')),
  strike      numeric     not null,
  mid         numeric,
  delta       numeric,
  iv          numeric,
  spot        numeric,
  snapshot_at timestamptz not null default now(),
  primary key (ticker, expiry, side, strike)
);
alter table public.option_chain_hedge enable row level security;
