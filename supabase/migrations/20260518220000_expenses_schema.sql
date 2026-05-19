-- Positions v3: expenses table.
-- Mirror of gain_entries but tracks outflows (losses, fees, put premium paid
-- that's not protective, broker commissions, etc.) Same Stock / Call / Put
-- source split for symmetric matrix views.
--
-- Amount is stored as a magnitude (always >= 0); the UI knows it's negative
-- because the row lives in the expenses table.

create table if not exists public.expenses (
  id            uuid primary key default gen_random_uuid(),
  ticker        text not null,
  expense_date  date not null,
  source        text not null check (source in ('stock', 'call', 'put')),
  amount        numeric(18, 2) not null check (amount >= 0),
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists expenses_ticker_idx on public.expenses (ticker);
create index if not exists expenses_date_idx   on public.expenses (expense_date);
create index if not exists expenses_source_idx on public.expenses (source);

drop trigger if exists expenses_updated_at on public.expenses;
create trigger expenses_updated_at
  before update on public.expenses
  for each row execute function public.positions_set_updated_at();

-- RLS
alter table public.expenses enable row level security;

drop policy if exists "expenses: authenticated read"   on public.expenses;
drop policy if exists "expenses: authenticated insert" on public.expenses;
drop policy if exists "expenses: authenticated update" on public.expenses;
drop policy if exists "expenses: authenticated delete" on public.expenses;

create policy "expenses: authenticated read"   on public.expenses for select to authenticated using (true);
create policy "expenses: authenticated insert" on public.expenses for insert to authenticated with check (true);
create policy "expenses: authenticated update" on public.expenses for update to authenticated using (true);
create policy "expenses: authenticated delete" on public.expenses for delete to authenticated using (true);

-- Realtime
do $$
begin
  alter publication supabase_realtime add table public.expenses;
exception when duplicate_object then null;
end $$;
