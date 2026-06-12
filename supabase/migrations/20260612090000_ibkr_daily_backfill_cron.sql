/* ============================================================
   ibkr-flex-backfill-daily cron — nightly Daily Flex sweep
   ============================================================
   The TCF cron (ibkr-flex-sync-cron) is real-time but fragile:
   TCF reports only return the CURRENT execution day. Any trade
   missed during the trading day — late settles, cron stalls,
   after-hours fills — falls off the TCF feed at midnight and
   only manual intervention recovers it.

   This second cron eliminates that recovery problem. It runs
   once nightly at 09:00 UTC against a SEPARATE Daily Flex query
   (ID 1540791 — type Daily Flex, period "Last 5 Business Days").
   Upserts key on ibkr_trade_id:

     • Trades already captured by TCF intraday → same id seen
       again → row updated in place (essentially a no-op).
     • Trades MISSED by TCF (the failure mode the user keeps
       hitting) → new id → inserted overnight, automatically.

   No duplicates. No overwrites. The user never has to manually
   backfill again.

   Schedule: 09:00 UTC daily Mon–Fri.
     • In EDT (Mar–Nov): 05:00 ET — well after market close,
       Daily Flex's T+1 latency has settled.
     • In EST (Nov–Mar): 04:00 ET — same logic.
     • Weekend runs would be a no-op (nothing new to backfill),
       but we skip them entirely to keep the cron history clean.

   trigger=backfill bypasses the edge function's ET-window gate
   so a 5am ET call is allowed; cron triggers stay gated to
   10:00–16:30 ET.

   The query_id override in the request body is what makes this
   safe — the intraday cron's `IBKR_FLEX_QUERY_ID` env var
   (1535729, TCF "Today") is untouched.
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
      'Skipped scheduling ibkr-flex-backfill-daily: vault secret "service_role_key" is not set.';
    return;
  end if;

  -- Idempotent: drop any prior incarnation before re-scheduling.
  if exists (select 1 from cron.job where jobname = 'ibkr-flex-backfill-daily') then
    perform cron.unschedule('ibkr-flex-backfill-daily');
  end if;

  perform cron.schedule(
    'ibkr-flex-backfill-daily',
    '0 9 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := jsonb_build_object(
          'trigger',  'backfill',
          'query_id', '1540791'
        ),
        timeout_milliseconds := 90000
      );
    $f$, proj_url || '/functions/v1/ibkr-flex-sync', svc_key)
  );
end $$;
