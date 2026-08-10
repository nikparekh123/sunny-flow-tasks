/* ============================================================
   planner_earnings_grade — the one input no feed provides, kept
   ============================================================
   The grade is the only number in the planner that comes from you
   rather than from a feed, and until now it lived as a single value
   in UserDefaults on the phone: no quarter attached, no history, and
   gone with the app's storage.

   That made two things impossible. The grade page cannot ask "how
   was Q1 FY27?" if it does not know which quarter the number refers
   to, and it cannot show whether you are grading this company more
   harshly than a year ago without the ones before it.

   It also fixes a quieter bug: a grade given for the May print kept
   applying after the August print, because nothing marked it stale.
   Keyed by quarter, a new print simply has no grade yet.

   NVDA's fiscal year runs a year ahead of the calendar — it ends in
   late January, so the May 2026 report is Q1 FY27. The label is
   derived, never typed, so the next print names itself.
   ============================================================ */

create or replace function public.nvda_fiscal_quarter(d date) returns text
language sql immutable as $$
  -- Reports land in Feb / May / Aug / Nov, but the day drifts and a print can
  -- slip a week, so this brackets by calendar quarter rather than by month.
  select case
    when extract(month from d)::int between 1 and 3
      then 'Q4 FY' || to_char(d, 'YY')
    when extract(month from d)::int between 4 and 6
      then 'Q1 FY' || to_char(d + interval '1 year', 'YY')
    when extract(month from d)::int between 7 and 9
      then 'Q2 FY' || to_char(d + interval '1 year', 'YY')
    else 'Q3 FY' || to_char(d + interval '1 year', 'YY')
  end
$$;

create table if not exists public.planner_earnings_grade (
  ticker      text not null default 'NVDA',
  quarter     text not null,                       -- 'Q1 FY27', derived above
  reported_on date not null,
  -- Null means "not graded yet", which is a real state and must not read as 0.
  -- A 0 is the harshest grade there is; the two cannot share a representation.
  grade       integer check (grade between 0 and 10),
  graded_at   timestamptz,
  primary key (ticker, quarter)
);

create index if not exists planner_earnings_grade_recent_idx
  on public.planner_earnings_grade (ticker, reported_on desc);

alter table public.planner_earnings_grade enable row level security;

drop policy if exists planner_earnings_grade_read on public.planner_earnings_grade;
create policy planner_earnings_grade_read on public.planner_earnings_grade
  for select to authenticated using (true);

-- The app writes this one directly: it is the user's own judgement, typed on the
-- phone, and routing a stepper through an edge function buys nothing.
drop policy if exists planner_earnings_grade_write on public.planner_earnings_grade;
create policy planner_earnings_grade_write on public.planner_earnings_grade
  for all to authenticated using (true) with check (true);

drop policy if exists planner_earnings_grade_service on public.planner_earnings_grade;
create policy planner_earnings_grade_service on public.planner_earnings_grade
  for all to service_role using (true) with check (true);

/* ------------------------------------------------------------
   Seed every print that has already happened. Grades stay null —
   these are your judgements and cannot be invented — so the page
   opens asking about the most recent quarter with the earlier ones
   listed and empty, which is the truth.
   ------------------------------------------------------------ */
insert into public.planner_earnings_grade (ticker, quarter, reported_on)
select e.ticker, public.nvda_fiscal_quarter(e.report_date), e.report_date
from public.earnings_events e
where e.report_date <= current_date
on conflict (ticker, quarter) do nothing;

select quarter, reported_on, coalesce(grade::text, 'not graded') as grade
from public.planner_earnings_grade
where ticker = 'NVDA'
order by reported_on desc
limit 8;
