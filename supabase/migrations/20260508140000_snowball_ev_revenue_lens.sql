-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — EV/Revenue as the 6th lens. Critical for unprofitable
-- growth names (SaaS, recent IPOs) where DCF/EPV/EV-EBITDA/P-E all
-- produce negative or null intrinsics.
--
-- New 6-lens weighting: 25 / 20 / 15 / 15 / 15 / 10
--   DCF        25%
--   EPV        20%
--   EV/EBITDA  15%
--   EV/Revenue 15% (NEW)
--   P/E        15%
--   Earn Yield 10%
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  add column if not exists revenue_ttm           numeric,
  add column if not exists target_ev_revenue     numeric default 3,
  add column if not exists intrinsic_ev_revenue  numeric,
  add column if not exists weight_ev_revenue     numeric default 0.15;

alter table public.snowball_sector_defaults
  add column if not exists default_ev_revenue numeric default 3;

-- Re-balance existing rows to the 6-lens split.
update public.snowball
set
  weight_dcf            = 0.25,
  weight_epv            = 0.20,
  weight_ev_ebitda      = 0.15,
  weight_ev_revenue     = 0.15,
  weight_pe             = 0.15,
  weight_earnings_yield = 0.10;

-- Update column defaults so newly-inserted stocks get the same.
alter table public.snowball
  alter column weight_dcf            set default 0.25,
  alter column weight_epv            set default 0.20,
  alter column weight_ev_ebitda      set default 0.15,
  alter column weight_ev_revenue     set default 0.15,
  alter column weight_pe             set default 0.15,
  alter column weight_earnings_yield set default 0.10;

-- Seed EV/Revenue per sector — user-specified values.
insert into public.snowball_sector_defaults
  (sector, target_pe, target_ev_ebitda, default_growth_pct,
   default_stage2_growth_pct, default_discount_rate_pct, default_ev_revenue) values
  ('Technology',                25, 18, 12, 7, 10, 8.0),
  ('Communication Services',    20, 12,  7, 5,  9, 6.0),
  ('Communications',            20, 12,  7, 5,  9, 6.0),
  ('Healthcare',                20, 14,  8, 5,  9, 5.0),
  ('Consumer Discretionary',    22, 14,  9, 5, 10, 3.0),
  ('Consumer Cyclicals',        22, 14,  9, 5, 10, 3.0),
  ('Industrials',               18, 11,  6, 4,  9, 2.5),
  ('Financials',                12, 12,  7, 4, 10, 2.0),
  ('Real Estate',               22, 18,  5, 3,  8, 2.5),
  ('Consumer Non-Cyclicals',    25, 18,  5, 3,  8, 2.0),
  ('Consumer Staples',          25, 18,  5, 3,  8, 2.0),
  ('Materials',                 14,  9,  5, 3, 10, 1.5),
  ('Basic Materials',           14,  9,  5, 3, 10, 1.5),
  ('Energy',                    12,  6,  4, 3, 11, 1.5),
  ('Utilities',                 18, 10,  4, 3,  7, 2.0),
  ('Telecommunications Services', 15, 10, 4, 3,  8, 2.0)
on conflict (sector) do update set
  default_ev_revenue = excluded.default_ev_revenue,
  updated_at         = now();

-- EV/Revenue lens function.
create or replace function public.snowball_ev_revenue(
  revenue numeric,
  multiple numeric,
  debt numeric,
  cash numeric,
  shares numeric
)
returns numeric
language sql immutable as $$
  select case
    when revenue is null or multiple is null then null
    when shares is null or shares <= 0       then null
    else (revenue * multiple - coalesce(debt, 0) + coalesce(cash, 0)) / shares
  end;
$$;

