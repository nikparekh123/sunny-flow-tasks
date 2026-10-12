-- The market around the book: one row per symbol, rewritten every 30 s by
-- market-tape (Yahoo) from 4:00 to 20:00 ET on weekdays. SPY/QQQ/IWM for the
-- Today row, VIX, four overnight indices, and the five watchlist names.

create table if not exists public.market_live (
  symbol text primary key,
  label text not null,
  kind text not null check (kind in ('index', 'vix', 'global', 'watch')),
  market_state text,
  price numeric,
  prev_close numeric,
  regular_price numeric, regular_change numeric, regular_change_pct numeric,
  pre_price numeric, pre_change_pct numeric,
  post_price numeric, post_change_pct numeric,
  regular_time timestamptz, ext_time timestamptz,
  captured_at timestamptz not null default now()
);

alter table public.market_live enable row level security;
drop policy if exists "market_live readable to authenticated" on public.market_live;
create policy "market_live readable to authenticated" on public.market_live
  for select to authenticated using (true);
grant select on public.market_live to authenticated;
grant all on public.market_live to service_role;

/* Every minute across 4:00-20:00 ET in both EDT and EST; the function itself
   checks New York time and returns at once outside the window. Two passes per
   call, so 30 s. */
select cron.unschedule(jobid) from cron.job where jobname in ('market-tape-day', 'market-tape-late');
select cron.schedule('market-tape-day', '* 8-23 * * 1-5', $$ SELECT public.cron_invoke_function('market-tape') $$);
select cron.schedule('market-tape-late', '* 0-1 * * 2-6', $$ SELECT public.cron_invoke_function('market-tape') $$);
