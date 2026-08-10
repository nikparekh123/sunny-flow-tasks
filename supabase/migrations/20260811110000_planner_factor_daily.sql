/* ============================================================
   planner_factor_daily — yesterday, so today has something to mean
   ============================================================
   The conviction page is built on movement: a trail under the hero
   (72 → 78 → 91), a sentence naming the two biggest movers, discs
   ordered by what changed most, and a tap that says "added 4 on
   yesterday". Every one of those needs the score AS IT READ on
   previous days, per family.

   Nothing stored it. planner_commits holds conviction and its parts,
   but only on days a pick was committed — so a trail drawn from it
   would skip every day you didn't trade and label last Thursday
   "yesterday". A gap-free daily series is its own thing.

   One row per ticker per day, upserted. The planner writes it on
   every full compute, so it fills simply by using the app; the
   30-minute ingest cron guarantees a row on days you never open it.
   Last write of the day wins, which is what "as it read" should mean
   for a decision made in the morning and revisited at the close.

   Generic by ticker: TLT gets its own planner and will want the same
   history without a second table.
   ============================================================ */

create table if not exists public.planner_factor_daily (
  ticker      text not null default 'NVDA',
  date        date not null,
  conviction  integer,
  -- { trend: 22, catalyst: 10, stretch: -2, record: 6, relative: 5,
  --   sector: 3, peers: 0, grade: 4, macro: -4 }
  -- Stored as sent rather than as columns: the families have changed
  -- twice already this year, and a jsonb blob survives the next change
  -- without a migration that would strand the history behind it.
  parts       jsonb not null default '{}'::jsonb,
  spot        numeric,
  event_state text,
  captured_at timestamptz not null default now(),
  primary key (ticker, date)
);

create index if not exists planner_factor_daily_recent_idx
  on public.planner_factor_daily (ticker, date desc);

alter table public.planner_factor_daily enable row level security;

drop policy if exists planner_factor_daily_read on public.planner_factor_daily;
create policy planner_factor_daily_read on public.planner_factor_daily
  for select to authenticated using (true);

drop policy if exists planner_factor_daily_service on public.planner_factor_daily;
create policy planner_factor_daily_service on public.planner_factor_daily
  for all to service_role using (true) with check (true);

/* ------------------------------------------------------------
   Seed the series from what planner_commits already holds.
   Gappy by nature — only days a pick was committed — but it means
   the trail has real history on day one instead of three days of
   nothing. Days the planner ran without a commit are simply absent,
   which the reader must treat as "no reading", never as zero.
   ------------------------------------------------------------ */
insert into public.planner_factor_daily (ticker, date, conviction, parts, spot, event_state, captured_at)
select distinct on (c.ticker, c.taken_on)
       c.ticker, c.taken_on, c.conviction,
       coalesce(c.conviction_parts, '{}'::jsonb), c.spot, c.event_state, c.decided_at
from public.planner_commits c
where c.conviction is not null
order by c.ticker, c.taken_on, c.decided_at desc
on conflict (ticker, date) do nothing;

select ticker, date, conviction, jsonb_object_keys_count as families
from (
  select ticker, date, conviction,
         (select count(*) from jsonb_object_keys(parts)) as jsonb_object_keys_count
  from public.planner_factor_daily
) s
order by date desc
limit 10;
