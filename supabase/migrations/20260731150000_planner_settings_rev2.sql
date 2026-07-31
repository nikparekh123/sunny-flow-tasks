-- Planner rev2: extend planner_settings with the Upside Room weights, the
-- bias/ATH-room knobs, and the reference-level tiebreak. max_assign is retired
-- (assignment is no longer a blocker) but left in place harmlessly if present.
alter table public.planner_settings add column if not exists min_ext       double precision not null default 0.25;
alter table public.planner_settings add column if not exists w_range       double precision not null default 0.30;
alter table public.planner_settings add column if not exists w_ath         double precision not null default 0.30;
alter table public.planner_settings add column if not exists w_rsi         double precision not null default 0.20;
alter table public.planner_settings add column if not exists w_ma          double precision not null default 0.20;
alter table public.planner_settings add column if not exists ath_full_room double precision not null default 30;
alter table public.planner_settings add column if not exists bias_max      double precision not null default 2.5;
alter table public.planner_settings add column if not exists bias_span     double precision not null default 3.5;
alter table public.planner_settings add column if not exists rally_pct     double precision not null default 0.15;
alter table public.planner_settings add column if not exists tiebreak_band double precision not null default 1.5;
