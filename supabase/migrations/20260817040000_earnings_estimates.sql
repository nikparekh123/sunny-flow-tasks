/* ============================================================
   Estimated report dates, so a name does not go silent every quarter.

   Companies publish a date three or four weeks ahead, so the quarter after next
   is simply not knowable. LULU's confirmed date runs out on 27 Aug 2026 and its
   December one does not exist anywhere yet. Waiting for it means each name stops
   writing for weeks, every quarter, forever.

   An estimate is anchored to the SAME QUARTER A YEAR EARLIER, read off the tape:

     LULU printed 11 Dec 2025  ->  ~10 Dec 2026
     NKE  printed 18 Dec 2025  ->  ~17 Dec 2026
     NFLX reports mid-January  ->  ~20 Jan 2027

   income-sleeve blocks a TWO-WEEK window around an estimate rather than a day,
   and labels the card "estimated, not confirmed". The width is the point: the
   anchor is good to about a week, so the window absorbs the error instead of
   pretending to a precision it does not have.

   This is NOT the cadence inference tested and rejected earlier today, which
   guessed dates from price gaps and came out 31, 29 and 120 days wrong. Same
   quarter last year is a far stronger anchor.

   ── Why a new column and not scope_tag ─────────────────────────────────────
   The first version of this wrote scope_tag = 'estimate' and was rejected by the
   table's own check constraint, correctly. scope_tag answers "why is this ticker
   here" (position, peer, top50) and is about SCOPE. Whether a date is confirmed
   is about CONFIDENCE. Two different questions, so two different columns; folding
   them together would have made 'estimate' mutually exclusive with 'position',
   which is nonsense since these rows are both.
   ============================================================ */

alter table public.earnings_events
  add column if not exists date_estimated boolean not null default false;

comment on column public.earnings_events.date_estimated is
  'true when report_date is inferred rather than announced. Consumers should '
  'widen any blackout around it. Replace with the confirmed date when published.';

insert into public.earnings_events
  (ticker, report_date, fiscal_period, scope_tag, date_estimated, notes) values
  ('LULU', '2026-12-10', 'FY26 Q3', 'position', true, 'Anchored to the 11 Dec 2025 print.'),
  ('NKE',  '2026-12-17', 'FY27 Q2', 'position', true, 'Anchored to the 18 Dec 2025 print.'),
  ('NFLX', '2027-01-20', 'FY26 Q4', 'position', true, 'Anchored to its mid-January cadence.')
on conflict (ticker, report_date) do update
   set date_estimated = true, notes = excluded.notes;

notify pgrst, 'reload schema';

/* Replace an estimate the moment the company announces. A confirmed row is a
   normal insert; this clears the flag if the date happens to match:
     update public.earnings_events set date_estimated = false
      where ticker = 'LULU' and report_date = '2026-12-10';                    */
select ticker, report_date, date_estimated, fiscal_period
  from public.earnings_events
 where ticker in ('NFLX','NKE','LULU') and report_date >= current_date - 10
 order by ticker, report_date;
