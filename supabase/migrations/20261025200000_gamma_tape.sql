-- Handoff 32 (Gamma tab): the options tape, classified by side, and what it says about dealers.
--
-- tape_contract_day   one row per contract per session: volume, the customer side (bought at or over the
--                     ask, sold at or under the bid, between counted in part, mid unclassified), and the
--                     open interest that morning. Strikes within 40% of the price only.
-- tape_expiry_day     the same session per expiry: trades, small trades, the size mix and the print types
--                     (single-leg, multi-leg, tied-to-stock, auction or cross, other), for coverage and the
--                     flow profile.
-- dealer_pos          the running dealer position per contract (the latest only): the tape's net since the
--                     backfill start plus an open-interest-model seed for what was open before it, never
--                     more than open interest.
-- gamma_view_day      what the Gamma page reads: per name, per session, per view (an expiry, 'weeklies',
--                     'all'), the walls with tape labels and confidence, the OI model's label, flip, regime.
create table if not exists public.tape_contract_day (
  ticker text not null, day date not null, expiry date not null, strike numeric not null, cp text not null,
  vol integer not null default 0, cust_buy numeric not null default 0, cust_sell numeric not null default 0,
  unclassified numeric not null default 0, oi integer,
  primary key (ticker, day, expiry, strike, cp)
);
create table if not exists public.tape_expiry_day (
  ticker text not null, day date not null, expiry date not null,
  vol integer not null default 0, classified numeric not null default 0, trades integer not null default 0,
  small_trades integer not null default 0, call_vol integer not null default 0, put_vol integer not null default 0,
  sizes jsonb, v_single integer not null default 0, v_multi integer not null default 0, v_tied integer not null default 0,
  v_auction integer not null default 0, v_other integer not null default 0, built_at timestamptz not null default now(),
  primary key (ticker, day, expiry)
);
create table if not exists public.dealer_pos (
  ticker text not null, expiry date not null, strike numeric not null, cp text not null,
  pos numeric not null default 0, seed numeric not null default 0, tape_vol numeric not null default 0,
  classified_vol numeric not null default 0, oi integer, asof date not null,
  primary key (ticker, expiry, strike, cp)
);
create table if not exists public.gamma_view_day (
  ticker text not null, day date not null, view text not null, built_at timestamptz not null default now(),
  data jsonb not null,
  primary key (ticker, day, view)
);
create index if not exists tape_contract_day_tk on public.tape_contract_day (ticker, expiry, day);
alter table public.tape_contract_day enable row level security;
alter table public.tape_expiry_day enable row level security;
alter table public.dealer_pos enable row level security;
alter table public.gamma_view_day enable row level security;
drop policy if exists gamma_view_day_read on public.gamma_view_day;
create policy gamma_view_day_read on public.gamma_view_day for select to authenticated using (true);
