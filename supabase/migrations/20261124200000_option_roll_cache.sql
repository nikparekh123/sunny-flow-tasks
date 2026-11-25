-- Income (24 Nov 2026): sunny-home caches the listed expiries (6 h) and the chains a ready rung rolls to (10 min) from
-- Theta, so four builds a minute do not ask Theta each time. Service key only.
create table if not exists public.option_roll_cache (
  key  text primary key,
  data jsonb,
  at   timestamptz not null default now()
);
alter table public.option_roll_cache enable row level security;
revoke all on public.option_roll_cache from anon, authenticated;
