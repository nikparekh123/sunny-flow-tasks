-- Scheduler key (audit, 13 Oct 2026).
--
-- Every scheduled call now carries `x-cron-key`, a dedicated random secret
-- (vault `cron_secret`, edge secret CRON_SECRET), and the cron-called
-- functions refuse callers without it, the service-role key, or (where the app
-- or website call them) a signed-in user. Before this, the scheduler sent the
-- vault's `service_role_key`, which held an sb_secret key wrapped in literal
-- "<...>" brackets: no function could check it, so every cron-called function
-- ran verify_jwt off and answered anyone. Five jobs also carried that key
-- inline in their command text; they now go through the helper and no job
-- holds a key.

create or replace function public.cron_invoke_function(p_name text)
returns bigint language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare cron_key text; req_id bigint;
begin
  select decrypted_secret into cron_key from vault.decrypted_secrets where name = 'cron_secret' limit 1;
  if cron_key is null then raise notice 'cron_invoke_function(%): no cron_secret in vault', p_name; return null; end if;
  select net.http_post(
    url := 'https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/' || p_name,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-key', cron_key),
    body := '{}'::jsonb) into req_id;
  return req_id;
end $$;

drop function if exists public.cron_invoke_function_body(text, jsonb);
create or replace function public.cron_invoke_function_body(p_name text, p_body jsonb, p_timeout_ms int default 60000)
returns bigint language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare cron_key text; req_id bigint;
begin
  select decrypted_secret into cron_key from vault.decrypted_secrets where name = 'cron_secret' limit 1;
  if cron_key is null then raise notice 'cron_invoke_function_body(%): no cron_secret in vault', p_name; return null; end if;
  select net.http_post(
    url := 'https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/' || p_name,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-key', cron_key),
    body := p_body, timeout_milliseconds := p_timeout_ms) into req_id;
  return req_id;
end $$;

select cron.alter_job(jobid, command := $$ SELECT public.cron_invoke_function_body('refresh-prices', '{}'::jsonb) $$)
  from cron.job where jobname = 'refresh-prices-hourly';
select cron.alter_job(jobid, command := $$ SELECT public.cron_invoke_function_body('ibkr-flex-sync', '{"trigger":"cron"}'::jsonb, 60000) $$)
  from cron.job where jobname = 'ibkr-flex-sync-5min';
select cron.alter_job(jobid, command := $$ SELECT public.cron_invoke_function_body('ibkr-flex-sync', '{"trigger":"backfill","query_id":"1540791"}'::jsonb, 90000) $$)
  from cron.job where jobname = 'ibkr-flex-backfill-daily';
select cron.alter_job(jobid, command := $$ SELECT public.cron_invoke_function_body('ticker-iv-snapshot', '{}'::jsonb, 120000) $$)
  from cron.job where jobname = 'ticker-iv-snapshot-daily';
select cron.alter_job(jobid, command := $$ SELECT public.cron_invoke_function_body('earnings-sync', '{}'::jsonb, 240000) $$)
  from cron.job where jobname = 'earnings-sync-daily';
