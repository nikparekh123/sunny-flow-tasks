/* ============================================================
   Confirmed report dates for the scanner universe, supplied by Nik 2026-08-17.

   These are ANNOUNCED dates, not inferred, so date_estimated stays false and the
   normal one-week margin rule applies rather than the two-week estimate window.

   Why it matters beyond the scanner: a name with no date on file is SKIPPED, by
   design, because a guard that cannot fire looks exactly like a guard with
   nothing to catch. Seventeen names here stop being blind.

   scope_tag is 'top50' for the universe and 'position' for the two Nik actually
   holds. It answers "why is this ticker here", so a name he trades and a name he
   only screens are genuinely different answers.

   NVDA 26 Aug and NFLX 20 Oct already exist from earlier migrations at the same
   dates; the upsert leaves their scope alone and only asserts the date is
   confirmed.
   ============================================================ */

insert into public.earnings_events
  (ticker, report_date, scope_tag, date_estimated, source) values
  ('NVDA',  '2026-08-26', 'position', false, 'manual'),
  ('NFLX',  '2026-10-20', 'position', false, 'manual'),
  ('AVGO',  '2026-09-02', 'top50',    false, 'manual'),
  ('MU',    '2026-09-29', 'top50',    false, 'manual'),
  ('AMZN',  '2026-10-22', 'top50',    false, 'manual'),
  ('MSFT',  '2026-10-27', 'top50',    false, 'manual'),
  ('GOOGL', '2026-10-27', 'top50',    false, 'manual'),
  ('GOOG',  '2026-10-27', 'top50',    false, 'manual'),
  ('KO',    '2026-10-27', 'top50',    false, 'manual'),
  ('TSLA',  '2026-10-28', 'top50',    false, 'manual'),
  ('META',  '2026-10-28', 'top50',    false, 'manual'),
  ('F',     '2026-10-28', 'top50',    false, 'manual'),
  ('AAPL',  '2026-10-29', 'top50',    false, 'manual'),
  ('AMD',   '2026-11-03', 'top50',    false, 'manual'),
  ('HOOD',  '2026-11-04', 'top50',    false, 'manual'),
  ('PLTR',  '2026-11-09', 'top50',    false, 'manual'),
  ('DIS',   '2026-11-12', 'top50',    false, 'manual')
on conflict (ticker, report_date) do update
   set date_estimated = false;

notify pgrst, 'reload schema';

select ticker, report_date, scope_tag, date_estimated
  from public.earnings_events
 where report_date >= current_date
 order by report_date, ticker;
