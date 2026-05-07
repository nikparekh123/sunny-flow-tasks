-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — track manual per-stock customization + store historical
-- 5-yr CAGR from Polygon annual filings.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  add column if not exists is_customized        boolean not null default false,
  add column if not exists historical_growth_pct numeric;  -- 5-yr CAGR of net income, %

-- apply_defaults overwrites every stock with universe assumptions, so
-- it should also reset the customized flag.
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
      is_high_quality          = coalesce(c.roe_pct >= 15, false),
      is_customized            = false  -- universe overwrite resets the flag
    from with_quality c
    where s.ticker = c.ticker
    returning s.ticker
  )
  select count(*)::int from updated;
$$;

-- Sector multiples apply also clears is_customized (it overwrites
-- target_pe / target_ev_ebitda for everyone).
create or replace function public.snowball_apply_sector_multiples()
returns int
language sql security definer set search_path = public as $$
  with updated as (
    update public.snowball s
    set
      target_pe        = sd.target_pe,
      target_ev_ebitda = sd.target_ev_ebitda,
      is_customized    = false
    from public.snowball_sector_defaults sd
    where s.sector = sd.sector
    returning s.ticker
  )
  select count(*)::int from updated;
$$;
