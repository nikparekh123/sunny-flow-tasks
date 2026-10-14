-- hourly_closes: until 9 Oct 2026 our quotes ran 15 minutes late (the feed
-- was the delayed one; real time from 12 Oct). Checked against Yahoo's
-- 15-minute bars at each full hour: those days match best 15 minutes later
-- (0.04% vs 0.18% mean gap, worst 0.77%). So a day before 12 Oct reads the
-- quote taken 15 minutes after the hour. Ages out of the five sessions by
-- 16 Oct; harmless after.
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
    select ((d.day + make_time(h.hr, 0, 0)) at time zone 'America/New_York')
           + case when d.day < date '2026-10-12' then interval '15 minutes' else interval '0' end as at
  ) w
  cross join lateral (
    select tq.spot
    from ticker_quotes tq
    where tq.ticker = t.ticker
      and tq.captured_at <= w.at
      and tq.captured_at >  w.at - interval '10 minutes'
    order by tq.captured_at desc
    limit 1
  ) q
$$;

revoke all on function public.hourly_closes(text[], date[]) from public, anon, authenticated;
grant execute on function public.hourly_closes(text[], date[]) to service_role;
