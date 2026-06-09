/* ============================================================
   Refactor every HTTP-invoking cron to look up the service-role
   key at RUNTIME instead of embedding it at schedule time.

   Why: when Supabase rotates the service-role key (e.g. on a Pro
   upgrade), the embedded key in any already-scheduled cron job
   becomes invalid and every scheduled run starts returning 401.
   Manual invocations from the iOS app keep working because they
   use the anon key which is unaffected.

   Pattern: a SECURITY DEFINER helper `cron_invoke_function(name)`
   reads `vault.decrypted_secrets` on every call, then POSTs to
   the named edge function with a fresh JWT. Crons are rescheduled
   to call this helper, not bake the key in.

   This migration is idempotent — drops + reschedules every
   affected cron. Safe to re-run if a future rotation happens
   (you just bounce this file with a new timestamp).
   ============================================================ */

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

-- ─── Runtime helper ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cron_invoke_function(p_name text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  svc_key  text;
  proj_url text := 'https://ziwoutsnuywjnsyfbzsp.supabase.co';
  req_id   bigint;
BEGIN
  -- Fresh key every call. If it's missing we log + bail so a
  -- single broken cron doesn't blow up the whole pg_cron worker.
  SELECT decrypted_secret INTO svc_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF svc_key IS NULL THEN
    RAISE NOTICE 'cron_invoke_function(%): no service_role_key in vault', p_name;
    RETURN NULL;
  END IF;

  SELECT net.http_post(
    url     := proj_url || '/functions/v1/' || p_name,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || svc_key
    ),
    body    := '{}'::jsonb
  ) INTO req_id;
  RETURN req_id;
END $$;

REVOKE ALL ON FUNCTION public.cron_invoke_function(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_invoke_function(text) TO service_role;

-- ─── Reschedule every HTTP cron ─────────────────────────────────
DO $$
DECLARE
  -- (jobname, schedule, function_name)
  jobs text[][] := ARRAY[
    ['mp-refresh-15min',         '*/15 13-19 * * 1-5', 'mp-refresh'],
    ['daily-theta-snapshot',     '15 20 * * 1-5',      'daily-theta-snapshot'],
    ['position-snapshot',        '30 20 * * 1-5',      'position-snapshot'],
    ['health-monitor',           '*/30 * * * *',       'health-monitor'],
    ['alert-dispatcher',         '0 12,17 * * 1-5',    'alert-dispatcher'],
    ['apns-deliver',             '* * * * *',          'apns-deliver']
  ];
  r text[];
BEGIN
  FOREACH r SLICE 1 IN ARRAY jobs LOOP
    -- Drop the old (stale-key) version if it exists.
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = r[1]) THEN
      PERFORM cron.unschedule(r[1]);
    END IF;
    -- Reschedule with the runtime-key helper.
    PERFORM cron.schedule(
      r[1],
      r[2],
      format('SELECT public.cron_invoke_function(%L)', r[3])
    );
  END LOOP;
END $$;
