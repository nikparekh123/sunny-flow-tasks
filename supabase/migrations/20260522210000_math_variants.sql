-- math_snapshots.kind — distinguish saved "snapshots" (per-ticker winners
-- shown in the global Compare view) from "variants" (per-ticker exploration
-- scratchpad, e.g. "what's the best NVDA put frequency?").
--
-- Default 'snapshot' for backfill — every existing row was already meant
-- to be a snapshot. New saves continue to be snapshots unless a variant
-- save flow asks for kind='variant' explicitly.

alter table public.math_snapshots
  add column kind text not null default 'snapshot'
    check (kind in ('snapshot', 'variant'));

-- Variants are queried as "all my IvC variants for NVDA right now" — a
-- per-calc / per-ticker subquery filtered by kind. This index covers it.
create index math_snapshots_user_kind_calc_idx
  on public.math_snapshots (user_id, kind, calc_key);
