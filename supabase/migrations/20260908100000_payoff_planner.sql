-- Payoff planner: hand-entered support/resistance, and saved plans per user.
-- Plans are JSON legs so the web and iOS clients share one row and one shape.

create table if not exists public.ticker_levels (
  ticker      text not null,
  kind        text not null check (kind in ('support','resistance')),
  price       numeric not null,
  note        text,
  updated_at  timestamptz not null default now(),
  primary key (ticker, kind, price)
);
alter table public.ticker_levels enable row level security;
drop policy if exists "levels readable by signed-in" on public.ticker_levels;
create policy "levels readable by signed-in" on public.ticker_levels
  for select to authenticated using (true);

create table if not exists public.payoff_plans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  ticker      text not null,
  name        text not null,
  legs        jsonb not null default '[]'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists payoff_plans_user_ticker on public.payoff_plans(user_id, ticker);
alter table public.payoff_plans enable row level security;
drop policy if exists "own plans" on public.payoff_plans;
create policy "own plans" on public.payoff_plans
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
