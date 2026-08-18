/* ============================================================
   UBER and CCL report dates, supplied by Nik 2026-08-18.

   Both cleared every gate on the 18 Aug scan and both were held back by the
   same thing: "no date on file, cannot be added yet". A name with no date is
   SKIPPED by design, because a guard that cannot fire looks exactly like a
   guard with nothing to catch.

   Marked confirmed, matching how the 17-name batch of 2026-08-17 was loaded.
   If either is a scheduled estimate rather than an announced date, flip
   date_estimated to true and the two-week window applies instead of one.
   ============================================================ */

insert into public.earnings_events
  (ticker, report_date, scope_tag, date_estimated, source) values
  ('UBER', '2026-10-29', 'top50', false, 'manual'),
  ('CCL',  '2026-09-17', 'top50', false, 'manual')
on conflict (ticker, report_date) do update
   set date_estimated = false;

notify pgrst, 'reload schema';

select ticker, report_date, scope_tag, date_estimated
  from public.earnings_events
 where ticker in ('UBER','CCL')
 order by report_date;
