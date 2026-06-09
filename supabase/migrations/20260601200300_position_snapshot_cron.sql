/* ============================================================
   position-snapshot cron — once per weekday at 20:30 UTC
   (~16:30 ET during EDT, ~15:30 ET during EST). Runs after the
   final mp-refresh capture of the day so current_price reflects
   close-of-day data.
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
      'Skipped scheduling position-snapshot: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'position-snapshot') then
    perform cron.unschedule('position-snapshot');
  end if;

  perform cron.schedule(
    'position-snapshot',
    '30 20 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/position-snapshot', svc_key)
  );
end $$;
