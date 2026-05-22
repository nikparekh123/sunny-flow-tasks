-- ticker_signals — daily snapshot of technical indicators per ticker.
-- Populated by the refresh-signals edge function (runs ~15 min after
-- US market close on weekdays).
--
-- One row per ticker; the same numbers are shown to every user, so RLS
-- lets all authenticated users read but only the service role writes.

create table if not exists public.ticker_signals (
  ticker        text primary key,
  asof_date     date not null,
  price         numeric,
  ma20          numeric,
  ma50          numeric,
  ma200         numeric,
  rsi14         numeric,
  chg_5d_pct    numeric,
  chg_21d_pct   numeric,
  updated_at    timestamptz not null default now()
);

alter table public.ticker_signals enable row level security;

drop policy if exists "ticker_signals select for authenticated" on public.ticker_signals;
create policy "ticker_signals select for authenticated"
  on public.ticker_signals for select
  to authenticated
  using (true);
-- No insert/update/delete policy → only service role can write.

alter publication supabase_realtime add table public.ticker_signals;

-- Schedule the refresh function for 21:15 UTC weekdays — about 15 mins
-- after the US market close in both EST and EDT.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

do $$
declare
  proj_url text := 'https://ziwoutsnuywjnsyfbzsp.supabase.co';
  svc_key  text;
begin
  select decrypted_secret into svc_key
  from vault.decrypted_secrets
  where name = 'service_role_key'
  limit 1;

  if svc_key is null then
    raise notice
      'Skipped scheduling refresh-signals: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'refresh-signals-daily') then
    perform cron.unschedule('refresh-signals-daily');
  end if;

  perform cron.schedule(
    'refresh-signals-daily',
    '15 21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb,
        timeout_milliseconds := 240000
      );
    $f$, proj_url || '/functions/v1/refresh-signals', svc_key)
  );
end $$;
