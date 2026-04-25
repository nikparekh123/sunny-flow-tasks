-- Schedule the refresh-prices edge function to run once per market day at
-- 16:30 ET (≈ 20:30 UTC during US daylight time, 21:30 UTC during standard
-- time — we go with 21:30 UTC year-round to guarantee the close has settled).
--
-- Requires pg_cron + pg_net extensions, both ON in default Supabase plans.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Drop any prior schedule with the same name so this migration is idempotent.
do $$
declare existing_jobid bigint;
begin
  select jobid into existing_jobid from cron.job where jobname = 'positions-daily-refresh';
  if existing_jobid is not null then perform cron.unschedule(existing_jobid); end if;
end $$;

-- The schedule needs to know how to call the edge function. We pull the
-- project URL + anon key from app-level GUCs; if they're not set, the cron
-- still installs but the call is a no-op until the secrets are configured.
--
-- Set these once in the Supabase SQL editor (replace with real values):
--   alter database postgres set "app.settings.supabase_url"      = '...';
--   alter database postgres set "app.settings.supabase_anon_key" = '...';
select cron.schedule(
  'positions-daily-refresh',
  '30 21 * * 1-5',  -- 21:30 UTC, Mon–Fri only
  $$
    select net.http_post(
      url := current_setting('app.settings.supabase_url', true) || '/functions/v1/refresh-prices',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.supabase_anon_key', true)
      ),
      body := '{}'::jsonb
    );
  $$
);
