/* ============================================================
   Benzinga earnings: allow the source, and undo a column I duplicated

   1. source had a check constraint listing manual / investing.com / fmp / iex /
      other. Writing 'benzinga' failed all 2,825 rows with 23514.

   2. ⚠ I ADDED A SECOND COLUMN FOR A FACT THAT ALREADY HAD ONE. On 2026-08-20 I
      added report_session (pre/post) to carry the pre-market flag. report_time
      (bmo/amc/tba) already existed, and earnings-history reads it. That is
      exactly the duplication that made the scanner and the book disagree about
      CPB, and I introduced it while fixing that.

      report_time wins: it is older, it has a consumer, and 'tba' says UNKNOWN
      explicitly where a NULL report_session only implies it. income-scanner and
      income-sleeve now read report_time and report_session is dropped.

        bmo = before market open   -> clears once 09:30 ET has passed
        amc = after market close   -> blocks the whole day
        tba = unknown              -> treated as amc, so ignorance never
                                      releases a name early
   ============================================================ */

alter table public.earnings_events drop constraint if exists earnings_events_source_check;
alter table public.earnings_events add constraint earnings_events_source_check
  check (source = any (array['manual','investing.com','fmp','iex','benzinga','other']));

-- carry across the seven Nik entered by hand before dropping the column
update public.earnings_events
   set report_time = case when report_session = 'pre' then 'bmo' else 'amc' end
 where report_session is not null and report_time is null;

alter table public.earnings_events drop column if exists report_session;

comment on column public.earnings_events.report_time is
  'bmo = before the open, clear after 09:30 ET on the day. amc = after the '
  'close, blocked all day. tba/NULL = unknown, treated as amc.';

notify pgrst, 'reload schema';
