/* ============================================================
   ibkr-flex-sync cron — tighten to every 5 min (was 15)
   ============================================================
   Cuts the "wait for the next cron tick" component of sync
   latency from an average ~7.5 min to ~2.5 min. IBKR's own TCF
   availability (~15 min after execution) is unchanged and still
   dominates; this only trims our side. 3× the invocations,
   negligible cost — off-window/empty runs return an empty
   TradeConfirms list and record 0 inserts.

   Rebuilds the command identically to the 15-min migration
   (service-role key from vault, {"trigger":"cron"} body) and
   renames the job to ibkr-flex-sync-5min so the name stays honest.
   Idempotent: unschedules any prior 15-min or 5-min job first.

   Schedule: every 5 minutes from 13:00 UTC to 21:59 UTC, Mon–Fri
   (same market-hours window as before).
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
      'Skipped scheduling ibkr-flex-sync-5min: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'ibkr-flex-sync-15min') then
    perform cron.unschedule('ibkr-flex-sync-15min');
  end if;
  if exists (select 1 from cron.job where jobname = 'ibkr-flex-sync-5min') then
    perform cron.unschedule('ibkr-flex-sync-5min');
  end if;

  perform cron.schedule(
    'ibkr-flex-sync-5min',
    '*/5 13-21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{"trigger":"cron"}'::jsonb,
        timeout_milliseconds := 60000
      );
    $f$, proj_url || '/functions/v1/ibkr-flex-sync', svc_key)
  );
end $$;
