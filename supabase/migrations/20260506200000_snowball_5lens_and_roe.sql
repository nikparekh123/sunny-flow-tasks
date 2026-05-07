-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — add 5th lens (Earnings Yield vs WACC) + ROE quality flag.
--
-- New 5-lens weighting: 30 / 25 / 20 / 15 / 10
--   DCF Growth Exit    30%  forward-looking
--   EPV                25%  downside / no-growth floor
--   EV/EBITDA          20%  peer benchmark
--   P/E                15%  mature-business sanity
--   Earnings Yield     10%  cost-of-capital test (EPS/WACC)
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  add column if not exists intrinsic_earnings_yield numeric,
  add column if not exists weight_earnings_yield    numeric default 0.10,
  add column if not exists equity_book              numeric,         -- balance-sheet equity (millions)
  add column if not exists net_income_ttm           numeric,         -- net income TTM (millions)
  add column if not exists roe                      numeric,         -- net_income / equity, %
  add column if not exists is_high_quality          boolean default false;

-- Re-balance existing weights to the 5-lens split. Anyone still on the
-- 4-lens default (35/25/25/15) gets bumped over.
update public.snowball
set
  weight_dcf            = 0.30,
  weight_epv            = 0.25,
  weight_ev_ebitda      = 0.20,
  weight_pe             = 0.15,
  weight_earnings_yield = 0.10
where
  weight_dcf = 0.35
  or weight_dcf is null;

-- Earnings Yield lens — equity-only "no growth, no debt adjustment" check.
-- Intrinsic = EPS / WACC. If EPS / price > WACC → stock yields more than
-- its cost of capital → cheap by this lens.
create or replace function public.snowball_earnings_yield(
  eps numeric,
  d   numeric  -- discount rate, DECIMAL
)
returns numeric
language sql immutable as $$
  select case
    when eps is null              then null
    when coalesce(d, 0) <= 0      then null
    else eps / d
  end;
$$;

-- 5-lens compute_lenses.
create or replace function public.snowball_compute_lenses(
  oe       numeric, shares numeric,
  g        numeric, d      numeric, tg numeric,
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
  with d_dcf as ( select public.snowball_dcf_intrinsic(oe, shares, g, d, tg) as v ),
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

-- Update apply_defaults to use 5-lens.
create or replace function public.snowball_apply_defaults(
  p_growth   numeric,
  p_discount numeric,
  p_terminal numeric
)
returns int
language sql security definer set search_path = public as $$
  with computed as (
    select s.ticker, l.*
    from public.snowball s
    cross join lateral public.snowball_compute_lenses(
      s.total_owner_earnings, s.shares_outstanding,
      p_growth/100, p_discount/100, p_terminal/100,
      s.eps_ttm, s.target_pe,
      s.ebitda_ttm, s.target_ev_ebitda, s.total_debt, s.cash_and_equivalents,
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda, s.weight_epv, s.weight_earnings_yield
    ) l
  ),
  -- Compute ROE = net_income / equity_book (×100 to get %).
  -- Set is_high_quality = ROE ≥ 15%.
  with_quality as (
    select
      c.*,
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
