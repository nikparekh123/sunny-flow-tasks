-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — DCF / valuation universe.
--
-- Two layers in one table:
--   • Static analysis (intrinsic, growth, discount rate, TBPs, tier) —
--     populated by CSV import; only changes when the analyst re-uploads.
--   • Live quote (price, low_52w, high_52w, change_pct, last_quote_at) —
--     populated daily by the refresh-snowball edge function from Polygon.
--
-- Members-only via existing is_member() RPC.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.snowball (
  ticker                   text primary key,
  name                     text not null,
  sector                   text,
  industry                 text,

  -- ── DCF inputs (from CSV) ──────────────────────────────────────────────
  shares_outstanding       numeric,
  intrinsic_value          numeric,
  stage1_growth_pct        numeric,
  discount_rate_pct        numeric,
  terminal_growth_pct      numeric,
  total_owner_earnings     numeric,

  -- ── Target Buy Prices at margins of safety ────────────────────────────
  tbp_aggressive_15        numeric,
  tbp_conservative_30      numeric,
  tbp_deep_value_50        numeric,
  distance_to_buy          text,

  -- ── Tier / valuation profile (1=strong buy, 6=overvalued) ─────────────
  valuation_profile        text,
  tier                     int check (tier between 1 and 6),

  -- ── Personal flags ────────────────────────────────────────────────────
  hold_position            boolean default false,
  watchlist                boolean default false,

  -- ── Misc CSV cols ─────────────────────────────────────────────────────
  dividend_yield_pct       numeric,
  earnings_date            text,

  -- ── Live quote (refreshed daily by edge function) ─────────────────────
  price                    numeric,
  low_52w                  numeric,
  high_52w                 numeric,
  change_pct               numeric,
  last_quote_at            timestamptz,

  -- ── Bookkeeping ───────────────────────────────────────────────────────
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index if not exists idx_snowball_sector on public.snowball(sector);
create index if not exists idx_snowball_tier   on public.snowball(tier);
create index if not exists idx_snowball_watch  on public.snowball(watchlist) where watchlist;

-- RLS: members-only, inline EXISTS for fast evaluation (same pattern that
-- fixed the slow `is_member()` policies on `reports`).
alter table public.snowball enable row level security;

drop policy if exists "Members can read snowball"   on public.snowball;
drop policy if exists "Members can insert snowball" on public.snowball;
drop policy if exists "Members can update snowball" on public.snowball;
drop policy if exists "Members can delete snowball" on public.snowball;

create policy "Members can read snowball"
  on public.snowball for select
  using (
    exists (select 1 from public.members m
            where lower(m.email) = lower((auth.jwt() ->> 'email')::text))
  );
create policy "Members can insert snowball"
  on public.snowball for insert
  with check (
    exists (select 1 from public.members m
            where lower(m.email) = lower((auth.jwt() ->> 'email')::text))
  );
create policy "Members can update snowball"
  on public.snowball for update
  using (
    exists (select 1 from public.members m
            where lower(m.email) = lower((auth.jwt() ->> 'email')::text))
  )
  with check (
    exists (select 1 from public.members m
            where lower(m.email) = lower((auth.jwt() ->> 'email')::text))
  );
create policy "Members can delete snowball"
  on public.snowball for delete
  using (
    exists (select 1 from public.members m
            where lower(m.email) = lower((auth.jwt() ->> 'email')::text))
  );

-- updated_at trigger
create or replace function public.snowball_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists snowball_set_updated on public.snowball;
create trigger snowball_set_updated
before update on public.snowball
for each row execute function public.snowball_touch_updated_at();
