/* ============================================================
   planner-score-nightly — resolve every expired commit
   ============================================================
   Scores each row in planner_commits whose expiry has passed:
   the underlying close, what all three picks did, which one won,
   the regret against the one taken, and whether the order the
   tool offered matched the order the market produced.

   Runs at 22:15 UTC on weekdays — after the US close and after
   Polygon has settled the daily bar, so the close is available.

   Safe to over-run. A row is only picked up while scored_at is
   null, and a day with no close is skipped rather than written as
   a zero, so it simply retries the next night. Nothing is lost by
   the job firing on a holiday or a day with nothing to do.
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
      'Skipped scheduling planner-score-nightly: vault secret "service_role_key" is not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'planner-score-nightly') then
    perform cron.unschedule('planner-score-nightly');
  end if;

  perform cron.schedule(
    'planner-score-nightly',
    '15 22 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{"score":true}'::jsonb,
        timeout_milliseconds := 120000
      );
    $f$, proj_url || '/functions/v1/nvda-planner', svc_key)
  );
end $$;
