/* ============================================================
   Persistence, computed in SQL over the full stored history

   Share of sessions spent within 10% of the trailing 252-day low. The universe
   median is about 4.7%; Nik's book runs 50-80. It is the factor that reproduces
   the names he picked by instinct, and unlike "52-week position today" it
   cannot be moved by a single session.

   ⚠ WHY IT MOVED OUT OF THE FUNCTION. It was computed from the bars the scanner
   holds in memory. When the fetch window dropped from 600 days to 420, to stop
   the worker dying at 596 names, the measurement period fell with it from ~158
   sessions to ~30. PEP read 100% where it had read 29.4% that morning. At 30
   observations 100% is trivial to hit and the number stopped meaning anything.

   The measurement window must not be a side effect of how much history the
   scanner happens to fetch. scanner_closes keeps everything ever downloaded and
   only grows, so the view sees the full record however short the fetch becomes.
   Heavy history work belongs in Postgres, not in an edge function.

   `measured` ships alongside so a thin reading is visible rather than trusted:
   a name with 40 observations and a name with 300 are not the same evidence.
   ============================================================ */

create or replace view public.scanner_persistence as
with w as (
  select ticker, date, close,
         min(close) over (
           partition by ticker order by date
           rows between 251 preceding and current row
         ) as low_252,
         count(*) over (
           partition by ticker order by date
           rows between 251 preceding and current row
         ) as window_n
    from public.scanner_closes
)
select ticker,
       round(avg(case when close <= low_252 * 1.10 then 1.0 else 0.0 end) * 100, 1)
         as persistence,
       round(avg(case when close <= low_252 * 1.05 then 1.0 else 0.0 end) * 100, 1)
         as persistence_5,
       count(*) as measured
  from w
 where window_n = 252          -- only where a full year sits behind the reading
 group by ticker;

comment on view public.scanner_persistence is
  'Share of sessions within 10% (and 5%) of the trailing 252-day low, over the '
  'whole of scanner_closes. Universe median ~4.7%. Check `measured` before '
  'trusting a value: under ~60 observations it is noise.';

grant select on public.scanner_persistence to authenticated;
