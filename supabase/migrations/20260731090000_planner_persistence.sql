-- Planner server-side persistence: guardrail settings + the calibration/commit log.
-- Both are per-user (auth.uid()), RLS-scoped so a signed-in user only sees their own.

-- ── guardrail settings (one row per user) ──
create table if not exists public.planner_settings (
  user_id       uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  min_net_delta double precision not null default 500,
  max_assign    double precision not null default 0.55,
  edge_floor    double precision not null default -0.40,
  weekend_vol   double precision not null default 0.3,
  edge_lookback text             not null default 'hv30',
  updated_at    timestamptz      not null default now()
);
alter table public.planner_settings enable row level security;
drop policy if exists "own planner_settings" on public.planner_settings;
create policy "own planner_settings" on public.planner_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── calibration / commit log (one row per logged short-call cycle) ──
create table if not exists public.planner_intents (
  user_id       uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  id            text        not null,               -- client cycle id (leg key or uuid)
  ts            timestamptz not null,               -- when the cycle was sold
  expiry        text,
  strike        double precision,
  ct            double precision,
  mid           double precision,                   -- mid at the sale
  fill          double precision,                   -- actual fill (mid − slip)
  p_assign      double precision,                   -- N(d2) predicted at the sale
  assigned      boolean,
  implied_move  double precision,
  realized_move double precision,
  settled       boolean     not null default false,
  created_at    timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.planner_intents enable row level security;
drop policy if exists "own planner_intents" on public.planner_intents;
create policy "own planner_intents" on public.planner_intents
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists planner_intents_user_ts on public.planner_intents (user_id, ts desc);
