-- New Home (handoff 6 Nov 2026, Pass 2): The economy and Out today, from FRED via econ-sync.
--
-- One row per indicator (the 12 in the design's sheet). econ-sync rebuilds each card from FRED: the latest
-- reading and the three before it in the indicator's own rhythm (weeks, months or quarters; a daily series uses
-- each week's last value), the run of same-direction moves ending now, and a one-line read of facts (how far
-- back it is the highest or lowest, the change from a year ago). landed_at = when econ-sync first saw the
-- latest reading: "Out today" and "new since yesterday" read it. sunny-home (service role) is the only reader,
-- so RLS is on with no policy.

create table if not exists public.econ_cards (
  id            text primary key,
  ord           int not null,
  series        text not null,
  title         text not null,
  rhythm        text not null,             -- week | month | quarter
  card          jsonb not null,            -- the indicator as the sheet draws it
  watch         boolean not null default false,
  last_period   date,
  fred_updated  timestamptz,
  landed_at     timestamptz,
  updated_at    timestamptz not null default now()
);
alter table public.econ_cards enable row level security;
