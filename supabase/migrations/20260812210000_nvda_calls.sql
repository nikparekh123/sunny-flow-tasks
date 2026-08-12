alter table public.nvda_planner_state
  add column if not exists calls_on      boolean not null default true,
  add column if not exists call_delta    numeric not null default 0.50,   -- ATM
  add column if not exists call_coverage numeric not null default 0.30;   -- 30% of the block
