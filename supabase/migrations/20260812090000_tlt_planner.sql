/* ============================================================
   tlt-planner — state, rates cache, auction cache, factor trail
   ============================================================
   Spec: docs/TLT_ACCUMULATION.md

   Four tables, and only the first one holds a decision:

   • tlt_planner_state   Nik's inputs — phase, target, quarterly
                         budget, cash ceiling, horizon band. The
                         function reads these and never writes
                         them. A single row, id = 1.
   • rates_daily         FRED observation cache. FRED is the live
                         source on every run; this is the fallback
                         that keeps the planner answering when
                         stlouisfed is down, and the reason a
                         percentile survives a cold start.
   • tlt_auctions        Treasury Fiscal Data cache, long end only.
                         Same role as rates_daily.
   • tlt_planner_factor_daily
                         one row per day: the nine family scores as
                         they stood. Conviction cannot be validated
                         until there is a trail to validate against,
                         so the trail starts on day one even though
                         nothing reads it yet.

   tlt_voter_bloc and tlt_macro_events already exist (8 Aug) and are
   the `bloc` and `calendar` sources. Nothing here duplicates them.
   ============================================================ */

-- ── Nik's inputs ────────────────────────────────────────────
create table if not exists public.tlt_planner_state (
  id             int primary key default 1 check (id = 1),
  phase          text not null default 'ACCUMULATE'
                   check (phase in ('ACCUMULATE','HOLD','HARVEST')),
  target_shares  int  not null default 100000,
  quarter_budget int  not null default 11000,   -- 11-12K closes the band; 10K does not
  cash_ceiling   numeric not null default 400000,
  horizon_lo_wk  int  not null default 100,
  horizon_hi_wk  int  not null default 120,
  started_on     date not null default '2026-08-10',  -- first TLT leg
  put_delta_tgt  numeric not null default 0.50,   -- ATM; see research/tlt-strike-policy
  updated_at     timestamptz default now()
);

insert into public.tlt_planner_state (id) values (1) on conflict (id) do nothing;

-- ── FRED cache ──────────────────────────────────────────────
create table if not exists public.rates_daily (
  series text not null,
  date   date not null,
  value  numeric not null,
  primary key (series, date)
);
create index if not exists rates_daily_series_date_idx
  on public.rates_daily (series, date desc);

-- ── Treasury cache, long end only ───────────────────────────
create table if not exists public.tlt_auctions (
  cusip          text primary key,
  security_type  text,
  term_years     int,                -- 10 | 20 | 30, from original_security_term
  auction_date   date not null,
  announced_on   date,
  offering_amt   numeric,
  total_accepted numeric,
  bid_to_cover   numeric,
  dealer_accepted numeric,
  high_yield     numeric,
  updated_at     timestamptz default now()
);
create index if not exists tlt_auctions_date_idx on public.tlt_auctions (auction_date desc);

-- ── the factor trail ────────────────────────────────────────
create table if not exists public.tlt_planner_factor_daily (
  taken_on   date primary key,
  phase      text,
  spot       numeric,
  conviction int,
  families   jsonb,          -- [{key,label,cap,score,pct,note,ok}]
  sizing     jsonb,          -- {weeklyDelta,priceFactor,convFactor,contracts,capped}
  created_at timestamptz default now()
);

-- ── RLS: read for the app, writes stay with the service role ─
do $$
declare t text;
begin
  foreach t in array array['rates_daily','tlt_auctions','tlt_planner_factor_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname=t||'_auth_read') then
      execute format($p$create policy %I on public.%I for select to authenticated using (true)$p$, t||'_auth_read', t);
    end if;
  end loop;

  -- state is Nik's to change from the app, so it is read+write like the bloc table
  execute 'alter table public.tlt_planner_state enable row level security';
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='tlt_planner_state' and policyname='tlt_planner_state_auth_rw') then
    create policy tlt_planner_state_auth_rw on public.tlt_planner_state
      for all to authenticated using (true) with check (true);
  end if;
end $$;
