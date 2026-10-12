-- Every leg's last mark and greeks of each New York day, kept for good.
--
-- ⚠ WHY: option_greeks keeps 30 s history for 90 days only (prune at 06:00
-- UTC), and the new app's Theta, Delta, Payback and Sold vs Bought charts
-- need one point per trading day back to the book's start and beyond. This
-- is that point: the last capture of the day per leg. Seeded from history
-- (13 Jul 2026 on); topped up after every close and again before the prune.

create table if not exists public.leg_marks_daily (
  option_trade_id uuid not null references public.option_trades(id) on delete cascade,
  day date not null,
  mark numeric, iv numeric, delta numeric, gamma numeric, theta numeric, vega numeric,
  underlying numeric,
  captured_at timestamptz not null,
  primary key (option_trade_id, day)
);
create index if not exists leg_marks_daily_day on public.leg_marks_daily (day);
alter table public.leg_marks_daily enable row level security;
drop policy if exists "leg_marks_daily readable to authenticated" on public.leg_marks_daily;
create policy "leg_marks_daily readable to authenticated" on public.leg_marks_daily
  for select to authenticated using (true);
grant select on public.leg_marks_daily to authenticated;
grant all on public.leg_marks_daily to service_role;

/* The last capture per leg per New York day, for every day since `since`. */
create or replace function public.capture_leg_marks_daily(since date default (now() at time zone 'America/New_York')::date - 3)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into leg_marks_daily as l (option_trade_id, day, mark, iv, delta, gamma, theta, vega, underlying, captured_at)
  select distinct on (g.option_trade_id, (g.captured_at at time zone 'America/New_York')::date)
    g.option_trade_id, (g.captured_at at time zone 'America/New_York')::date,
    g.last_mark, g.iv, g.delta, g.gamma, g.theta, g.vega, g.underlying, g.captured_at
  from option_greeks g
  where g.captured_at >= (since::timestamp at time zone 'America/New_York')
  order by g.option_trade_id, (g.captured_at at time zone 'America/New_York')::date, g.captured_at desc
  on conflict (option_trade_id, day) do update set
    mark = excluded.mark, iv = excluded.iv, delta = excluded.delta, gamma = excluded.gamma,
    theta = excluded.theta, vega = excluded.vega, underlying = excluded.underlying,
    captured_at = excluded.captured_at
  where excluded.captured_at >= l.captured_at;
  get diagnostics n = row_count;
  return n;
end $$;

-- After the last price pass of the day, and once more before the 06:00 prune.
select cron.unschedule(jobid) from cron.job where jobname in ('leg-marks-daily-close', 'leg-marks-daily-prune-guard');
select cron.schedule('leg-marks-daily-close', '10 21 * * 1-5', $$ select public.capture_leg_marks_daily() $$);
select cron.schedule('leg-marks-daily-prune-guard', '50 5 * * *', $$ select public.capture_leg_marks_daily() $$);
