/* ============================================================
   Estimated report dates, so a name does not go silent every quarter.

   Companies publish a date three or four weeks ahead, so the quarter after next
   is simply not knowable. LULU's confirmed date runs out on 27 Aug 2026 and its
   December one does not exist anywhere yet. Waiting for it means each name stops
   writing for weeks, every quarter, forever.

   An estimate is anchored to the SAME QUARTER A YEAR EARLIER, taken from the
   actual dates in the tape:

     LULU printed 11 Dec 2025  ->  ~10 Dec 2026
     NKE  printed 18 Dec 2025  ->  ~17 Dec 2026
     NFLX reports mid-January  ->  ~20 Jan 2027

   scope_tag 'estimate' makes income-sleeve block a TWO-WEEK window rather than a
   day, and label the card "estimated, not confirmed". The width is the point: the
   anchor is good to about a week, so the window absorbs the error instead of
   pretending to a precision it does not have.

   This is NOT the cadence inference tested and rejected on 2026-08-17, which
   guessed dates from price gaps and came out 31, 29 and 120 days wrong. Same
   quarter last year is a much stronger anchor.

   REPLACE EACH ONE the moment the company announces. A confirmed row is picked
   ahead of an estimate and the block narrows back to the normal rule:
     insert into public.earnings_events (ticker, report_date, scope_tag)
     values ('LULU','2026-12-DD','position') on conflict do nothing;
   ============================================================ */

insert into public.earnings_events (ticker, report_date, fiscal_period, scope_tag) values
  ('LULU', '2026-12-10', 'FY26 Q3 (est)', 'estimate'),
  ('NKE',  '2026-12-17', 'FY27 Q2 (est)', 'estimate'),
  ('NFLX', '2027-01-20', 'FY26 Q4 (est)', 'estimate')
on conflict (ticker, report_date) do nothing;

select ticker, report_date, scope_tag from public.earnings_events
 where ticker in ('NFLX','NKE','LULU') and report_date >= current_date - 10
 order by ticker, report_date;
