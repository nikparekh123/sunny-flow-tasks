-- Gamma walls for every held name, in any book, as soon as it is held (Nik, 12 Nov 2026: "No walls for SpaceX and
-- NVDA, we should get walls and technicals as soon as a new position in a new company is made").
-- The per-name jobs (gamma-close-baba ... gamma-close-uber, 23:20-23:34 UTC) stay. This one runs in 2-minute slots
-- from 23:36 to 23:58 UTC and, in slot i, runs gex-walls tape_gamma for the i-th held name (A to Z, every book's Home
-- strategy map) that has no job of its own. A new name is seeded from open interest on its first run.
create or replace function public.gamma_close_held() returns text
language plpgsql security definer set search_path = public as $$
declare
  slot int := (extract(minute from now())::int - 36) / 2;
  t text;
begin
  if slot < 0 then return 'before the first slot'; end if;
  select k into t from (
    select k, row_number() over (order by k) - 1 as i from (
      select distinct upper(jsonb_object_keys(payload->'strategies')) as k from public.home_snapshot
    ) h
    where not exists (select 1 from cron.job j where j.jobname = 'gamma-close-' || lower(h.k) and j.active)
  ) x where x.i = slot;
  if t is null then return 'no name in slot ' || slot; end if;
  perform public.cron_invoke_function_body('gex-walls', jsonb_build_object('mode', 'tape_gamma', 'ticker', t), 240000);
  return t;
end $$;

select cron.unschedule('gamma-close-held') where exists (select 1 from cron.job where jobname = 'gamma-close-held');
select cron.schedule('gamma-close-held', '36-58/2 23 * * 1-5', 'select public.gamma_close_held()');
