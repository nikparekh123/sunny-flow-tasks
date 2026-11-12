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
  -- 400 s, the function's own limit (12 Nov 2026: NVDA's run after 18:00 New York takes about 200 s; the reply
  -- streams past 100 s, so the gateway keeps the call open).
  perform public.cron_invoke_function_body('gex-walls', jsonb_build_object('mode', 'tape_gamma', 'ticker', t), 400000);
  return t;
end $$;

select cron.unschedule('gamma-close-held') where exists (select 1 from cron.job where jobname = 'gamma-close-held');
select cron.schedule('gamma-close-held', '36-58/2 23 * * 1-5', 'select public.gamma_close_held()');

-- Prime a new name on its first night (12 Nov 2026: NVDA and SPCX showed only a Flip on Positions; each expiry's
-- Ceiling, Floor and Accelerator come from its view five sessions back, and a new name had only today's). Every 3
-- minutes from 22:00 to 23:57 UTC, one held name (any book) that needs it gets one step of gex-walls 'prime': the
-- five sessions before today (their tape, then their views in order, positions seeded from the first one's open
-- interest), then today's tape_gamma again. Each step answers within about 150 s. A name needs it while it has
-- views on fewer than 5 days in the 12 before today, or while an earlier day's views rebuilt today are newer than
-- today's (priming just finished). The names that need it take turns; the slots above still run as before.
create or replace function public.gamma_prime_held() returns text
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'America/New_York')::date;
  since timestamptz := today::timestamp at time zone 'America/New_York';
  names text[];
  t text;
begin
  if extract(isodow from today) > 5 or exists (select 1 from public.market_calendar where date = today and kind = 'closed') then
    return 'market closed';
  end if;
  select array_agg(k order by k) into names from (
    select distinct upper(jsonb_object_keys(payload->'strategies')) as k from public.home_snapshot
  ) h
  where (select count(distinct g.day) from public.gamma_view_day g where g.ticker = h.k and g.day < today and g.day >= today - 12) < 5
     or exists (select 1 from public.gamma_view_day p
                where p.ticker = h.k and p.view = 'all' and p.day < today and p.day >= today - 12 and p.built_at >= since
                  and p.built_at > coalesce((select max(c.built_at) from public.gamma_view_day c
                                             where c.ticker = h.k and c.view = 'all' and c.day = today), '-infinity'::timestamptz));
  if names is null then return 'every held name is primed'; end if;
  t := names[1 + ((extract(epoch from now())::bigint / 180) % array_length(names, 1))::int];
  perform public.cron_invoke_function_body('gex-walls', jsonb_build_object('mode', 'prime', 'ticker', t), 400000);
  return t;
end $$;

select cron.unschedule('gamma-prime-held') where exists (select 1 from cron.job where jobname = 'gamma-prime-held');
select cron.schedule('gamma-prime-held', '*/3 22-23 * * 1-5', 'select public.gamma_prime_held()');
