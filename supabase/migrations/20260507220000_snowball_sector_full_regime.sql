-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — sector defaults now cover the full valuation regime, not
-- just multiples. Each sector encodes its typical:
--   • Stage 1 growth (g1)
--   • Stage 2 growth (g2)
--   • Discount rate (WACC)
--   • Target P/E
--   • Target EV/EBITDA
--
-- Universe-wide ⚙ Defaults still works as a "reset everyone to one set
-- of assumptions" override. Sector defaults are the per-industry baseline.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball_sector_defaults
  add column if not exists default_discount_rate_pct numeric default 10;

-- Updated seed values — sensible regime per sector. Re-runnable.
insert into public.snowball_sector_defaults
  (sector, target_pe, target_ev_ebitda, default_growth_pct,
   default_stage2_growth_pct, default_discount_rate_pct) values
  ('Technology',                25, 18, 12,  7, 10),
  ('Healthcare',                20, 14,  8,  5,  9),
  ('Financials',                12, 12,  7,  4, 10),
  ('Consumer Discretionary',    22, 14,  9,  5, 10),
  ('Consumer Cyclicals',        22, 14,  9,  5, 10),
  ('Consumer Non-Cyclicals',    25, 18,  5,  3,  8),
  ('Consumer Staples',          25, 18,  5,  3,  8),
  ('Energy',                    12,  6,  4,  3, 11),
  ('Industrials',               18, 11,  6,  4,  9),
  ('Materials',                 14,  9,  5,  3, 10),
  ('Basic Materials',           14,  9,  5,  3, 10),
  ('Utilities',                 18, 10,  4,  3,  7),
  ('Real Estate',               22, 18,  5,  3,  8),
  ('Communication Services',    20, 12,  7,  5,  9),
  ('Communications',            20, 12,  7,  5,  9),
  ('Telecommunications Services', 15, 10, 4, 3,  8)
on conflict (sector) do update set
  target_pe                 = excluded.target_pe,
  target_ev_ebitda          = excluded.target_ev_ebitda,
  default_growth_pct        = excluded.default_growth_pct,
  default_stage2_growth_pct = excluded.default_stage2_growth_pct,
  default_discount_rate_pct = excluded.default_discount_rate_pct,
  updated_at                = now();

-- New RPC: apply ALL sector knobs to every stock by sector match, then
-- recompute lenses. Replaces the old "multiples-only" version.
-- Resets is_customized = false (deliberate sector-wide overwrite).
create or replace function public.snowball_apply_sector_defaults()
returns int
language sql security definer set search_path = public as $$
  with applied as (
    update public.snowball s
    set
      target_pe           = sd.target_pe,
      target_ev_ebitda    = sd.target_ev_ebitda,
      stage1_growth_pct   = sd.default_growth_pct,
      stage2_growth_pct   = sd.default_stage2_growth_pct,
      discount_rate_pct   = sd.default_discount_rate_pct,
      is_customized       = false
    from public.snowball_sector_defaults sd
    where s.sector = sd.sector
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

grant execute on function public.snowball_apply_sector_defaults() to authenticated, anon;
