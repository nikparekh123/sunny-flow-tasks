-- Schedule refresh-prices every 15 minutes during US market hours.
-- pg_cron uses UTC. Regular session = 9:30–16:00 ET, which is
-- 13:30–20:00 UTC (EDT) or 14:30–21:00 UTC (EST). We schedule a
-- broad window 13–21 UTC Mon–Fri, then guard inside the function
-- with day-of-week check at insert (Polygon returns yesterday's
-- close outside hours anyway, so over-scheduling is just wasted
-- API calls, not harmful).
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

-- Project ref + service role are read from Supabase Vault if available;
-- fall back to settings inline (will need to be set manually post-deploy).
do $$
declare
  proj_url   text := current_setting('app.supabase_url',         true);
  svc_key    text := current_setting('app.supabase_service_role', true);
begin
  if proj_url is null or svc_key is null then
    raise notice 'Set app.supabase_url and app.supabase_service_role before scheduling.';
    return;
  end if;

  -- Unschedule prior version if it exists.
  perform cron.unschedule('refresh-prices-15min')
    where exists (
      select 1 from cron.job where jobname = 'refresh-prices-15min'
    );

  perform cron.schedule(
    'refresh-prices-15min',
    '*/15 13-21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{}'::jsonb
      );
    $f$, proj_url || '/functions/v1/refresh-prices', svc_key)
  );
end $$;
