/* ============================================================
   nvda-marks cron — the 60-second realtime feed.
   Every minute during US market hours (13:00–21:59 UTC, Mon–Fri):
   NVDA + peers spot → nvda_quote, and per-leg mark/greeks →
   nvda_option_marks. Off-hours/empty runs are harmless.
   ============================================================ */
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

do $$
declare
  proj_url text := 'https://ziwoutsnuywjnsyfbzsp.supabase.co';
  svc_key  text;
begin
  select decrypted_secret into svc_key from vault.decrypted_secrets where name = 'service_role_key' limit 1;
  if svc_key is null then
    raise notice 'Skipped nvda-marks-60s: vault secret "service_role_key" not set.';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'nvda-marks-60s') then
    perform cron.unschedule('nvda-marks-60s');
  end if;
  perform cron.schedule(
    'nvda-marks-60s',
    '* 13-21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || %L),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000
      );
    $f$, proj_url || '/functions/v1/nvda-marks', svc_key)
  );
end $$;
