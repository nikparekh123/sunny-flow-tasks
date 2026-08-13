/* ============================================================
   The EOD snapshot must never store — or overwrite with — a null mark.

   nvda_eod() copied every row of *_option_marks as-is. Run at a moment when the
   feed had not yet populated a leg, it wrote a NULL mark; run again later, the
   on-conflict update would overwrite a perfectly good close with that null. The
   app drops null marks, so the leg then reads "no mark" and drops out of P&L.

   Both functions now filter to marks that exist, so a snapshot can only ever add
   or improve a close, never erase one.
   ============================================================ */

create or replace function public.nvda_eod() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.nvda_option_marks_eod (option_trade_id, date, mark, delta, theta, captured_at)
  select option_trade_id, (captured_at at time zone 'America/New_York')::date, mark, delta, theta, captured_at
  from public.nvda_option_marks
  where mark is not null                      -- never snapshot a hole
  on conflict (option_trade_id, date) do update set
     mark=excluded.mark, delta=excluded.delta, theta=excluded.theta, captured_at=excluded.captured_at;

  insert into public.nvda_daily_closes (ticker, date, close_price)
  select ticker, (captured_at at time zone 'America/New_York')::date, spot
  from public.nvda_quote where spot is not null
  on conflict (ticker, date) do update set close_price=excluded.close_price;
end $$;

create or replace function public.tlt_eod() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.tlt_option_marks_eod (option_trade_id, date, mark, delta, theta, captured_at)
  select option_trade_id, (captured_at at time zone 'America/New_York')::date, mark, delta, theta, captured_at
  from public.tlt_option_marks
  where mark is not null
  on conflict (option_trade_id, date) do update set
     mark=excluded.mark, delta=excluded.delta, theta=excluded.theta, captured_at=excluded.captured_at;

  insert into public.tlt_daily_closes (ticker, date, close_price)
  select ticker, (captured_at at time zone 'America/New_York')::date, spot
  from public.tlt_quote where spot is not null
  on conflict (ticker, date) do update set close_price=excluded.close_price;
end $$;

-- nvda-marks has since populated every open leg, so re-snapshot to capture them.
select public.nvda_eod();
select public.tlt_eod();

-- Every OPEN leg should now appear with a mark. Any row here is a leg the app
-- will still show as "no mark".
select t.ticker, t.strike, t.option_type, t.direction, t.expiry,
       (e.mark is null) as missing_close
from (
  select 'NVDA' as ticker, strike, option_type, direction, expiry, id from public.nvda_option_trades
   where voided_at is null and action='open' and expiry >= current_date
  union all
  select 'TLT', strike, option_type, direction, expiry, id from public.tlt_option_trades
   where voided_at is null and action='open' and expiry >= current_date
) t
left join (
  select option_trade_id, mark from public.nvda_option_marks_eod where date = (select max(date) from public.nvda_option_marks_eod)
  union all
  select option_trade_id, mark from public.tlt_option_marks_eod  where date = (select max(date) from public.tlt_option_marks_eod)
) e on e.option_trade_id = t.id
where e.mark is null
order by t.ticker, t.expiry, t.strike;
