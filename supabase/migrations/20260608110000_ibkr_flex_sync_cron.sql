/* ============================================================
   ibkr-flex-sync cron — every 15 min, weekdays, US market hours
   ============================================================
   Matches the existing pattern used by mp-refresh-15min: read
   service-role key from vault.decrypted_secrets, idempotent
   schedule (unschedule any prior version first).

   Schedule: every 15 minutes from 13:00 UTC to 21:59 UTC, Mon–Fri.
   • In EDT (Mar–Nov): covers 9:00 AM – 5:45 PM ET
   • In EST (Nov–Mar): covers 8:00 AM – 4:45 PM ET
   Both windows include the full regular session (9:30–16:00 ET)
   plus a post-close sweep for late settles. Off-window runs are
   harmless — IBKR returns an empty TradeConfirms list and the
   sync_run row records 0 inserts.

   Body sends trigger=cron so ibkr_sync_runs.trigger reflects how
   the function was invoked (vs manual / backfill).
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
      'Skipped scheduling ibkr-flex-sync-15min: vault secret "service_role_key" is not set. '
      'Create it via vault.create_secret(...) and re-run this migration.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'ibkr-flex-sync-15min') then
    perform cron.unschedule('ibkr-flex-sync-15min');
  end if;

  perform cron.schedule(
    'ibkr-flex-sync-15min',
    '*/15 13-21 * * 1-5',
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
