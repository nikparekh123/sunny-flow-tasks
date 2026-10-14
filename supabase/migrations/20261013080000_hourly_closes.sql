-- Positions Chart cards (handoff 22, block 13): hourly closes 10:00 to 16:00
-- New York for the last five sessions per ticker. Taken from our own quotes
-- (ticker_quotes, real time every 30 s, kept 30 days): the last quote at or
-- before each full hour, within 10 minutes. An hour not reached yet, or with
-- no quote, returns no row. sunny-home calls it once per pass (8 tickers x 35
-- hours = 280 index probes on idx_ticker_quotes_ticker_captured).
create or replace function public.hourly_closes(p_tickers text[], p_days date[])
returns table (ticker text, day date, hr int, spot numeric)
language sql stable
set search_path = public
as $$
  select t.ticker, d.day, h.hr, q.spot
  from unnest(p_tickers) as t(ticker)
  cross join unnest(p_days) as d(day)
  cross join generate_series(10, 16) as h(hr)
  cross join lateral (
    select tq.spot
    from ticker_quotes tq
    where tq.ticker = t.ticker
      and tq.captured_at <= ((d.day + make_time(h.hr, 0, 0)) at time zone 'America/New_York')
      and tq.captured_at >  ((d.day + make_time(h.hr, 0, 0)) at time zone 'America/New_York') - interval '10 minutes'
    order by tq.captured_at desc
    limit 1
  ) q
$$;

revoke all on function public.hourly_closes(text[], date[]) from public, anon, authenticated;
grant execute on function public.hourly_closes(text[], date[]) to service_role;
