/* ============================================================
   daily-theta-snapshot cron — capture today's portfolio θ burn
   once per weekday at market close.

   Same pattern as mp-refresh-15min: pulls service-role key from
   vault, idempotent (drops prior job before scheduling).

   Schedule: 20:15 UTC weekdays = ~16:15 ET during EDT (Mar–Nov),
   ~15:15 ET during EST (Nov–Mar). The greeks feed is 15-min
   delayed off Polygon, so a 16:15 ET capture is the freshest
   close-of-day data we can get. Single schedule trades ~1h drift
   in winter for simplicity vs maintaining two crons.
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
      'Skipped scheduling daily-theta-snapshot: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'daily-theta-snapshot') then
    perform cron.unschedule('daily-theta-snapshot');
  end if;

  perform cron.schedule(
    'daily-theta-snapshot',
    '15 20 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/daily-theta-snapshot', svc_key)
  );
end $$;
