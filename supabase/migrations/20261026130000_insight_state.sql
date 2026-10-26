-- Handoff 32 (14d), 26 Oct 2026: the first read of each Insights point per name per day, so the All page can
-- say what changed since the last session (a point is new when its tag or variant differs).
create table if not exists public.insight_state (
  ticker text not null, day date not null, key text not null, kind text not null, tag text not null,
  primary key (ticker, day, key)
);
alter table public.insight_state enable row level security;
