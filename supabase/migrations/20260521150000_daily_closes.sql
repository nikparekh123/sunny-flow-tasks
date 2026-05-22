-- daily_closes — historical close prices per ticker per trading day.
--
-- Populated by a pg_cron job that snapshots positions.current_price
-- ~15 min after US market close on weekdays. Used by the Resolve flow
-- to look up the close price on an option's expiry date and default
-- the Exercised vs Expired-worthless choice.
--
-- The hourly refresh-prices cron has already fetched today's close
-- by 21:00 UTC, so the snapshot just copies whatever current_price
-- holds.

create table if not exists public.daily_closes (
  ticker      text not null,
  date        date not null,
  close_price numeric not null,
  captured_at timestamptz not null default now(),
  primary key (ticker, date)
);

create index if not exists daily_closes_ticker_idx on public.daily_closes (ticker);
create index if not exists daily_closes_date_idx   on public.daily_closes (date desc);

alter table public.daily_closes enable row level security;

drop policy if exists "daily_closes: authenticated read" on public.daily_closes;
create policy "daily_closes: authenticated read"
  on public.daily_closes for select to authenticated using (true);
-- No write policy — only service role / SQL cron writes.

-- ── Cron — snapshot today's close from positions ────────────────────
-- Runs at 21:30 UTC Mon–Fri, ~30 min after market close (and 30 min
-- after the last hourly refresh-prices run). Idempotent: ON CONFLICT
-- update if it somehow fires twice.
create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'capture-daily-close') then
    perform cron.unschedule('capture-daily-close');
  end if;

  perform cron.schedule(
    'capture-daily-close',
    '30 21 * * 1-5',
    $job$
      insert into public.daily_closes (ticker, date, close_price)
      select ticker, current_date, current_price
      from public.positions
      where current_price is not null
      on conflict (ticker, date) do update
        set close_price = excluded.close_price,
            captured_at = now();
    $job$
  );
end $$;
