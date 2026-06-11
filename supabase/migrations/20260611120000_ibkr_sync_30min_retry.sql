/* ============================================================
   IBKR sync: 30-min cadence with 15-min retry + failure alerts
   ============================================================
   Part of the stabilization pass. Three changes here:

   1. ibkr_sync_alerts NEW — failures that survive the 15-min
      retry land here. Deliberately NOT system_alerts: the
      alert-dispatcher cron mirrors that table to APNs push, and
      we explicitly want NO app-side notification for sync
      failures. The user reads this table from Claude Code.

   2. Replace the cron — same schedule (every 15 min, 13:00–21:59
      UTC, weekdays), renamed to ibkr-flex-sync-cron and
      re-pointed at the function. The function itself now decides
      whether to do work or no-op:
        • Outside 10:00–16:30 America/New_York → skip
        • :00 / :30 slots → always run (primary slot)
        • :15 / :45 slots → only run if the previous attempt
          failed (the retry pass)

   3. RPC `ibkr_alerts_recent` — convenience helper so future
      Claude Code sessions can say "show me recent IBKR sync
      failures" without having to look up the column list.

   Cron schedule kept at every-15-min on purpose: it lets the
   edge function self-gate to a true 30-min cadence with a
   single 15-min retry slot, without needing a second cron.
   ============================================================ */

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

-- ── 1. Failure alerts table ────────────────────────────────────
create table if not exists public.ibkr_sync_alerts (
  id           bigserial primary key,
  created_at   timestamptz not null default now(),
  run_id       uuid references public.ibkr_sync_runs(id) on delete set null,
  slot_minute  int  not null,                -- 15 or 45 (the retry slot)
  reason       text not null,                -- short human summary
  details      jsonb,                        -- run errors[], reference codes, etc.
  acknowledged bool not null default false,
  acknowledged_at timestamptz
);

create index if not exists ibkr_sync_alerts_created_idx
  on public.ibkr_sync_alerts (created_at desc);

create index if not exists ibkr_sync_alerts_open_idx
  on public.ibkr_sync_alerts (created_at desc)
  where acknowledged = false;

comment on table public.ibkr_sync_alerts is
  'IBKR sync failures that survived the in-window 15-min retry. '
  'Intentionally NOT system_alerts — alert-dispatcher does not '
  'forward these to APNs push. Read from Claude Code via the '
  'ibkr_alerts_recent() RPC.';

-- Service-role-only access. No anon/auth read.
alter table public.ibkr_sync_alerts enable row level security;

drop policy if exists ibkr_sync_alerts_service_all on public.ibkr_sync_alerts;
create policy ibkr_sync_alerts_service_all
  on public.ibkr_sync_alerts
  for all
  to service_role
  using (true)
  with check (true);

-- ── 2. Convenience RPC ─────────────────────────────────────────
create or replace function public.ibkr_alerts_recent(p_limit int default 20)
returns table (
  id bigint,
  created_at timestamptz,
  run_id uuid,
  slot_minute int,
  reason text,
  details jsonb,
  acknowledged bool
)
language sql
stable
security definer
set search_path = public
as $$
  select id, created_at, run_id, slot_minute, reason, details, acknowledged
  from public.ibkr_sync_alerts
  order by created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function public.ibkr_alerts_recent(int) to service_role;

-- ── 3. Rebuild cron ────────────────────────────────────────────
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
      'Skipped scheduling ibkr-flex-sync-cron: vault secret "service_role_key" is not set.';
    return;
  end if;

  -- Unschedule any prior versions.
  if exists (select 1 from cron.job where jobname = 'ibkr-flex-sync-15min') then
    perform cron.unschedule('ibkr-flex-sync-15min');
  end if;
  if exists (select 1 from cron.job where jobname = 'ibkr-flex-sync-cron') then
    perform cron.unschedule('ibkr-flex-sync-cron');
  end if;

  -- Every 15 min, 13:00–21:59 UTC, Mon–Fri. Edge function
  -- gates to ET wall clock and slot-of-hour:
  --   • Skip outside 10:00–16:30 America/New_York
  --   • :00 / :30 → primary slot, always run
  --   • :15 / :45 → retry slot, only run if last attempt failed
  --
  -- UTC 13–21 covers both EDT (UTC-4 → 9:00–17:59 ET) and EST
  -- (UTC-5 → 8:00–16:59 ET); the ET window check inside the
  -- function does the precise gating.
  perform cron.schedule(
    'ibkr-flex-sync-cron',
    '*/15 13-21 * * 1-5',
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body    := '{"trigger":"cron"}'::jsonb,
        timeout_milliseconds := 60000
      );
    $f$, proj_url || '/functions/v1/ibkr-flex-sync', svc_key)
  );
end $$;
