-- Exchange holidays and early closes (market-calendar, from Theta, daily),
-- and earnings season (Nik, 12 Oct 2026: starts the day JPMorgan reports,
-- runs 6 weeks).

create table if not exists public.market_calendar (
  date date primary key,
  kind text not null check (kind in ('closed', 'early_close')),
  opens time, closes time,
  name text not null,
  source text not null default 'theta',
  fetched_at timestamptz not null default now()
);
alter table public.market_calendar enable row level security;
drop policy if exists "market_calendar readable to authenticated" on public.market_calendar;
create policy "market_calendar readable to authenticated" on public.market_calendar
  for select to authenticated using (true);
grant select on public.market_calendar to authenticated;
grant all on public.market_calendar to service_role;

/* One row per JPM report: the season it opens. A report in Jan is Q4 of the
   year before, Apr Q1, Jul Q2, Oct Q3. `ends` is the last day inside it. */
create or replace view public.earnings_season with (security_invoker = on) as
  select distinct on (report_date)
    report_date as starts,
    report_date + 41 as ends,
    case when extract(month from report_date) <= 3 then 'Q4'
         else 'Q' || ((extract(month from report_date)::int - 1) / 3)::text end as quarter,
    case when extract(month from report_date) <= 3 then extract(year from report_date)::int - 1
         else extract(year from report_date)::int end as fiscal_year,
    date_estimated
  from public.earnings_events
  where ticker = 'JPM'
  order by report_date, date_estimated;
grant select on public.earnings_season to authenticated, service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'market-calendar-daily';
select cron.schedule('market-calendar-daily', '20 5 * * *',
  $$ SELECT public.cron_invoke_function('market-calendar') $$);
