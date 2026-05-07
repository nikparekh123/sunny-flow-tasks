-- ─────────────────────────────────────────────────────────────────────────
-- snowball_recompute_one — recompute all 5 lenses + weighted intrinsic
-- for a single ticker, using its currently-stored inputs and assumptions.
-- Called from the drawer Save flow so all lens columns stay in sync with
-- the freshly-updated assumption values (instead of the JS only writing
-- intrinsic_value from the DCF lens).
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.snowball_recompute_one(p_ticker text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  l record;
begin
  select * into r from public.snowball where ticker = p_ticker;
  if not found then return; end if;

  select * into l from public.snowball_compute_lenses(
    r.total_owner_earnings,
    r.shares_outstanding,
    coalesce(r.stage1_growth_pct, 8) / 100,
    coalesce(
      r.stage2_growth_pct,
      (coalesce(r.stage1_growth_pct, 8) + coalesce(r.terminal_growth_pct, 2)) / 2
    ) / 100,
    coalesce(r.discount_rate_pct, 10) / 100,
    coalesce(r.terminal_growth_pct, 2) / 100,
    r.eps_ttm, r.target_pe,
    r.ebitda_ttm, r.target_ev_ebitda, r.total_debt, r.cash_and_equivalents,
    r.weight_dcf, r.weight_pe, r.weight_ev_ebitda, r.weight_epv, r.weight_earnings_yield
  );

  update public.snowball
  set
    intrinsic_dcf            = l.intrinsic_dcf,
    intrinsic_pe             = l.intrinsic_pe,
    intrinsic_ev_ebitda      = l.intrinsic_ev_ebitda,
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

grant execute on function public.snowball_recompute_one(text) to authenticated, anon;
