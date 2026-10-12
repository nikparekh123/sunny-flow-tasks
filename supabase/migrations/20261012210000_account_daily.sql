-- The account, from IBKR, one row per account per trading day.
--
-- ⚠ TWO ACCOUNTS, ONE BOOK (Nik, 12 Oct 2026). The main account (...475)
-- reports about $769K and the second (...9479) about -$672K of cash; IBKR
-- cannot fix the split. The real account value is the SUM of the two
-- (~$97K on 9 Oct). Never show either alone. `account_value_daily` adds them
-- and says how many accounts it found, so a day missing one is visible.
--
-- Fed by ibkr-account-sync from the Activity Flex query "Sunny account"
-- (1670350): NAV in Base, Change in NAV, Cash Report, Interest Accruals,
-- Open Positions, last 30 calendar days, broken out by day.

create table if not exists public.account_daily (
  account_id text not null,
  report_date date not null,
  nav numeric not null,
  cash numeric, stock numeric, options numeric, interest_accruals numeric,
  starting_value numeric, mtm numeric, realized numeric, change_in_unrealized numeric,
  deposits_withdrawals numeric, dividends numeric, interest numeric,
  change_in_interest_accruals numeric, commissions numeric, other_fees numeric, twr numeric,
  interest_accrued numeric,
  commissions_mtd numeric, broker_interest_mtd numeric, other_fees_mtd numeric,
  synced_at timestamptz not null default now(),
  primary key (account_id, report_date)
);

create table if not exists public.account_positions_daily (
  account_id text not null,
  report_date date not null,
  conid text not null,
  symbol text, underlying text, asset_category text, put_call text,
  strike numeric, expiry date, multiplier numeric,
  position numeric, mark_price numeric, position_value numeric,
  cost_basis_money numeric, fifo_pnl_unrealized numeric,
  synced_at timestamptz not null default now(),
  primary key (account_id, report_date, conid)
);
create index if not exists account_positions_daily_date on public.account_positions_daily (report_date);

alter table public.account_daily enable row level security;
alter table public.account_positions_daily enable row level security;
drop policy if exists "account_daily readable to authenticated" on public.account_daily;
create policy "account_daily readable to authenticated" on public.account_daily
  for select to authenticated using (true);
drop policy if exists "account_positions_daily readable to authenticated" on public.account_positions_daily;
create policy "account_positions_daily readable to authenticated" on public.account_positions_daily
  for select to authenticated using (true);
grant select on public.account_daily, public.account_positions_daily to authenticated;
grant all on public.account_daily, public.account_positions_daily to service_role;

create or replace view public.account_value_daily with (security_invoker = on) as
  select report_date,
         count(*) as accounts,
         sum(nav) as nav, sum(cash) as cash, sum(stock) as stock, sum(options) as options,
         sum(interest_accruals) as interest_accruals,
         sum(mtm) as mtm, sum(deposits_withdrawals) as deposits_withdrawals,
         sum(interest) as interest, sum(interest_accrued) as interest_accrued,
         sum(commissions) as commissions, sum(other_fees) as other_fees,
         sum(commissions_mtd) as commissions_mtd, sum(broker_interest_mtd) as broker_interest_mtd
  from public.account_daily
  group by report_date;
grant select on public.account_value_daily to authenticated, service_role;

-- 6:30 and 9:30 ET every day; IBKR's daily statement for the prior day is
-- usually ready by the first, the second catches a late one. Upserts, so
-- running twice is harmless.
select cron.unschedule(jobid) from cron.job where jobname = 'ibkr-account-sync-daily';
select cron.schedule('ibkr-account-sync-daily', '30 10,13 * * *',
  $$ SELECT public.cron_invoke_function('ibkr-account-sync') $$);
