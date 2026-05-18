-- Schedule refresh-prices every 15 minutes during US market hours.
-- pg_cron uses UTC; 9:30–16:00 ET spans 13–21 UTC across EDT/EST, so we
-- schedule a broad weekday window. Polygon returns yesterday's close
-- outside hours so over-scheduling is wasted API calls, not harmful.
--
-- ── Setup (run ONCE before applying this migration) ─────────────────
-- The cron job calls the edge function with the service-role JWT. That
-- secret must live in Supabase Vault — we cannot ALTER DATABASE SET on
-- a hosted project. In the SQL editor:
--
--   select vault.create_secret(
--     '<paste service_role JWT here>',
--     'service_role_key',
--     'Used by pg_cron to invoke edge functions'
--   );
--
-- If a secret named 'service_role_key' already exists, the existing
-- value is reused — no need to recreate it.
-- ─────────────────────────────────────────────────────────────────────

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

do $$
declare
  proj_url text := 'https://ziwoutsnuywjnsyfbzsp.supabase.co';
  svc_key  text;
begin
  -- Pull service-role from Vault. If it isn't there, raise a notice
  -- and skip — the migration still succeeds so it can be re-run after
  -- the secret is created.
  select decrypted_secret into svc_key
  from vault.decrypted_secrets
  where name = 'service_role_key'
  limit 1;

  if svc_key is null then
    raise notice
      'Skipped scheduling refresh-prices: vault secret "service_role_key" is not set. '
      'Create it via vault.create_secret(...) and re-run this migration.';
    return;
  end if;

  -- Unschedule prior version if it exists.
  if exists (select 1 from cron.job where jobname = 'refresh-prices-15min') then
    perform cron.unschedule('refresh-prices-15min');
  end if;

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
