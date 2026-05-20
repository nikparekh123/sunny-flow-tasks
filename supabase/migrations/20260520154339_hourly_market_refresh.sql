-- Reschedule price + put-quote refreshes to run hourly during US market
-- hours on weekdays. Per pricing review (Polygon free tier: 5 calls/min,
-- no daily cap) hourly is the right cadence: ~7-9 runs/day, totally safe.
--
-- US market is open 9:30 → 16:00 ET. pg_cron runs in UTC, so we need a
-- window that covers both EST (winter, UTC-5) and EDT (summer, UTC-4):
--   EST: 9:30-16 ET = 14:30-21:00 UTC
--   EDT: 9:30-16 ET = 13:30-20:00 UTC
-- We schedule top-of-hour from 13:00 → 21:00 UTC weekdays — covers both
-- regimes. Polygon returns the previous close when called outside hours,
-- so any "overflow" run during the wrong DST is wasted but not harmful.
--
-- Prereq (same as the previous migration): vault secret 'service_role_key'
-- must already exist. If it doesn't, the migration logs a notice and
-- skips scheduling.

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
      'Skipped scheduling: vault secret "service_role_key" is not set. '
      'Create it via vault.create_secret(...) and re-run this migration.';
    return;
  end if;

  -- Drop the prior 15-minute schedule + any earlier versions of this job.
  if exists (select 1 from cron.job where jobname = 'refresh-prices-15min') then
    perform cron.unschedule('refresh-prices-15min');
  end if;
  if exists (select 1 from cron.job where jobname = 'refresh-prices-hourly') then
    perform cron.unschedule('refresh-prices-hourly');
  end if;
  if exists (select 1 from cron.job where jobname = 'refresh-put-quotes-hourly') then
    perform cron.unschedule('refresh-put-quotes-hourly');
  end if;

  -- Stock prices: 1 API call per run (Polygon batch snapshot endpoint).
  perform cron.schedule(
    'refresh-prices-hourly',
    '0 13-21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/refresh-prices', svc_key)
  );

  -- Put option quotes: one API call per active put contract. Hourly is
  -- well within Polygon's 5-calls-per-minute rate limit even if you hold
  -- 10+ active puts.
  perform cron.schedule(
    'refresh-put-quotes-hourly',
    '0 13-21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/refresh-put-quotes', svc_key)
  );
end $$;
