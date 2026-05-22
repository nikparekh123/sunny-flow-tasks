-- math_snapshots: per-user saved calculator snapshots for the Math module.
--
-- Each row is one "Save calculation" event from a specific calculator. The
-- payload is calc-specific JSON (e.g. Percentage Difference stores
-- { from, to, fromLabel, toLabel }). Adding a new calculator does NOT require
-- a schema change — only an entry in the JS-side CALC_MODULES registry.

create table public.math_snapshots (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  calc_key    text not null,
  name        text not null,
  purpose     text,
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

-- Fast "give me my snapshots, newest first" — the History modal's only query.
create index math_snapshots_user_created_idx
  on public.math_snapshots (user_id, created_at desc);

-- Optional faster filter for "this calculator" in the History segmented control.
create index math_snapshots_user_calc_idx
  on public.math_snapshots (user_id, calc_key);

alter table public.math_snapshots enable row level security;

create policy "math_snapshots: owner select"
  on public.math_snapshots for select
  to authenticated
  using (auth.uid() = user_id);

create policy "math_snapshots: owner insert"
  on public.math_snapshots for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "math_snapshots: owner update"
  on public.math_snapshots for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "math_snapshots: owner delete"
  on public.math_snapshots for delete
  to authenticated
  using (auth.uid() = user_id);
