/* ============================================================
   The grade strip fills forward, one print at a time
   ============================================================
   The earlier migration seeded planner_earnings_grade from every
   past print. That was wrong for this page. The strip is meant to
   show your judgement accumulating quarter by quarter — a row of
   ungraded historical quarters is not history, it is a list of
   questions you were never asked and cannot honestly answer now.

   So: nothing backfilled. The table starts empty and gains exactly
   one row per print, on the day that print lands. The first will be
   the 26 Aug 2026 report; by this time next year the strip has four
   real columns, every one of them graded when it was fresh.

   grade_open_quarter() promotes any print in earnings_events whose
   date has passed into a gradeable row. Running daily, it is the
   whole mechanism — no seeding, no manual step when a quarter ends.
   Idempotent by primary key, so a holiday or a double-run is fine.
   ============================================================ */

create extension if not exists pg_cron with schema extensions;

-- Undo the earlier backfill. Only ungraded rows: if a grade was
-- given between then and now it is a real judgement and stays.
delete from public.planner_earnings_grade where grade is null;

create or replace function public.grade_open_quarter() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.planner_earnings_grade (ticker, quarter, reported_on)
  select e.ticker, public.nvda_fiscal_quarter(e.report_date), e.report_date
  from public.earnings_events e
  where e.report_date <= current_date
    -- The report lands after the close on print day; grading it the same
    -- morning would be grading a quarter nobody has read yet.
    and e.report_date < current_date
  on conflict (ticker, quarter) do nothing;
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'grade-open-quarter-daily') then
    perform cron.unschedule('grade-open-quarter-daily');
  end if;
  -- 10:00 UTC, before the US open, so a print from last night is
  -- gradeable the moment you open the app.
  perform cron.schedule('grade-open-quarter-daily', '0 10 * * *',
                        'select public.grade_open_quarter()');
end $$;

select public.grade_open_quarter();

-- Expected: empty today. The next print (26 Aug) opens the first row.
select coalesce((select count(*)::text from public.planner_earnings_grade), '0')
       || ' gradeable quarters; next print '
       || coalesce((select min(report_date)::text from public.earnings_events
                    where report_date > current_date), 'unknown') as state;
