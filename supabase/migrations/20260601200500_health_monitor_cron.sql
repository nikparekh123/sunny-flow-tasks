/* ============================================================
   health-monitor cron — runs every 30 min, all days. Cheap.
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
      'Skipped scheduling health-monitor: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'health-monitor') then
    perform cron.unschedule('health-monitor');
  end if;

  perform cron.schedule(
    'health-monitor',
    '*/30 * * * *',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/health-monitor', svc_key)
  );
end $$;
