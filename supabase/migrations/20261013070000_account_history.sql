-- Block 02b (account chart): one row per trading day, rebuilt each morning
-- after IBKR's statement lands (sunny-home, mode 'history'). The payload adds
-- today's live point on every tick.
create table if not exists public.account_history (
  day date primary key,
  nav numeric not null,            -- both accounts, IBKR close
  cash numeric,
  margin numeric,                  -- nav + net borrowed (Nik, 13 Oct 2026)
  interest_cum numeric, commission_cum numeric, dividends_cum numeric,   -- since the book's start
  realized_cum numeric,            -- PNL_GLOSSARY REALIZED since the book's start
  unrealized numeric,              -- paper P&L at the close (level)
  time_value numeric,              -- left in the options sold, at the close
  capital_long numeric,            -- cost of the long options held: the Sold/Bought return divisor
  shares_value numeric,
  groups jsonb not null,           -- per group: line (P&L since start), realized_cum, unrealized, time_value, mv
  built_at timestamptz not null default now()
);
alter table public.account_history enable row level security;
drop policy if exists "account_history readable to authenticated" on public.account_history;
create policy "account_history readable to authenticated" on public.account_history
  for select to authenticated using (true);
grant select on public.account_history to authenticated;
grant all on public.account_history to service_role;

-- Dividends received per day, both accounts (Change in NAV), for the chart.
create or replace view public.account_value_daily with (security_invoker = on) as
  select report_date,
         count(*) as accounts,
         sum(nav) as nav, sum(cash) as cash, sum(stock) as stock, sum(options) as options,
         sum(interest_accruals) as interest_accruals,
         sum(mtm) as mtm, sum(deposits_withdrawals) as deposits_withdrawals,
         sum(interest) as interest, sum(interest_accrued) as interest_accrued,
         sum(commissions) as commissions, sum(other_fees) as other_fees,
         sum(commissions_mtd) as commissions_mtd, sum(broker_interest_mtd) as broker_interest_mtd,
         sum(coalesce(dividends, 0)) as dividends
  from public.account_daily
  group by report_date;

-- The old vault entry the scheduler used (an sb_secret key in "<...>") was
-- deleted on 13 Oct 2026 once nothing read it; the scheduler uses cron_secret.
delete from vault.secrets where name = 'service_role_key';

-- Rebuilt after each morning account sync (6:30 and 9:30 ET).
select cron.unschedule(jobid) from cron.job where jobname = 'account-history-daily';
select cron.schedule('account-history-daily', '45 10,13 * * *',
  $$ SELECT public.cron_invoke_function_body('sunny-home', '{"mode":"history"}'::jsonb, 120000) $$);
