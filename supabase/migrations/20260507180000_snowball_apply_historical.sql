-- ─────────────────────────────────────────────────────────────────────────
-- snowball_apply_historical_growth — for every non-customized stock,
-- set Stage 1 = historical_growth_pct and Stage 2 = fade halfway toward
-- terminal. Then recompute all lenses.
--
-- Skips rows where is_customized = true (preserves your manual tuning).
-- Skips rows with no historical_growth_pct (missing data).
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.snowball_apply_historical_growth()
returns int
language sql security definer set search_path = public as $$
  with eligible as (
    select * from public.snowball
    where is_customized = false
      and historical_growth_pct is not null
  ),
  computed as (
    select e.ticker, l.*,
      e.historical_growth_pct as new_g1,
      greatest(2.0,
        (e.historical_growth_pct + coalesce(e.terminal_growth_pct, 2)) / 2
      ) as new_g2
    from eligible e
    cross join lateral public.snowball_compute_lenses(
      e.total_owner_earnings, e.shares_outstanding,
      e.historical_growth_pct / 100,
      greatest(2.0,
        (e.historical_growth_pct + coalesce(e.terminal_growth_pct, 2)) / 2
      ) / 100,
      coalesce(e.discount_rate_pct, 10) / 100,
      coalesce(e.terminal_growth_pct, 2) / 100,
      e.eps_ttm, e.target_pe,
      e.ebitda_ttm, e.target_ev_ebitda, e.total_debt, e.cash_and_equivalents,
      e.weight_dcf, e.weight_pe, e.weight_ev_ebitda, e.weight_epv, e.weight_earnings_yield
    ) l
  ),
  updated as (
    update public.snowball s
    set
      stage1_growth_pct        = c.new_g1,
      stage2_growth_pct        = c.new_g2,
      intrinsic_dcf            = c.intrinsic_dcf,
      intrinsic_pe             = c.intrinsic_pe,
      intrinsic_ev_ebitda      = c.intrinsic_ev_ebitda,
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
  select count(*)::int from updated;
$$;

grant execute on function public.snowball_apply_historical_growth() to authenticated, anon;
