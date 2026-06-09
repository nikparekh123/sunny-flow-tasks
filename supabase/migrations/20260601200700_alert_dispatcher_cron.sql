/* ============================================================
   alert-dispatcher cron — twice daily during market hours, plus
   one pre-market sweep. Idempotent via dedup_key.
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
      'Skipped scheduling alert-dispatcher: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'alert-dispatcher') then
    perform cron.unschedule('alert-dispatcher');
  end if;

  -- Pre-market (~07:00 ET = 12:00 UTC), midday (~12:00 ET = 17:00 UTC),
  -- post-close (~16:30 ET = 21:30 UTC), weekdays only.
  perform cron.schedule(
    'alert-dispatcher',
    '0 12,17 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/alert-dispatcher', svc_key)
  );
end $$;
