-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — three-lens valuation: DCF + P/E + EV/EBITDA
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  add column if not exists eps_ttm                numeric,
  add column if not exists ebitda_ttm             numeric,
  add column if not exists total_debt             numeric,
  add column if not exists cash_and_equivalents   numeric,
  add column if not exists target_pe              numeric default 18,
  add column if not exists target_ev_ebitda       numeric default 12,
  add column if not exists intrinsic_dcf          numeric,
  add column if not exists intrinsic_pe           numeric,
  add column if not exists intrinsic_ev_ebitda    numeric,
  add column if not exists intrinsic_weighted     numeric,
  add column if not exists weight_dcf             numeric default 0.40,
  add column if not exists weight_pe              numeric default 0.30,
  add column if not exists weight_ev_ebitda       numeric default 0.30;

-- Recompute helper that returns the per-share intrinsic from each lens
-- AND the weighted average. Pure SQL, called from apply_defaults.
create or replace function public.snowball_compute_lenses(
  oe       numeric, shares numeric,
  g        numeric, d      numeric, tg numeric,
  eps      numeric, target_pe numeric,
  ebitda   numeric, target_ev_ebitda numeric, debt numeric, cash numeric,
  w_dcf    numeric, w_pe numeric, w_eve numeric
)
returns table(intrinsic_dcf numeric, intrinsic_pe numeric, intrinsic_ev_ebitda numeric, intrinsic_weighted numeric)
language sql immutable as $$
  with d_dcf as (
    select public.snowball_dcf_intrinsic(oe, shares, g, d, tg) as v
  ),
  d_pe as (
    select case
      when eps is null or target_pe is null then null
      else eps * target_pe
    end as v
  ),
  d_eve as (
    select case
      when ebitda is null or target_ev_ebitda is null
        or shares is null or shares <= 0 then null
      else (ebitda * target_ev_ebitda
            - coalesce(debt, 0) + coalesce(cash, 0)) / shares
    end as v
  )
  select
    d_dcf.v as intrinsic_dcf,
    d_pe.v  as intrinsic_pe,
    d_eve.v as intrinsic_ev_ebitda,
    -- Weighted average — only across non-null lenses, with weights renormalized.
    case
      when d_dcf.v is null and d_pe.v is null and d_eve.v is null then null
      else (
        coalesce(d_dcf.v * w_dcf, 0)
        + coalesce(d_pe.v  * w_pe,  0)
        + coalesce(d_eve.v * w_eve, 0)
      ) / (
        case when d_dcf.v is null then 0 else w_dcf end
        + case when d_pe.v  is null then 0 else w_pe  end
        + case when d_eve.v is null then 0 else w_eve end
      )
    end as intrinsic_weighted
  from d_dcf, d_pe, d_eve;
$$;

-- Replace apply_defaults to compute all three lenses + the weighted average,
-- and update the headline `intrinsic_value` column to the weighted figure.
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
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda
    ) l
  ),
  updated as (
    update public.snowball s
    set
      stage1_growth_pct   = p_growth,
      discount_rate_pct   = p_discount,
      terminal_growth_pct = p_terminal,
      intrinsic_dcf       = c.intrinsic_dcf,
      intrinsic_pe        = c.intrinsic_pe,
      intrinsic_ev_ebitda = c.intrinsic_ev_ebitda,
      intrinsic_weighted  = c.intrinsic_weighted,
      intrinsic_value     = c.intrinsic_weighted,
      tbp_aggressive_15   = c.intrinsic_weighted * 0.85,
      tbp_conservative_30 = c.intrinsic_weighted * 0.70,
      tbp_deep_value_50   = c.intrinsic_weighted * 0.50
    from computed c
    where s.ticker = c.ticker
    returning s.ticker
  )
  select count(*)::int from updated;
$$;
