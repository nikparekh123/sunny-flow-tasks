-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — add Earnings Power Value (EPV) as a 4th lens.
--
-- Greenwald's EPV = adjusted owner earnings × (1/cost of capital), then
-- subtract net debt to get equity. It's the "no-growth floor" — what the
-- business is worth if growth dies. Comparing EPV to DCF tells you how
-- much you're paying for growth (DCF >> EPV → expensive growth premium).
--
-- New default weights re-balance to make room for EPV:
--   DCF        35% (was 40%)
--   EPV        25% (NEW)
--   EV/EBITDA  25% (was 30%)
--   P/E        15% (was 30%)
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  add column if not exists intrinsic_epv numeric,
  add column if not exists weight_epv    numeric default 0.25;

-- Re-balance existing weights for rows that were on the old defaults.
update public.snowball
set
  weight_dcf       = 0.35,
  weight_pe        = 0.15,
  weight_ev_ebitda = 0.25,
  weight_epv       = 0.25
where
  weight_dcf = 0.40 or weight_dcf is null;

-- EPV computation in SQL — simple perpetuity at zero growth.
create or replace function public.snowball_epv(
  oe      numeric,  -- owner earnings, millions
  d       numeric,  -- discount rate, DECIMAL
  debt    numeric,  -- in millions
  cash    numeric,  -- in millions
  shares  numeric   -- in millions
)
returns numeric
language sql immutable as $$
  select case
    when oe is null                         then null
    when coalesce(shares, 0) <= 0           then null
    when coalesce(d, 0) <= 0                then null
    -- EV (perpetuity) = OE / d. Equity = EV − debt + cash.
    -- All in millions; shares in millions; result in dollars per share.
    else (oe / d - coalesce(debt, 0) + coalesce(cash, 0)) / shares
  end;
$$;

-- Replace compute_lenses to include EPV (4-lens version).
create or replace function public.snowball_compute_lenses(
  oe       numeric, shares numeric,
  g        numeric, d      numeric, tg numeric,
  eps      numeric, target_pe numeric,
  ebitda   numeric, target_ev_ebitda numeric, debt numeric, cash numeric,
  w_dcf    numeric, w_pe numeric, w_eve numeric, w_epv numeric
)
returns table(
  intrinsic_dcf       numeric,
  intrinsic_pe        numeric,
  intrinsic_ev_ebitda numeric,
  intrinsic_epv       numeric,
  intrinsic_weighted  numeric
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
  d_epv as ( select public.snowball_epv(oe, d, debt, cash, shares) as v )
  select
    d_dcf.v as intrinsic_dcf,
    d_pe.v  as intrinsic_pe,
    d_eve.v as intrinsic_ev_ebitda,
    d_epv.v as intrinsic_epv,
    -- Weighted average across non-null lenses, weights renormalized.
    case
      when d_dcf.v is null and d_pe.v is null
       and d_eve.v is null and d_epv.v is null then null
      else (
        coalesce(d_dcf.v * w_dcf, 0)
        + coalesce(d_pe.v  * w_pe,  0)
        + coalesce(d_eve.v * w_eve, 0)
        + coalesce(d_epv.v * w_epv, 0)
      ) / nullif((
        case when d_dcf.v is null then 0 else w_dcf end
        + case when d_pe.v  is null then 0 else w_pe  end
        + case when d_eve.v is null then 0 else w_eve end
        + case when d_epv.v is null then 0 else w_epv end
      ), 0)
    end as intrinsic_weighted
  from d_dcf, d_pe, d_eve, d_epv;
$$;

-- Update apply_defaults to feed the 4-lens computation.
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
      s.weight_dcf, s.weight_pe, s.weight_ev_ebitda, s.weight_epv
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
      intrinsic_epv       = c.intrinsic_epv,
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
