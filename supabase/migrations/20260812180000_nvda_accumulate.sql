/* ============================================================
   nvda-accumulate — state and the factor trail
   ============================================================
   Spec: docs/NVDA_ACCUMULATION.md

   NVDA switches from monetising a block to building one, so it
   gets TLT's machinery rather than the covered-call planner's.
   The old nvda-planner and its screen are untouched.

   Two differences from the TLT tables, both measured rather
   than assumed (research/nvda-tenor):

   • The speed dial reads DISTANCE BELOW MA100, not a price.
     TLT oscillates around a yield so an absolute band works;
     NVDA trends, and a fixed price would either never fire or
     fire forever. MA100 discriminated best of seven references
     tested: below it the next month averaged +9.4%, above it
     +2.6%.

   • Conviction ships at WEIGHT ZERO. Six candidate signals were
     tested against 62 real weekly writes and none cleared the
     noise — the largest tertile spread was 1.29 against a 0.66
     standard error, and it was negative. The score is computed
     and stored every day so the trail can eventually test it;
     it does not move size until it has earned the right.
   ============================================================ */

create table if not exists public.nvda_planner_state (
  id             int primary key default 1 check (id = 1),
  target_shares  int  not null default 15000,
  quarter_budget int  not null default 2450,
  cash_ceiling   numeric not null default 400000,
  horizon_lo_wk  int  not null default 66,
  horizon_hi_wk  int  not null default 78,
  started_on     date not null default '2026-08-26',   -- after the reduction
  otm_pct        numeric not null default 0.01,        -- 1% out; see the strike table
  ma_window      int  not null default 100,            -- the speed dial's reference
  conviction_wt  numeric not null default 0.0,         -- ZERO until the trail proves otherwise
  updated_at     timestamptz default now()
);

insert into public.nvda_planner_state (id) values (1) on conflict (id) do nothing;

/* The trail. One row a day, whether or not anything was written, so the
   candidate signals accumulate a history to be judged against. This is the
   whole reason conviction is computed at all right now. */
create table if not exists public.nvda_planner_factor_daily (
  taken_on   date primary key,
  spot       numeric,
  ma         numeric,
  below_pct  numeric,          -- the speed dial's actual reading
  conviction int,              -- scored but unweighted
  families   jsonb,
  sizing     jsonb,
  outcome    jsonb,            -- filled in later: what the week's write actually did
  created_at timestamptz default now()
);

do $$
declare t text;
begin
  foreach t in array array['nvda_planner_factor_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname=t||'_auth_read') then
      execute format($p$create policy %I on public.%I for select to authenticated using (true)$p$, t||'_auth_read', t);
    end if;
  end loop;

  execute 'alter table public.nvda_planner_state enable row level security';
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='nvda_planner_state' and policyname='nvda_planner_state_auth_rw') then
    create policy nvda_planner_state_auth_rw on public.nvda_planner_state
      for all to authenticated using (true) with check (true);
  end if;
end $$;
