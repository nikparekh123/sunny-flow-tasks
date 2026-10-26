-- Handoff 32 (rule 5), 26 Oct 2026: each name's flow profile, five inputs over the last 20 sessions ranked against
-- the book, the watchlist and the 100 most-traded option names (research/flow-profile/run.py writes it).
create table if not exists public.flow_profile (
  ticker text primary key,
  asof date not null,
  sessions int not null,
  universe int not null,
  retail int not null,
  profile text not null,          -- 'retail-heavy' | 'institution-heavy'
  inputs jsonb not null,          -- [{key, name, value, pct, retail}]
  built_at timestamptz not null default now()
);
alter table public.flow_profile enable row level security;
