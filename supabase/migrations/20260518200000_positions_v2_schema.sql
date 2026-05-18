-- Positions v2 schema:
--   1. positions.status (open | closed) so closed positions remain in DB
--      for gain history without polluting active P&L.
--   2. gain_entries gets a per-entry shape (date, source, amount) instead of
--      the legacy weekly-aggregate (options, stock). Three sources: stock,
--      call, put. The amount is signed so realized losses are first-class.
--   3. New put_protection table: one row per ticker, capturing total
--      premium paid + expiry. Cost/day and burn are derived on read.
--
-- The legacy gain_entries data is wiped per user instruction — no
-- meaningful production rows yet, simpler than a column-level migration.

-- ── 1) positions.status ─────────────────────────────────────────────
alter table public.positions
  add column if not exists status text not null default 'open'
    check (status in ('open', 'closed'));

create index if not exists positions_status_idx on public.positions (status);

-- ── 2) gain_entries — wipe + recreate ──────────────────────────────
-- Drop the old table (loses options/stock weekly aggregate; safe per user).
drop table if exists public.gain_entries cascade;

create table public.gain_entries (
  id          uuid primary key default gen_random_uuid(),
  ticker      text not null,
  gain_date   date not null,
  source      text not null check (source in ('stock', 'call', 'put')),
  amount      numeric(18, 2) not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index gain_entries_ticker_idx     on public.gain_entries (ticker);
create index gain_entries_date_idx       on public.gain_entries (gain_date);
create index gain_entries_source_idx     on public.gain_entries (source);

drop trigger if exists gain_entries_updated_at on public.gain_entries;
create trigger gain_entries_updated_at
  before update on public.gain_entries
  for each row execute function public.positions_set_updated_at();

-- ── 3) put_protection ──────────────────────────────────────────────
-- One row per ticker. Null row = no protection. cost_per_day, days_to_expiry,
-- and cost_remaining are computed in the app from these three fields.
create table if not exists public.put_protection (
  id             uuid primary key default gen_random_uuid(),
  ticker         text not null unique,
  total_cost     numeric(18, 2) not null check (total_cost >= 0),
  expiry         date not null,
  purchase_date  date not null default current_date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (expiry >= purchase_date)
);

create index if not exists put_protection_ticker_idx
  on public.put_protection (ticker);
create index if not exists put_protection_expiry_idx
  on public.put_protection (expiry);

drop trigger if exists put_protection_updated_at on public.put_protection;
create trigger put_protection_updated_at
  before update on public.put_protection
  for each row execute function public.positions_set_updated_at();

-- ── 4) Drop legacy put_cost from strategy_overlay ──────────────────
-- put_cost now lives on put_protection.total_cost; keep put_frequency
-- on the overlay since it's a strategy-level pacing concept (not a single
-- contract).
alter table public.strategy_overlay drop column if exists put_cost;

-- ── 5) RLS for the new + recreated tables ──────────────────────────
alter table public.gain_entries   enable row level security;
alter table public.put_protection enable row level security;

do $$
declare
  tbl text;
begin
  foreach tbl in array array['gain_entries', 'put_protection'] loop
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

-- ── 6) Realtime ────────────────────────────────────────────────────
-- gain_entries was already in the publication; cascade-dropping the table
-- removed it. Re-add. put_protection is brand new.
do $$
begin
  begin
    alter publication supabase_realtime add table public.gain_entries;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.put_protection;
  exception when duplicate_object then null;
  end;
end $$;
