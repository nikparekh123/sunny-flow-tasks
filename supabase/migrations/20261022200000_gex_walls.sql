-- Gamma walls log (Nik, 22 Oct 2026): one row per gex-walls run, per ticker. The function writes with
-- the service role; signed-in users may read. Run daily after the close for the open names.

create table if not exists public.gex_walls (
  id             bigserial primary key,
  run_at         timestamptz not null default now(),
  day            date not null,
  ticker         text not null,
  days           integer,
  expiries       text[],
  spot           numeric,
  net_gex        numeric,
  flip           numeric,
  call_wall      numeric,
  call_wall_gex  numeric,
  call_wall2     numeric,
  put_wall       numeric,
  put_wall_gex   numeric,
  put_wall2      numeric,
  fresh          numeric[],
  filled_oi_pct  numeric,
  summary        text not null,
  strikes        jsonb
);
create index if not exists gex_walls_ticker_day on public.gex_walls (ticker, day desc);

alter table public.gex_walls enable row level security;
drop policy if exists gex_walls_read on public.gex_walls;
create policy gex_walls_read on public.gex_walls for select to authenticated using (true);
grant select on public.gex_walls to authenticated;

-- 21:15 UTC on weekdays: 5:15 PM New York in summer time, 4:15 PM in winter, after the close either way.
select cron.unschedule('gex-walls-daily') where exists (select 1 from cron.job where jobname = 'gex-walls-daily');
select cron.schedule('gex-walls-daily', '15 21 * * 1-5',
  $$ select public.cron_invoke_function_body('gex-walls', '{"mode":"daily"}'::jsonb, 240000) $$);
