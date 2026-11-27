-- Sundial's check (Nik, 27 Nov 2026: "check the positions at 10am, 12pm, 2pm and 4pm, that the engine is not over or
-- under suggesting"). The sundial function's 'audit' mode rebuilds every name's book from IBKR's trades a second way and
-- checks what the board suggests; one row per run, with what it found. Pushes go to Nik when a run finds a problem.
create table if not exists public.sundial_audits (
  id bigserial primary key,
  day date not null,
  slot text not null,                 -- '10am', '12pm', '2pm', '4pm' (a forced run adds the minute)
  run_at timestamptz not null default now(),
  build text,
  problems int not null default 0,
  results jsonb not null,             -- per name: problems[], notes[], the test now and with the suggestions
  unique (day, slot)
);
alter table public.sundial_audits enable row level security;
drop policy if exists sundial_audits_owner_read on public.sundial_audits;
create policy sundial_audits_owner_read on public.sundial_audits for select to authenticated
  using ('S' in (select public.my_owned_books()));
revoke insert, update, delete on public.sundial_audits from anon, authenticated;

-- Every hour on weekdays 14:00-21:00 UTC; the function runs the check only at 10 AM, 12 PM, 2 PM and 4 PM New York, so
-- it stays right across daylight saving.
select cron.unschedule('sundial-audit') where exists (select 1 from cron.job where jobname = 'sundial-audit');
select cron.schedule('sundial-audit', '0 14-21 * * 1-5',
  $$select public.cron_invoke_function_body('sundial', '{"mode":"audit"}'::jsonb)$$);
