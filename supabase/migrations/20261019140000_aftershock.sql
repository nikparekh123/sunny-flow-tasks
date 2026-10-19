-- AFTERSHOCK (handoff 26, 19 Oct 2026): the page shows each day's scan and each crash's Day 2 move.
-- crash_scans records that a scan ran (so "No crashes" differs from "not scanned yet"); crash_events
-- gains the Day 2 close. The day-2 trade suggestion is dropped (Nik: no entry or size instructions);
-- the `suggestion` column stays empty from now on.
alter table public.crash_events
  add column if not exists day2_close numeric,
  add column if not exists day2_pct   numeric;          -- Day 2 close against the crash close, %

create table if not exists public.crash_scans (
  day        date primary key,           -- the session scanned
  scanned_at timestamptz not null,
  universe   int not null,               -- names checked
  crashes    int not null,
  source     text not null,              -- 'snapshot' at 4:15, 'grouped' once the day's bars are final
  updated_at timestamptz not null default now()
);
alter table public.crash_scans enable row level security;
create policy "crash_scans: signed-in read" on public.crash_scans for select to authenticated using (true);

-- Every 5 minutes 20:00-23:55 UTC; the function scans only between 4:15 and 7:00 PM New York, once a day,
-- as soon as Polygon has the session's grouped bars (our plan has no snapshots and releases the day's bars
-- after the close).
select cron.unschedule('crash-scan-10min');
select cron.schedule('crash-scan', '*/5 20-23 * * 1-5', $$ select public.cron_invoke_function('crash-scan') $$);
