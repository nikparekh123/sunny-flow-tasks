/* ============================================================
   mp-refresh cron — Portfolio master data every 15 min during
   US market hours.

   Prereqs (one-time setup in Supabase dashboard → Database →
   Extensions): pg_cron, pg_net.

   Schedule: every 15 minutes from 13:30 UTC to 20:00 UTC, Mon–Fri.
   That's 9:30 AM – 4:00 PM ET during EDT (most of the year). During
   EST (Nov–Mar) the same UTC window covers 8:30 AM – 3:00 PM ET, so
   we get the first 30 minutes of pre-market and skip the last hour
   of regular trading — acceptable trade-off vs maintaining two
   schedules. (Polygon's 15-min delay anyway means data outside
   market hours is stale.)

   Same activation pattern as bnf-cache-nightly: the schedule body
   is commented out so the operator can substitute the project ref
   and service-role key once per environment.
   ============================================================ */

DO $$
DECLARE
  job_id integer;
BEGIN
  SELECT jobid INTO job_id FROM cron.job WHERE jobname = 'mp-refresh-15min';
  IF job_id IS NOT NULL THEN
    PERFORM cron.unschedule(job_id);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not available; skipping unschedule step';
END
$$;

-- Replace <PROJECT-REF> and <SERVICE-ROLE-KEY> with your values:
--
--   SELECT cron.schedule(
--     'mp-refresh-15min',
--     '*/15 13-19 * * 1-5',  -- every 15 min, 13:00–19:59 UTC, Mon–Fri
--                            -- (covers 9:30 AM – 3:45 PM ET in EDT;
--                            --  the first interval at 13:00 fires
--                            --  ~30 min before open which is fine)
--     $cron$
--     SELECT net.http_post(
--       url := 'https://<PROJECT-REF>.functions.supabase.co/mp-refresh',
--       headers := jsonb_build_object(
--         'Authorization', 'Bearer <SERVICE-ROLE-KEY>',
--         'Content-Type', 'application/json'
--       ),
--       body := '{}'::jsonb
--     );
--     $cron$
--   );

SELECT 1;
