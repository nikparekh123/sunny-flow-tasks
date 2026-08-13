/* ============================================================
   TLT was missing its end-of-day snapshot entirely.

   tlt_option_marks_eod has existed since the TLT store went in, but nothing
   ever wrote it — nvda_eod() has run on a cron since July while TLT had only
   tlt_mirror. The table was empty, so "when the market is shut, read the
   close" produced no marks at all for TLT and every leg rendered as $0.

   1. tlt_eod()   — mirrors nvda_eod(): per-leg marks into tlt_option_marks_eod
                    and the day's spot into tlt_daily_closes, both dated on the
                    New York market date.
   2. the cron    — 21:10 UTC weekdays, same slot as nvda-eod.
   3. a backfill  — runs both eod functions NOW, so today's marks are captured
                    rather than waiting until tonight's close.
   ============================================================ */

create or replace function public.tlt_eod() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.tlt_option_marks_eod (option_trade_id, date, mark, delta, theta, captured_at)
  select option_trade_id, (captured_at at time zone 'America/New_York')::date, mark, delta, theta, captured_at
  from public.tlt_option_marks
  on conflict (option_trade_id, date) do update set
     mark=excluded.mark, delta=excluded.delta, theta=excluded.theta, captured_at=excluded.captured_at;

  insert into public.tlt_daily_closes (ticker, date, close_price)
  select ticker, (captured_at at time zone 'America/New_York')::date, spot
  from public.tlt_quote where spot is not null
  on conflict (ticker, date) do update set close_price=excluded.close_price;
end $$;

do $$ begin
  if exists (select 1 from cron.job where jobname='tlt-eod') then perform cron.unschedule('tlt-eod'); end if;
  perform cron.schedule('tlt-eod', '10 21 * * 1-5', 'select public.tlt_eod()');
end $$;

-- Seed both tables from the marks on hand, so the app has a close to read today
-- instead of waiting for 21:10 UTC.
select public.tlt_eod();
select public.nvda_eod();

select 'nvda' as store, count(*) as eod_rows, max(date) as latest from public.nvda_option_marks_eod
union all
select 'tlt', count(*), max(date) from public.tlt_option_marks_eod;
