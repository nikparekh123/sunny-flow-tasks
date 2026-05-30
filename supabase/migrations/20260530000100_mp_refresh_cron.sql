/* ============================================================
   mp-refresh cron — Portfolio master data every 15 min during
   US market hours.

   Matches the pattern of `20260520154339_hourly_market_refresh.sql`:
   reads the service-role key from `vault.decrypted_secrets` (created
   once via `vault.create_secret(...)` per environment) instead of
   hard-coding it into the cron body. Idempotent — drops any prior
   version of the job before scheduling.

   Schedule: every 15 minutes from 13:00 UTC to 19:59 UTC, Mon–Fri.
   That covers 9:30 AM – 3:45 PM ET during EDT (most of the year). In
   EST (Nov–Mar) the same window covers 8:30 AM – 2:45 PM ET — early
   start, no last hour. Trade-off vs maintaining two schedules. (The
   15-min Polygon delay means data outside market hours is stale
   anyway, so the off-hour overlap is harmless.)
   ============================================================ */

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
      'Skipped scheduling mp-refresh-15min: vault secret "service_role_key" is not set. '
      'Create it via vault.create_secret(...) and re-run this migration.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'mp-refresh-15min') then
    perform cron.unschedule('mp-refresh-15min');
  end if;

  perform cron.schedule(
    'mp-refresh-15min',
    '*/15 13-19 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/mp-refresh', svc_key)
  );
end $$;
