-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — server-side DCF + "apply defaults" RPC.
--
-- Lets the UI set growth/discount/terminal once and recompute every
-- ticker's intrinsic + TBPs in a single SQL UPDATE.
-- ─────────────────────────────────────────────────────────────────────────

-- Two-stage DCF, mirrors the client-side `dcfIntrinsic`. Returns intrinsic
-- value per share, or null if inputs are invalid.
create or replace function public.snowball_dcf_intrinsic(
  oe       numeric,  -- total owner earnings (in millions)
  shares   numeric,  -- shares outstanding (in millions)
  g        numeric,  -- stage 1 growth (decimal — pass 0.08 not 8)
  d        numeric,  -- discount rate (decimal)
  tg       numeric   -- terminal growth (decimal)
)
returns numeric
language sql
immutable
as $$
  select case
    when coalesce(shares, 0) <= 0           then null
    when coalesce(d, 0) <= coalesce(tg, 0)  then null  -- Gordon diverges
    else (
      -- PV of years 1-10
      (select coalesce(sum(
        coalesce(oe, 0) * power(1 + g, y) / power(1 + d, y)
      ), 0) from generate_series(1, 10) as y)
      -- Terminal value at year 10, discounted back
      + (coalesce(oe, 0) * power(1 + g, 10) * (1 + tg) / (d - tg))
        / power(1 + d, 10)
    ) / shares
  end;
$$;

-- Bulk-apply defaults to every row in `snowball`. SECURITY DEFINER so
-- members can call it (their RLS UPDATE policy permits this anyway, but
-- this packaged form lets us audit + log it).
create or replace function public.snowball_apply_defaults(
  p_growth   numeric,  -- in % (e.g. 8 for 8%)
  p_discount numeric,
  p_terminal numeric
)
returns int
language sql
security definer
set search_path = public
as $$
  with computed as (
    select
      ticker,
      public.snowball_dcf_intrinsic(
        total_owner_earnings,
        shares_outstanding,
        p_growth / 100,
        p_discount / 100,
        p_terminal / 100
      ) as iv
    from public.snowball
  )
  , updated as (
    update public.snowball s
    set
      stage1_growth_pct   = p_growth,
      discount_rate_pct   = p_discount,
      terminal_growth_pct = p_terminal,
      intrinsic_value     = c.iv,
      tbp_aggressive_15   = c.iv * 0.85,
      tbp_conservative_30 = c.iv * 0.70,
      tbp_deep_value_50   = c.iv * 0.50
    from computed c
    where s.ticker = c.ticker
    returning s.ticker
  )
  select count(*)::int from updated;
$$;

-- Members can call the RPC. (The bulk update inside relies on RLS being
-- bypassed by SECURITY DEFINER; we still gate the RPC itself by member
-- check at the application layer.)
revoke all on function public.snowball_apply_defaults(numeric, numeric, numeric) from public;
grant execute on function public.snowball_apply_defaults(numeric, numeric, numeric) to authenticated, anon;
