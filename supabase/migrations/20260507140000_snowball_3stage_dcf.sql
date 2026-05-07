-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — 3-stage DCF.
--   Years 1-5:  Stage 1 growth (high, current trajectory)
--   Years 6-10: Stage 2 growth (fade toward terminal)
--   Year 11+:   Terminal growth (Gordon perpetuity)
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  add column if not exists stage2_growth_pct numeric;

alter table public.snowball_sector_defaults
  add column if not exists default_stage2_growth_pct numeric;

-- Seed sector Stage 2 defaults — typically half the Stage 1 rate (linear
-- fade halfway toward terminal). Re-runnable.
update public.snowball_sector_defaults
set default_stage2_growth_pct = greatest(2.0, default_growth_pct * 0.5);

-- For existing snowball rows that don't have stage2, set it to half of
-- their stage1 (matches the seed pattern). Per-stock customization in the
-- drawer overrides this.
update public.snowball
set stage2_growth_pct = greatest(2.0, coalesce(stage1_growth_pct, 8) * 0.5)
where stage2_growth_pct is null;

-- New 3-stage DCF function. The 2-stage version stays as
-- snowball_dcf_intrinsic for backwards compat / unit tests; the 3-stage
-- version below is what apply_defaults now uses.
create or replace function public.snowball_dcf_intrinsic_3stage(
  oe       numeric,  -- owner earnings, millions
  shares   numeric,  -- millions
  g1       numeric,  -- stage 1 growth (DECIMAL, e.g. 0.12)
  g2       numeric,  -- stage 2 growth (DECIMAL)
  d        numeric,  -- discount rate (DECIMAL)
  tg       numeric   -- terminal growth (DECIMAL)
)
returns numeric
language sql immutable as $$
  select case
    when oe is null                         then null
    when coalesce(shares, 0) <= 0           then null
    when coalesce(d, 0) <= coalesce(tg, 0)  then null
    else (
      -- Stage 1: years 1-5 at g1, discounted
      (select coalesce(sum(
        oe * power(1 + g1, y) / power(1 + d, y)
      ), 0) from generate_series(1, 5) as y)
      -- Stage 2: years 6-10 at g2 (compounds on top of year-5 FCF)
      + (select coalesce(sum(
        oe * power(1 + g1, 5) * power(1 + g2, y - 5) / power(1 + d, y)
      ), 0) from generate_series(6, 10) as y)
      -- Terminal at end of year 10
      + (oe * power(1 + g1, 5) * power(1 + g2, 5) * (1 + tg) / (d - tg))
        / power(1 + d, 10)
    ) / shares
  end;
$$;

-- Updated compute_lenses with Stage 2 support.
create or replace function public.snowball_compute_lenses(
  oe       numeric, shares numeric,
  g1       numeric, g2 numeric, d numeric, tg numeric,
  eps      numeric, target_pe numeric,
  ebitda   numeric, target_ev_ebitda numeric, debt numeric, cash numeric,
  w_dcf    numeric, w_pe numeric, w_eve numeric, w_epv numeric, w_ey numeric
)
returns table(
  intrinsic_dcf            numeric,
  intrinsic_pe             numeric,
  intrinsic_ev_ebitda      numeric,
  intrinsic_epv            numeric,
  intrinsic_earnings_yield numeric,
  intrinsic_weighted       numeric
)
language sql immutable as $$
  with d_dcf as (
    select public.snowball_dcf_intrinsic_3stage(oe, shares, g1, g2, d, tg) as v
  ),
  d_pe  as ( select case when eps is null or target_pe is null then null
                         else eps * target_pe end as v ),
  d_eve as ( select case
                      when ebitda is null or target_ev_ebitda is null
                        or shares is null or shares <= 0 then null
                      else (ebitda * target_ev_ebitda
                            - coalesce(debt, 0) + coalesce(cash, 0)) / shares
                    end as v ),
  d_epv as ( select public.snowball_epv(oe, d, debt, cash, shares) as v ),
  d_ey  as ( select public.snowball_earnings_yield(eps, d) as v )
  select
    d_dcf.v as intrinsic_dcf,
    d_pe.v  as intrinsic_pe,
    d_eve.v as intrinsic_ev_ebitda,
    d_epv.v as intrinsic_epv,
    d_ey.v  as intrinsic_earnings_yield,
    case
      when d_dcf.v is null and d_pe.v is null and d_eve.v is null
       and d_epv.v is null and d_ey.v is null then null
      else (
        coalesce(d_dcf.v * w_dcf, 0)
        + coalesce(d_pe.v  * w_pe,  0)
        + coalesce(d_eve.v * w_eve, 0)
        + coalesce(d_epv.v * w_epv, 0)
        + coalesce(d_ey.v  * w_ey,  0)
      ) / nullif((
        case when d_dcf.v is null then 0 else w_dcf end
        + case when d_pe.v  is null then 0 else w_pe  end
        + case when d_eve.v is null then 0 else w_eve end
        + case when d_epv.v is null then 0 else w_epv end
        + case when d_ey.v  is null then 0 else w_ey  end
      ), 0)
    end as intrinsic_weighted
  from d_dcf, d_pe, d_eve, d_epv, d_ey;
$$;

-- apply_defaults now takes stage 2 and passes it through.
create or replace function public.snowball_apply_defaults(
  p_growth   numeric,    -- stage 1 universe default
  p_discount numeric,
  p_terminal numeric,
  p_growth2  numeric default null  -- stage 2; if null, defaults to (stage1+terminal)/2
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
      s.ebitda_ttm, s.target_ev_ebitda, s.total_debt, s.cash_and_equivalents,
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda, s.weight_epv, s.weight_earnings_yield
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
      intrinsic_epv            = c.intrinsic_epv,
      intrinsic_earnings_yield = c.intrinsic_earnings_yield,
      intrinsic_weighted       = c.intrinsic_weighted,
      intrinsic_value          = c.intrinsic_weighted,
      tbp_aggressive_15        = c.intrinsic_weighted * 0.85,
      tbp_conservative_30      = c.intrinsic_weighted * 0.70,
      tbp_deep_value_50        = c.intrinsic_weighted * 0.50,
      roe                      = c.roe_pct,
      is_high_quality          = coalesce(c.roe_pct >= 15, false)
    from with_quality c
    where s.ticker = c.ticker
    returning s.ticker
  )
  select count(*)::int from updated;
$$;
