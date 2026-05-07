-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — sector defaults should NOT clobber per-stock historical
-- growth. Each lens input has the right source:
--
--   Stage 1 growth   ← historical_growth_pct (per-stock) OR sector default
--   Stage 2 growth   ← sector default
--   Discount (WACC)  ← sector default
--   Target P/E       ← sector default
--   Target EV/EBITDA ← sector default
--   Terminal         ← stays whatever it was (not in sector_defaults)
--
-- Per-stock customization (is_customized = true) still wins everything.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.snowball_apply_sector_defaults()
returns int
language sql security definer set search_path = public as $$
  with applied as (
    update public.snowball s
    set
      target_pe         = sd.target_pe,
      target_ev_ebitda  = sd.target_ev_ebitda,
      -- Stage 1 prefers per-stock historical CAGR; sector default fallback
      stage1_growth_pct = coalesce(s.historical_growth_pct, sd.default_growth_pct),
      stage2_growth_pct = sd.default_stage2_growth_pct,
      discount_rate_pct = sd.default_discount_rate_pct,
      is_customized     = false
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
      s.ebitda_ttm, s.target_ev_ebitda, s.total_debt, s.cash_and_equivalents,
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda, s.weight_epv, s.weight_earnings_yield
    ) l
  ),
  recomputed as (
    update public.snowball s
    set
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
  select count(*)::int from recomputed;
$$;
