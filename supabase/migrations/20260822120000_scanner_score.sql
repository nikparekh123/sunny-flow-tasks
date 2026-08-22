/* ============================================================
   The score: rank what survives the gates

   Gates answer "is this eligible", binary, no judgement. They cannot say that
   BABA suits this book better than SBUX, and today they call both simply
   "clear". The score ranks survivors, and Nik picks from the ranking.

   ⚠ SCORE ONLY EVER APPLIES AFTER THE GATES. On 2026-08-20 a linear edge
   component put INTU at 74/100, the highest of anything tested, while it failed
   FOUR gates: still moving 19% in 3mo, vol 52, edge 34.8 with an event priced,
   and a print three days away. It maxed edge and premium and BOTH were the
   earnings. The same stock scored as underpaid five days earlier on unchanged
   fundamentals. So the edge component is BANDED, not linear: it peaks between
   +4 and +10 and scores ZERO above the ceiling, or the score rewards precisely
   what the ceiling exists to reject.

   PERSISTENCE is the new factor and the best one. Share of the last ~7 months
   spent within 10% of the trailing 52-week low. The median stock across 140
   names scores 4.7%. Nik's book runs 50-80%: NKE 72.5, PG 80.6, MCD 75.0,
   NFLX 52.5, LULU 52.5. One number reproduces the book he picked by instinct,
   and unlike "52-week position today" it cannot be moved by a single session.
   It is why his proposed "within 5% of the low" gate returned zero names: the
   median stock is only there for FOUR DAYS, so proximity catches tourists.

   Weights, and why persistence outranks the spot reading:

       edge         25   banded, zero above the ceiling
       persistence  25   has it LIVED down here
       premium      15   income per dollar committed
       conviction   15   Nik's own 0-10, the only hand-set input
       cheap        10   where it sits today
       settled      10   has it stopped moving

   ⚠ The edge here is IV minus the 20-DAY realised, the same number the gate
   uses. The 20-day input swings 9 to 26 points on its own and the 60-day is
   four to seven times steadier, so the honest measure is probably the 60-day.
   But changing one and not the other is how the scanner and the book came to
   disagree about CPB. If it moves, BOTH move.
   ============================================================ */

alter table public.income_scanner_universe
  add column if not exists conviction smallint
    check (conviction between 0 and 10);

comment on column public.income_scanner_universe.conviction is
  'Nik''s own 0-10. The only hand-set input in the score. NULL is read as 5, '
  'neutral, so an unrated name is neither rewarded nor punished.';

alter table public.income_scanner_results
  add column if not exists persistence numeric,
  add column if not exists score       numeric;

comment on column public.income_scanner_results.persistence is
  'Share of sessions in the last ~7 months spent within 10% of the trailing '
  '252-day low. Universe median 4.7%.';
comment on column public.income_scanner_results.score is
  '0-100, meaningful ONLY for rows where passes = true.';

update public.income_scanner_universe set conviction = v.c
  from (values ('NKE',9),('LULU',9),('BIDU',8),('NFLX',7),('BABA',7)) as v(t,c)
 where income_scanner_universe.ticker = v.t;

notify pgrst, 'reload schema';

select ticker, conviction from public.income_scanner_universe
 where conviction is not null order by conviction desc, ticker;