-- 6-lens compute_lenses.
create or replace function public.snowball_compute_lenses(
  oe       numeric, shares numeric,
  g1       numeric, g2 numeric, d numeric, tg numeric,
  eps      numeric, target_pe numeric,
  ebitda   numeric, target_ev_ebitda numeric,
  revenue  numeric, target_ev_revenue numeric,
  debt numeric, cash numeric,
  w_dcf    numeric, w_pe numeric, w_eve numeric, w_evr numeric,
  w_epv    numeric, w_ey numeric
)
returns table(
  intrinsic_dcf            numeric,
  intrinsic_pe             numeric,
  intrinsic_ev_ebitda      numeric,
  intrinsic_ev_revenue     numeric,
  intrinsic_epv            numeric,
  intrinsic_earnings_yield numeric,
  intrinsic_weighted       numeric
)
language sql immutable as $$
  with d_dcf as ( select public.snowball_dcf_intrinsic_3stage(oe, shares, g1, g2, d, tg) as v ),
  d_pe  as ( select case when eps is null or target_pe is null then null
                         else eps * target_pe end as v ),
  d_eve as ( select case
                      when ebitda is null or target_ev_ebitda is null
                        or shares is null or shares <= 0 then null
                      else (ebitda * target_ev_ebitda
                            - coalesce(debt, 0) + coalesce(cash, 0)) / shares
                    end as v ),
  d_evr as ( select public.snowball_ev_revenue(revenue, target_ev_revenue, debt, cash, shares) as v ),
  d_epv as ( select public.snowball_epv(oe, d, debt, cash, shares) as v ),
  d_ey  as ( select public.snowball_earnings_yield(eps, d) as v )
  select
    d_dcf.v as intrinsic_dcf,
    d_pe.v  as intrinsic_pe,
    d_eve.v as intrinsic_ev_ebitda,
    d_evr.v as intrinsic_ev_revenue,
    d_epv.v as intrinsic_epv,
    d_ey.v  as intrinsic_earnings_yield,
    case
      when d_dcf.v is null and d_pe.v is null and d_eve.v is null
       and d_evr.v is null and d_epv.v is null and d_ey.v is null then null
      else (
        coalesce(d_dcf.v * w_dcf, 0)
        + coalesce(d_pe.v  * w_pe,  0)
        + coalesce(d_eve.v * w_eve, 0)
        + coalesce(d_evr.v * w_evr, 0)
        + coalesce(d_epv.v * w_epv, 0)
        + coalesce(d_ey.v  * w_ey,  0)
      ) / nullif((
        case when d_dcf.v is null then 0 else w_dcf end
        + case when d_pe.v  is null then 0 else w_pe  end
        + case when d_eve.v is null then 0 else w_eve end
        + case when d_evr.v is null then 0 else w_evr end
        + case when d_epv.v is null then 0 else w_epv end
        + case when d_ey.v  is null then 0 else w_ey  end
      ), 0)
    end as intrinsic_weighted
  from d_dcf, d_pe, d_eve, d_evr, d_epv, d_ey;
$$;

-- apply_defaults updated for 6-lens.
create or replace function public.snowball_apply_defaults(
  p_growth   numeric,
  p_discount numeric,
  p_terminal numeric,
  p_growth2  numeric default null
)
returns int
language sql security definer set search_path = public as $$
  with computed as (
    select s.ticker, l.*
    from public.snowball s
    cross join lateral public.snowball_compute_lenses(
      s.total_owner_earnings, s.shares_outstanding,
      p_growth/100,
      coalesce(p_growth2, (p_growth + p_terminal) / 2) / 100,
      p_discount/100,
      p_terminal/100,
      s.eps_ttm, s.target_pe,
      s.ebitda_ttm, s.target_ev_ebitda,
      s.revenue_ttm, s.target_ev_revenue,
      s.total_debt, s.cash_and_equivalents,
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda, s.weight_ev_revenue,
      s.weight_epv, s.weight_earnings_yield
    ) l
  ),
  with_quality as (
    select c.*,
      case
        when s.equity_book is null or s.equity_book <= 0
          or s.net_income_ttm is null then null
        else (s.net_income_ttm / s.equity_book) * 100
      end as roe_pct
    from computed c
    join public.snowball s on s.ticker = c.ticker
  ),
  updated as (
    update public.snowball s
    set
      stage1_growth_pct        = p_growth,
      stage2_growth_pct        = coalesce(p_growth2, (p_growth + p_terminal) / 2),
      discount_rate_pct        = p_discount,
      terminal_growth_pct      = p_terminal,
      intrinsic_dcf            = c.intrinsic_dcf,
      intrinsic_pe             = c.intrinsic_pe,
      intrinsic_ev_ebitda      = c.intrinsic_ev_ebitda,
      intrinsic_ev_revenue     = c.intrinsic_ev_revenue,
      intrinsic_epv            = c.intrinsic_epv,
      intrinsic_earnings_yield = c.intrinsic_earnings_yield,
      intrinsic_weighted       = c.intrinsic_weighted,
      intrinsic_value          = c.intrinsic_weighted,
      tbp_aggressive_15        = c.intrinsic_weighted * 0.85,
      tbp_conservative_30      = c.intrinsic_weighted * 0.70,
      tbp_deep_value_50        = c.intrinsic_weighted * 0.50,
      roe                      = c.roe_pct,
      is_high_quality          = coalesce(c.roe_pct >= 15, false),
      is_customized            = false
    from with_quality c
    where s.ticker = c.ticker
    returning s.ticker
  )
  select count(*)::int from updated;
