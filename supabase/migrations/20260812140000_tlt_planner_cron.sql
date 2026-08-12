/* ============================================================
   tlt-planner-daily — fills the factor trail.
   ============================================================
   Every weekday at 14:00 UTC (10:00 ET), half an hour after the
   open.

   NOT thrice weekly, even though the decisions are. The trail is
   how conviction eventually gets validated — nine families are
   worth nothing until there is a history to check them against —
   and a daily row is a better record than three. The function
   already flags `isDecisionDay`, so Tuesday's row is context and
   Wednesday's is a decision without the schedule needing to know
   the difference.

   After the open rather than before it: pre-market option quotes
   are thin, and a plan priced off a modelled chain is a worse
   record than one priced off real bids. The app can invoke the
   function any time for a live answer; this job exists for the
   record, not for the recommendation.
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
      'Skipped scheduling tlt-planner-daily: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'tlt-planner-daily') then
    perform cron.unschedule('tlt-planner-daily');
  end if;

  perform cron.schedule(
    'tlt-planner-daily',
    '0 14 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/tlt-planner', svc_key)
  );
end $$;
