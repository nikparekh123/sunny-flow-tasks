-- Live tables: one row per leg and one row per ticker, kept current by
-- triggers on the append-only history tables.
--
-- ⚠ WHY (12 Oct 2026). The database froze 15:13-15:30 ET. Among the waste on
-- the 1 GB server: `ticker_quotes_latest` was a DISTINCT ON over ~107k history
-- rows (~1.1 s a read) and `option_greeks_latest` a lateral over every
-- option_trade (0.9-3.2 s), and the app and website read both every 30 s.
-- The views keep their names and columns, so every reader gets the fast path
-- with no code change. History is untouched: mp-refresh still appends, the
-- 90-day and 30-day prunes still run.

create table if not exists public.option_greeks_live (
  option_trade_id uuid primary key references public.option_trades(id) on delete cascade,
  delta numeric, gamma numeric, theta numeric, vega numeric, iv numeric,
  open_interest integer, volume integer, last_mark numeric, underlying numeric,
  captured_at timestamptz not null,
  id uuid not null
);

create table if not exists public.ticker_quotes_live (
  ticker text primary key,
  spot numeric, day_change_pct numeric, beta numeric,
  captured_at timestamptz not null,
  id uuid not null
);

alter table public.option_greeks_live enable row level security;
alter table public.ticker_quotes_live enable row level security;
drop policy if exists "option_greeks_live readable to authenticated" on public.option_greeks_live;
create policy "option_greeks_live readable to authenticated" on public.option_greeks_live
  for select to authenticated using (true);
drop policy if exists "ticker_quotes_live readable to authenticated" on public.ticker_quotes_live;
create policy "ticker_quotes_live readable to authenticated" on public.ticker_quotes_live
  for select to authenticated using (true);
grant select on public.option_greeks_live, public.ticker_quotes_live to anon, authenticated;
grant all on public.option_greeks_live, public.ticker_quotes_live to service_role;

/* Statement-level, so mp-refresh's one 45-row insert is one upsert. A capture
   never overwrites a newer one. */
create or replace function public.option_greeks_to_live() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into option_greeks_live as l
    (option_trade_id, delta, gamma, theta, vega, iv, open_interest, volume,
     last_mark, underlying, captured_at, id)
  select distinct on (n.option_trade_id)
    n.option_trade_id, n.delta, n.gamma, n.theta, n.vega, n.iv, n.open_interest,
    n.volume, n.last_mark, n.underlying, n.captured_at, n.id
  from new_rows n
  order by n.option_trade_id, n.captured_at desc
  on conflict (option_trade_id) do update set
    delta = excluded.delta, gamma = excluded.gamma, theta = excluded.theta,
    vega = excluded.vega, iv = excluded.iv, open_interest = excluded.open_interest,
    volume = excluded.volume, last_mark = excluded.last_mark,
    underlying = excluded.underlying, captured_at = excluded.captured_at, id = excluded.id
  where excluded.captured_at >= l.captured_at;
  return null;
end $$;

create or replace function public.ticker_quotes_to_live() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into ticker_quotes_live as l (ticker, spot, day_change_pct, beta, captured_at, id)
  select distinct on (n.ticker) n.ticker, n.spot, n.day_change_pct, n.beta, n.captured_at, n.id
  from new_rows n
  order by n.ticker, n.captured_at desc
  on conflict (ticker) do update set
    spot = excluded.spot, day_change_pct = excluded.day_change_pct, beta = excluded.beta,
    captured_at = excluded.captured_at, id = excluded.id
  where excluded.captured_at >= l.captured_at;
  return null;
end $$;

drop trigger if exists option_greeks_live_sync on public.option_greeks;
create trigger option_greeks_live_sync after insert on public.option_greeks
  referencing new table as new_rows for each statement
  execute function public.option_greeks_to_live();

drop trigger if exists ticker_quotes_live_sync on public.ticker_quotes;
create trigger ticker_quotes_live_sync after insert on public.ticker_quotes
  referencing new table as new_rows for each statement
  execute function public.ticker_quotes_to_live();

-- Seed from history (index scans on (key, captured_at desc)).
insert into public.option_greeks_live
select distinct on (option_trade_id)
  option_trade_id, delta, gamma, theta, vega, iv, open_interest, volume,
  last_mark, underlying, captured_at, id
from public.option_greeks
order by option_trade_id, captured_at desc
on conflict (option_trade_id) do nothing;

insert into public.ticker_quotes_live
select distinct on (ticker) ticker, spot, day_change_pct, beta, captured_at, id
from public.ticker_quotes
order by ticker, captured_at desc
on conflict (ticker) do nothing;

-- Same names, same columns, same security as before.
create or replace view public.option_greeks_latest as
  select l.option_trade_id, l.delta, l.gamma, l.theta, l.vega, l.iv,
         l.open_interest, l.volume, l.last_mark, l.underlying, l.captured_at, l.id
  from public.option_greeks_live l
  join public.option_trades t on t.id = l.option_trade_id;

create or replace view public.ticker_quotes_latest with (security_invoker = on) as
  select ticker, spot, day_change_pct, beta, captured_at, id
  from public.ticker_quotes_live;

-- Housekeeping that let the server choke: job logs grew to 275k rows, and
-- pg_net's reply table bloated to 81 MB for 801 rows.
select cron.unschedule(jobid) from cron.job where jobname in ('trim-cron-run-details-daily', 'vacuum-pg-net-hourly');
select cron.schedule('trim-cron-run-details-daily', '10 6 * * *',
  $$ delete from cron.job_run_details where end_time < now() - interval '7 days' $$);
select cron.schedule('vacuum-pg-net-hourly', '7 * * * *', $$ vacuum net._http_response $$);
