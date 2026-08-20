/* ============================================================
   earnings_events.report_session, pre-market or post-market

   The blackout gate added on 2026-08-20 treats any date from today onward as
   still ahead of you, so BABA was blocked on the morning of 20 Aug by a print
   it had already delivered before the open. Its edge that day was +9.3, the
   best on the board, and it was excluded by an event that was over.

   The table stores a date and no time, so "reported before the open" and
   "reports after the close" are indistinguishable. Nik's rule, and it is the
   right one:

     pre-market   the print lands before 09:30 ET, so the name is blocked
                  only until 09:30 on the day itself, and clear after it
     post-market  the print lands after the close, so the name is blocked
                  for the whole of that day and clear the next morning

   NULL stays conservative and blocks the whole day, which is exactly what
   happens today. Nothing gets worse by not knowing; names only get released
   as Nik fills the column in.
   ============================================================ */

alter table public.earnings_events
  add column if not exists report_session text
    check (report_session in ('pre', 'post'));

comment on column public.earnings_events.report_session is
  'pre = before the open, clear after 09:30 ET on the day. post = after the '
  'close, blocked all day. NULL = unknown, treated as post.';

/* BABA reported before the open on 2026-08-20, confirmed by Nik that morning. */
update public.earnings_events
   set report_session = 'pre'
 where ticker = 'BABA' and report_date = '2026-08-20';

notify pgrst, 'reload schema';

select ticker, report_date, report_session
  from public.earnings_events
 where report_date >= current_date
 order by report_date, ticker
 limit 20;
