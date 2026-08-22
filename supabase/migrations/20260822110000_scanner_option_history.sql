/* ============================================================
   scanner_option_history, the option market's trend

   income-scanner already reads open interest and volume across the strikes
   around the money on every run, uses them for the liquidity gate, and keeps
   only today's figure. So the question a weekly writer most needs answered
   cannot be asked: is the option market in this name BUILDING or LEAVING?

   A thinning market is a real risk. It shows up first as open interest
   draining, long before a spread becomes obviously bad, and today there is no
   way to see it coming.

   One row per name per scan date. Written from data already in hand, so it
   costs one round trip and no extra Polygon calls.
   ============================================================ */

create table if not exists public.scanner_option_history (
  ticker      text    not null,
  asof        date    not null,
  expiry      date,
  spot        numeric,
  option_oi   integer,          -- summed across +/-5% of spot, both legs
  option_vol  integer,
  straddle_pct numeric,         -- what a week costs, as a % of spot
  implied_vol numeric,
  primary key (ticker, asof)
);

create index if not exists scanner_option_history_ticker_idx
  on public.scanner_option_history (ticker, asof desc);

comment on table public.scanner_option_history is
  'Daily option-market readings per name from income-scanner: open interest and '
  'volume across the money, plus the straddle and implied vol. For trend, the '
  'liquidity GATE reads the live figure instead.';

alter table public.scanner_option_history enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='scanner_option_history' and policyname='soh_auth_read') then
    create policy soh_auth_read on public.scanner_option_history
      for select to authenticated using (true);
  end if;
end $$;

notify pgrst, 'reload schema';
