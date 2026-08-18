/* ============================================================
   The opportunity limits: cap, floor, ceiling, per-name share.

   Spec: docs/INCOME_OPPORTUNITY_SPEC.md

   The sleeve wrote on a weekly rhythm and sized in a fixed 25 contracts. The
   rhythm was never the strategy, and a fixed count is not a fixed size: 25 NFLX
   puts is a $190,000 promise and 25 CCL puts is a $133,000 one, and calling both
   "25" hid the actual risk.

   These four numbers replace both. Edge decides WHETHER to write, the cap
   decides HOW MUCH, and neither is a calendar.

   They live here rather than in the function so Nik can move them in the SQL
   editor without a deploy, the same reason ramp_start and ramp_cap do.

   TLT is deliberately NOT counted against commit_cap. It runs its own dip rule.
   Its short puts stood at $311,300 on 2026-08-18 against the sleeve's $180,800
   and they are a claim on the same cash, so a whole-book ceiling is worth having
   eventually. It is not part of this.
   ============================================================ */

alter table public.income_sleeve_settings
  add column if not exists commit_cap   numeric not null default 500000,
  add column if not exists edge_floor   numeric not null default 3,
  add column if not exists edge_ceiling numeric not null default 15,
  add column if not exists name_cap_pct numeric not null default 33;

comment on column public.income_sleeve_settings.commit_cap is
  'Dollars owed if every open sleeve put is assigned. The hard stop. Sleeve only, '
  'TLT is not counted.';
comment on column public.income_sleeve_settings.edge_floor is
  '7-day ATM implied vol minus 20-day realised, in points. Below this the option '
  'is not paying for the movement and there is no reason to write.';
comment on column public.income_sleeve_settings.edge_ceiling is
  'Above this an event is priced inside the week. A huge edge is a trap, not a find.';
comment on column public.income_sleeve_settings.name_cap_pct is
  'Most of the cap any single name may hold, as a percent. One name must not '
  'become the whole book.';

notify pgrst, 'reload schema';

select commit_cap, edge_floor, edge_ceiling, name_cap_pct,
       ramp_start, ramp_cap, ramp_paused
  from public.income_sleeve_settings where id = 1;
