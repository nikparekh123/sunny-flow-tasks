-- Sundial's inspector (Nik, 27 Nov 2026: "another layer of audit ... think of it as a random inspection"). The
-- sundial-inspect function works every name out again with its own code and saves what it found here, once a trading
-- day at a random time (picked from the date), plus any run forced by hand. Pushes go to Nik when it finds a problem.
create table if not exists public.sundial_inspections (
  id bigserial primary key,
  day date not null,
  at_mins int,                 -- New York minutes after midnight when it ran
  forced boolean not null default false,
  run_at timestamptz not null default now(),
  build text,
  engine_build text,
  problems int not null default 0,
  results jsonb not null       -- per name: problems[], notes[], checks{}
);
create index if not exists sundial_inspections_day on public.sundial_inspections (day);
alter table public.sundial_inspections enable row level security;
drop policy if exists sundial_inspections_owner_read on public.sundial_inspections;
create policy sundial_inspections_owner_read on public.sundial_inspections for select to authenticated
  using ('S' in (select public.my_owned_books()));
revoke insert, update, delete on public.sundial_inspections from anon, authenticated;

-- Every 15 minutes on weekdays 14:00-20:45 UTC; the function inspects only in its slot of the day.
select cron.unschedule('sundial-inspect') where exists (select 1 from cron.job where jobname = 'sundial-inspect');
select cron.schedule('sundial-inspect', '*/15 14-20 * * 1-5',
  $$select public.cron_invoke_function_body('sundial-inspect', '{}'::jsonb)$$);
