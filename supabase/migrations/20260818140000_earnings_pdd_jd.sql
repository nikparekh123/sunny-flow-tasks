/* ============================================================
   PDD and JD report dates, supplied by Nik 2026-08-18.

   The last two names on the 18 Aug board without a date. Both cleared every
   gate and both were unwritable, because a name with no date is skipped by
   design: a guard that cannot fire looks exactly like a guard with nothing to
   catch.

   PDD reports in SIX DAYS. It is second on the board at edge +10.9, and that
   number is now readable as what it is. A seven-day option priced eleven points
   above realised, six days before a print, is the market pricing the print. The
   date does not make PDD writable, it makes the edge honest.

   JD reports 12 Nov, far outside any weekly expiry. JD is skipped on edge
   instead: +0.3, below the +3 floor. Same outcome as yesterday, correct reason.
   ============================================================ */

insert into public.earnings_events
  (ticker, report_date, scope_tag, date_estimated, source) values
  ('PDD', '2026-08-24', 'top50', false, 'manual'),
  ('JD',  '2026-11-12', 'top50', false, 'manual')
on conflict (ticker, report_date) do update
   set date_estimated = false;

notify pgrst, 'reload schema';

select ticker, report_date, scope_tag, date_estimated,
       report_date - current_date as days_away
  from public.earnings_events
 where ticker in ('PDD','JD')
 order by report_date;
