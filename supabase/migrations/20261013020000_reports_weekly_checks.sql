-- Saved weekly/monthly reports (block 06: "save each report so history can
-- come later"), each week's index move against its priced move (block 09,
-- Last week), and the Theta check's findings (block 07).

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('weekly', 'monthly')),
  period_start date not null,
  period_end date not null,
  shown_on date not null,
  payload jsonb not null,
  built_at timestamptz not null default now(),
  unique (kind, period_start)
);

create table if not exists public.index_weekly (
  week_start date not null,
  symbol text not null,
  prior_close_date date, close_date date,
  prior_close numeric, close numeric, change_pct numeric,
  expiry date, atm_strike numeric, straddle numeric, priced_move_pct numeric,
  built_at timestamptz not null default now(),
  primary key (week_start, symbol)
);

create table if not exists public.theta_checks (
  id uuid primary key default gen_random_uuid(),
  ticker text not null,
  option_type text not null,
  strike numeric not null,
  expiry date not null,
  contracts numeric not null,
  status text not null default 'open' check (status in ('open', 'resolved')),
  trigger text not null check (trigger in ('growth', 'ratio')),
  found_on date not null,
  card_on date not null,
  theta_now numeric, theta_then numeric, then_date date, growth_pct numeric,
  ratio_now numeric, ratio_without numeric, ratio_at_card numeric,
  roll jsonb,
  last_checked date,
  resolved_on date, resolved_why text
);
create unique index if not exists theta_checks_one_open
  on public.theta_checks (ticker, option_type, strike, expiry) where status = 'open';

alter table public.reports enable row level security;
alter table public.index_weekly enable row level security;
alter table public.theta_checks enable row level security;
drop policy if exists "reports readable to authenticated" on public.reports;
create policy "reports readable to authenticated" on public.reports for select to authenticated using (true);
drop policy if exists "index_weekly readable to authenticated" on public.index_weekly;
create policy "index_weekly readable to authenticated" on public.index_weekly for select to authenticated using (true);
drop policy if exists "theta_checks readable to authenticated" on public.theta_checks;
create policy "theta_checks readable to authenticated" on public.theta_checks for select to authenticated using (true);
grant select on public.reports, public.index_weekly, public.theta_checks to authenticated;
grant all on public.reports, public.index_weekly, public.theta_checks to service_role;

/* cron_invoke_function with a body: the Theta check is sunny-home in
   mode 'theta_check'. Fires at 20:25 and 21:25 UTC (EDT and EST); the
   function runs once, after 4:15 New York. */
create or replace function public.cron_invoke_function_body(p_name text, p_body jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare svc_key text; req_id bigint;
begin
  select decrypted_secret into svc_key from vault.decrypted_secrets where name = 'service_role_key' limit 1;
  if svc_key is null then raise notice 'cron_invoke_function_body(%): no service_role_key', p_name; return null; end if;
  select net.http_post(
    url := 'https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/' || p_name,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || svc_key),
    body := p_body, timeout_milliseconds := 60000) into req_id;
  return req_id;
end $$;
select cron.unschedule(jobid) from cron.job where jobname = 'theta-check-close';
select cron.schedule('theta-check-close', '25 20,21 * * 1-5',
  $$ SELECT public.cron_invoke_function_body('sunny-home', '{"mode":"theta_check"}'::jsonb) $$);
