-- Nightly cron: refresh the BNF universe cache after US market close.
--
-- Prereqs (one-time setup in Supabase dashboard → Database → Extensions):
--   • pg_cron  — schedules SQL jobs at fixed times
--   • pg_net   — http_post() for invoking edge functions
--
-- The cron fires at 22:30 UTC = 6:30pm ET Mon–Fri (markets close 4pm ET,
-- Polygon publishes EOD data within ~30 min). We invoke bnf-cache-update
-- which pulls the previous-trading-day grouped snapshot.
--
-- The SUPABASE service role key must be set in vault — the cron job
-- references it as vault.decrypted_secrets so it can hit the function.

-- Idempotent: unschedule if it already exists, then create.
DO $$
DECLARE
  job_id integer;
BEGIN
  SELECT jobid INTO job_id FROM cron.job WHERE jobname = 'bnf-cache-nightly';
  IF job_id IS NOT NULL THEN
    PERFORM cron.unschedule(job_id);
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not installed yet; the schedule call below will also fail
  -- and the operator will see the missing-extension error.
  RAISE NOTICE 'pg_cron not available; skipping unschedule step';
END
$$;

-- NOTE: the project ref and service-role key need to be substituted
-- before running. We can't bake them in here because they're per-env
-- secrets. The operator should edit this file once during initial
-- setup, or run the equivalent SQL manually in the SQL editor.
--
-- Replace <PROJECT-REF> and <SERVICE-ROLE-KEY> with your values:
--
--   SELECT cron.schedule(
--     'bnf-cache-nightly',
--     '30 22 * * 1-5',  -- 22:30 UTC, Mon-Fri
--     $cron$
--     SELECT net.http_post(
--       url := 'https://<PROJECT-REF>.functions.supabase.co/bnf-cache-update',
--       headers := jsonb_build_object(
--         'Authorization', 'Bearer <SERVICE-ROLE-KEY>',
--         'Content-Type', 'application/json'
--       ),
--       body := '{}'::jsonb
--     );
--     $cron$
--   );

-- For now this migration just makes sure the table + extension expectations
-- are documented. The schedule itself stays in operator hands until you
-- want to point it at the right project. To activate, uncomment the
-- SELECT cron.schedule(...) block above and substitute the placeholders.
SELECT 1;
