/* ============================================================
   ticker-iv-snapshot cron — once daily after market close
   ============================================================
   Fires once per market day at 20:15 UTC (4:15pm ET in EDT,
   3:15pm ET in EST — both safely post-close on weekdays).

   That's late enough that closing prints have settled and IBKR /
   Polygon have updated end-of-day IV. We don't poll intraday
   because:
     • The Seller Score framing is "today's snapshot vs history".
     • Each run is ~13 Polygon calls (reference + snapshot per held
       ticker) — daily keeps total well under the free-tier ceiling.

   Body is empty {} — function has no inputs.
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
      'Skipped scheduling ticker-iv-snapshot-daily: vault secret "service_role_key" missing.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'ticker-iv-snapshot-daily') then
    perform cron.unschedule('ticker-iv-snapshot-daily');
  end if;

  perform cron.schedule(
    'ticker-iv-snapshot-daily',
    '15 20 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb,
        timeout_milliseconds := 120000
      );
    $f$, proj_url || '/functions/v1/ticker-iv-snapshot', svc_key)
  );
end $$;