$$;

-- apply_sector_defaults updated for 6-lens (uses new EV/Rev sector default).
create or replace function public.snowball_apply_sector_defaults()
returns int
language sql security definer set search_path = public as $$
  with applied as (
    update public.snowball s
    set
      target_pe          = sd.target_pe,
      target_ev_ebitda   = sd.target_ev_ebitda,
      target_ev_revenue  = sd.default_ev_revenue,
      stage1_growth_pct  = coalesce(s.historical_growth_pct, sd.default_growth_pct),
      stage2_growth_pct  = sd.default_stage2_growth_pct,
      discount_rate_pct  = sd.default_discount_rate_pct,
      is_customized      = false
    from public.snowball_sector_defaults sd
    where s.sector = sd.sector
      and (s.is_customized = false or s.is_customized is null)
    returning s.ticker
  ),
  computed as (
    select s.ticker, l.*
    from public.snowball s
    join applied a on a.ticker = s.ticker
    cross join lateral public.snowball_compute_lenses(
      s.total_owner_earnings, s.shares_outstanding,
      s.stage1_growth_pct / 100,
      coalesce(s.stage2_growth_pct, (s.stage1_growth_pct + s.terminal_growth_pct) / 2) / 100,
      s.discount_rate_pct / 100,
      coalesce(s.terminal_growth_pct, 2) / 100,
      s.eps_ttm, s.target_pe,
      s.ebitda_ttm, s.target_ev_ebitda,
      s.revenue_ttm, s.target_ev_revenue,
      s.total_debt, s.cash_and_equivalents,
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda, s.weight_ev_revenue,
      s.weight_epv, s.weight_earnings_yield
    ) l
  ),
  recomputed as (
    update public.snowball s
    set
      intrinsic_dcf            = c.intrinsic_dcf,
      intrinsic_pe             = c.intrinsic_pe,
      intrinsic_ev_ebitda      = c.intrinsic_ev_ebitda,
      intrinsic_ev_revenue     = c.intrinsic_ev_revenue,
      intrinsic_epv            = c.intrinsic_epv,
      intrinsic_earnings_yield = c.intrinsic_earnings_yield,
      intrinsic_weighted       = c.intrinsic_weighted,
      intrinsic_value          = c.intrinsic_weighted,
      tbp_aggressive_15        = c.intrinsic_weighted * 0.85,
      tbp_conservative_30      = c.intrinsic_weighted * 0.70,
      tbp_deep_value_50        = c.intrinsic_weighted * 0.50
    from computed c
    where s.ticker = c.ticker
    returning s.ticker
  )
  select count(*)::int from recomputed;
$$;

-- recompute_one updated for 6-lens.
create or replace function public.snowball_recompute_one(p_ticker text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  l record;
begin
  select * into r from public.snowball where ticker = p_ticker;
  if not found then return; end if;

  select * into l from public.snowball_compute_lenses(
    r.total_owner_earnings, r.shares_outstanding,
    coalesce(r.stage1_growth_pct, 8) / 100,
    coalesce(
      r.stage2_growth_pct,
      (coalesce(r.stage1_growth_pct, 8) + coalesce(r.terminal_growth_pct, 2)) / 2
    ) / 100,
    coalesce(r.discount_rate_pct, 10) / 100,
    coalesce(r.terminal_growth_pct, 2) / 100,
    r.eps_ttm, r.target_pe,
    r.ebitda_ttm, r.target_ev_ebitda,
    r.revenue_ttm, r.target_ev_revenue,
    r.total_debt, r.cash_and_equivalents,
    r.weight_dcf, r.weight_pe, r.weight_ev_ebitda, r.weight_ev_revenue,
    r.weight_epv, r.weight_earnings_yield
  );

  update public.snowball
  set
    intrinsic_dcf            = l.intrinsic_dcf,
    intrinsic_pe             = l.intrinsic_pe,
    intrinsic_ev_ebitda      = l.intrinsic_ev_ebitda,
    intrinsic_ev_revenue     = l.intrinsic_ev_revenue,
    intrinsic_epv            = l.intrinsic_epv,
    intrinsic_earnings_yield = l.intrinsic_earnings_yield,
    intrinsic_weighted       = l.intrinsic_weighted,
    intrinsic_value          = l.intrinsic_weighted,
    tbp_aggressive_15        = l.intrinsic_weighted * 0.85,
    tbp_conservative_30      = l.intrinsic_weighted * 0.70,
    tbp_deep_value_50        = l.intrinsic_weighted * 0.50
  where ticker = p_ticker;
end;
$$;
