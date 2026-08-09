/* ============================================================
   planner_week_snapshots — what the planner thought, and when
   ============================================================
   The week score is only meaningful against its own history: a 68 means
   little until you know last week read 61. One row per ticker per day,
   written by nvda-planner on each run and idempotent on (ticker, taken_on),
   so opening the planner five times in a day leaves one row.

   `factors` stores each force's CONTRIBUTION (weight x score), not its raw
   score, because that is the number the screen shows and the only one that
   is comparable week to week — a weight change would otherwise look like a
   market change.
   ============================================================ */

create table if not exists public.planner_week_snapshots (
  id          uuid primary key default gen_random_uuid(),
  ticker      text not null,
  taken_on    date not null,
  score       int  not null,
  stance      text not null,
  factors     jsonb not null default '{}'::jsonb,   -- {force_key: contribution}
  posture     jsonb,                                 -- floor, upside delta, freeroll
  created_at  timestamptz default now(),
  unique (ticker, taken_on)
);

create index if not exists planner_snap_lookup_idx
  on public.planner_week_snapshots (ticker, taken_on desc);

alter table public.planner_week_snapshots enable row level security;

drop policy if exists planner_snap_read on public.planner_week_snapshots;
create policy planner_snap_read on public.planner_week_snapshots
  for select to authenticated using (true);

-- the edge function writes with the service role, which bypasses RLS
drop policy if exists planner_snap_write on public.planner_week_snapshots;
create policy planner_snap_write on public.planner_week_snapshots
  for all to service_role using (true) with check (true);
