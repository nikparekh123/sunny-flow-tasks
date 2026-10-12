-- The new app's Home page in one row, rebuilt by sunny-home after every
-- 30 s price pass (handoff 18). The app reads this row and nothing else on
-- the tick. Signed-in readers only: it carries the account.
create table if not exists public.home_snapshot (
  id int primary key check (id = 1),
  payload jsonb not null,
  built_at timestamptz not null,
  build text,
  ms int
);
alter table public.home_snapshot enable row level security;
drop policy if exists "home_snapshot readable to authenticated" on public.home_snapshot;
create policy "home_snapshot readable to authenticated" on public.home_snapshot
  for select to authenticated using (true);
grant select on public.home_snapshot to authenticated;
grant all on public.home_snapshot to service_role;

/* Every minute; the function decides: two passes (:06, :36) from 4:00 to
   20:00 ET on weekdays, one every 10 minutes otherwise. */
select cron.unschedule(jobid) from cron.job where jobname = 'sunny-home';
select cron.schedule('sunny-home', '* * * * *', $$ SELECT public.cron_invoke_function('sunny-home') $$);
