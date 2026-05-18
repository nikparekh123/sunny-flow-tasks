-- Strategy schema: renames positions price columns to match the
-- Positions ↔ Strategy contract, adds a name column, and creates the
-- three new tables that the /strategy route reads/writes.
--
-- All tables are org-wide (any authenticated user reads + writes the
-- same rows), matching the existing positions table tenancy.

-- ── 1) positions: rename + add name ─────────────────────────────────
alter table public.positions rename column last_price   to current_price;
alter table public.positions rename column last_updated to last_price_update;
alter table public.positions add column if not exists name text;

-- ── 2) strategy_overlay ─────────────────────────────────────────────
-- One row per ticker that has been assigned a bucket. Tickers in
-- positions without an overlay row appear in the Unassigned strip.
-- Note: ticker is plain text, NOT a foreign key. When a position is sold
-- and the row leaves `positions`, the overlay deliberately survives so the
-- ticker shows up in the "Closed" section with its journal history intact.
-- The app derives "closed = overlay rows whose ticker no longer exists in
-- positions" at read time.
create table if not exists public.strategy_overlay (
  id            uuid primary key default gen_random_uuid(),
  ticker        text not null unique,
  bucket        text not null check (bucket in ('income','invest','yield')),
  put_cost      numeric(18, 2) not null default 0 check (put_cost >= 0),
  put_frequency text not null default 'quarterly'
                  check (put_frequency in
                    ('weekly','biweekly','monthly','quarterly','yearly')),
  days_held     integer not null default 0 check (days_held >= 0),
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists strategy_overlay_bucket_idx
  on public.strategy_overlay (bucket);

drop trigger if exists strategy_overlay_updated_at on public.strategy_overlay;
create trigger strategy_overlay_updated_at
  before update on public.strategy_overlay
  for each row execute function public.positions_set_updated_at();

-- ── 3) gain_entries (weekly journal — options premium + realized) ──
-- Anchored by week_start_date (Monday) so entries don't rotate over
-- time. UI converts to "this wk / −1 / −2" at render time.
-- Note: ticker is plain text, NOT a foreign key. Journal entries are
-- valuable history that must survive the position being sold/deleted.
create table if not exists public.gain_entries (
  id              uuid primary key default gen_random_uuid(),
  ticker          text not null,
  week_start_date date not null,
  options         numeric(18, 2) not null default 0,
  stock           numeric(18, 2) not null default 0,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (ticker, week_start_date),
  check (extract(dow from week_start_date) = 1)  -- Monday
);

create index if not exists gain_entries_ticker_idx
  on public.gain_entries (ticker);
create index if not exists gain_entries_week_idx
  on public.gain_entries (week_start_date);

drop trigger if exists gain_entries_updated_at on public.gain_entries;
create trigger gain_entries_updated_at
  before update on public.gain_entries
  for each row execute function public.positions_set_updated_at();

-- ── 4) watching (tickers tracked but not bought) ────────────────────
create table if not exists public.watching (
  id            uuid primary key default gen_random_uuid(),
  ticker        text not null unique,
  name          text,
  sector        public.sector_kind not null default 'Other',
  current_price numeric(20, 6),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

drop trigger if exists watching_updated_at on public.watching;
create trigger watching_updated_at
  before update on public.watching
  for each row execute function public.positions_set_updated_at();

-- ── 5) RLS ──────────────────────────────────────────────────────────
alter table public.strategy_overlay enable row level security;
alter table public.gain_entries     enable row level security;
alter table public.watching         enable row level security;

do $$
declare
  tbl text;
begin
  foreach tbl in array array['strategy_overlay', 'gain_entries', 'watching'] loop
    execute format('drop policy if exists "%1$s: authenticated read"   on public.%1$I', tbl);
    execute format('drop policy if exists "%1$s: authenticated insert" on public.%1$I', tbl);
    execute format('drop policy if exists "%1$s: authenticated update" on public.%1$I', tbl);
    execute format('drop policy if exists "%1$s: authenticated delete" on public.%1$I', tbl);

    execute format(
      'create policy "%1$s: authenticated read" on public.%1$I '
      'for select to authenticated using (true)', tbl);
    execute format(
      'create policy "%1$s: authenticated insert" on public.%1$I '
      'for insert to authenticated with check (true)', tbl);
    execute format(
      'create policy "%1$s: authenticated update" on public.%1$I '
      'for update to authenticated using (true)', tbl);
    execute format(
      'create policy "%1$s: authenticated delete" on public.%1$I '
      'for delete to authenticated using (true)', tbl);
  end loop;
end $$;

-- ── 6) Realtime ─────────────────────────────────────────────────────
alter publication supabase_realtime add table public.strategy_overlay;
alter publication supabase_realtime add table public.gain_entries;
alter publication supabase_realtime add table public.watching;
