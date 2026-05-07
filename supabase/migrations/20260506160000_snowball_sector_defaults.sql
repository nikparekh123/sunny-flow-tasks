-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — sector-based default multiples.
-- Each sector has typical P/E and EV/EBITDA bands (industry medians).
-- Per-stock overrides still live on the snowball row's target_pe /
-- target_ev_ebitda columns; this table just provides the defaults.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.snowball_sector_defaults (
  sector              text primary key,
  target_pe           numeric not null default 18,
  target_ev_ebitda    numeric not null default 12,
  default_growth_pct  numeric not null default 8,
  updated_at          timestamptz not null default now()
);

alter table public.snowball_sector_defaults enable row level security;

drop policy if exists "Members read sector defaults"   on public.snowball_sector_defaults;
drop policy if exists "Members write sector defaults"  on public.snowball_sector_defaults;

create policy "Members read sector defaults"
  on public.snowball_sector_defaults for select
  using (exists (
    select 1 from public.members m
    where lower(m.email) = lower((auth.jwt() ->> 'email')::text)
  ));
create policy "Members write sector defaults"
  on public.snowball_sector_defaults for all
  using (exists (
    select 1 from public.members m
    where lower(m.email) = lower((auth.jwt() ->> 'email')::text)
  ))
  with check (exists (
    select 1 from public.members m
    where lower(m.email) = lower((auth.jwt() ->> 'email')::text)
  ));

-- Seed with sensible industry-median multiples. Re-runnable.
insert into public.snowball_sector_defaults
  (sector, target_pe, target_ev_ebitda, default_growth_pct) values
  ('Technology',                25, 18, 12),
  ('Healthcare',                20, 14,  8),
  ('Financials',                12, 12,  7),
  ('Consumer Discretionary',    22, 14,  9),
  ('Consumer Cyclicals',        22, 14,  9),
  ('Consumer Non-Cyclicals',    22, 14,  5),
  ('Consumer Staples',          22, 14,  5),
  ('Energy',                    12,  6,  4),
  ('Industrials',               18, 11,  6),
  ('Materials',                 14,  9,  5),
  ('Basic Materials',           14,  9,  5),
  ('Utilities',                 18, 10,  4),
  ('Real Estate',               22, 18,  5),
  ('Communication Services',    20, 12,  7),
  ('Communications',            20, 12,  7),
  ('Telecommunications Services', 15, 10, 4)
on conflict (sector) do update set
  target_pe          = excluded.target_pe,
  target_ev_ebitda   = excluded.target_ev_ebitda,
  default_growth_pct = excluded.default_growth_pct,
  updated_at         = now();

-- Apply sector defaults to all snowball rows by sector match.
-- Overwrites target_pe / target_ev_ebitda on every stock with the
-- sector's defaults. Per-stock customization (via drawer sliders) is
-- expected to happen AFTER this — it'll overwrite sector defaults for
-- that single stock.
create or replace function public.snowball_apply_sector_multiples()
returns int
language sql security definer set search_path = public as $$
  with updated as (
    update public.snowball s
    set
      target_pe        = sd.target_pe,
      target_ev_ebitda = sd.target_ev_ebitda
    from public.snowball_sector_defaults sd
    where s.sector = sd.sector
    returning s.ticker
  )
  select count(*)::int from updated;
$$;

grant execute on function public.snowball_apply_sector_multiples() to authenticated, anon;
