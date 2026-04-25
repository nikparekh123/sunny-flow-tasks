-- Positions schema for the company portfolio. Org-wide shared (every
-- authenticated user reads + writes the same rows). CSV upload replaces all
-- rows; refresh-prices function updates last_price / prev_close.

do $$ begin
  create type public.sector_kind as enum (
    'Technology',
    'Healthcare',
    'Financials',
    'Consumer Discretionary',
    'Consumer Staples',
    'Energy',
    'Industrials',
    'Materials',
    'Utilities',
    'Real Estate',
    'Communication Services',
    'Other'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.positions (
  id           uuid primary key default gen_random_uuid(),
  ticker       text not null,
  sector       public.sector_kind not null default 'Other',
  quantity     numeric(20, 6) not null check (quantity >= 0),
  avg_cost     numeric(20, 6) not null check (avg_cost >= 0),
  last_price   numeric(20, 6),
  prev_close   numeric(20, 6),
  last_updated timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (ticker)
);

create index if not exists positions_ticker_idx on public.positions (ticker);

create or replace function public.positions_set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists positions_updated_at on public.positions;
create trigger positions_updated_at
  before update on public.positions
  for each row execute function public.positions_set_updated_at();

alter table public.positions enable row level security;

drop policy if exists "positions: authenticated read"   on public.positions;
drop policy if exists "positions: authenticated insert" on public.positions;
drop policy if exists "positions: authenticated update" on public.positions;
drop policy if exists "positions: authenticated delete" on public.positions;

create policy "positions: authenticated read"   on public.positions
  for select to authenticated using (true);
create policy "positions: authenticated insert" on public.positions
  for insert to authenticated with check (true);
create policy "positions: authenticated update" on public.positions
  for update to authenticated using (true);
create policy "positions: authenticated delete" on public.positions
  for delete to authenticated using (true);

-- Realtime so the UI updates when a refresh writes new prices.
alter publication supabase_realtime add table public.positions;
