/* ============================================================
   planner_commits — what the tool said, what you did, what happened
   ============================================================
   One row per decision. Written when a pick is committed, scored
   later when the expiry resolves.

   THE POINT: all three picks are stored, not just the one taken.
   Scoring only the chosen pick measures which way NVDA went, which
   the tool has no control over. Storing all three measures whether
   the RANKING was any good — and that is the only question about the
   model. It also turns one decision into three scored outcomes.

   The whole decision state is kept, not a summary. Without the
   conviction parts as they read on the day you can learn THAT the
   model was wrong but never WHICH factor led it wrong, and the second
   is the only one you can act on.
   ============================================================ */

create table if not exists public.planner_commits (
  id               uuid primary key default gen_random_uuid(),
  ticker           text not null default 'NVDA',
  taken_on         date not null,
  decided_at       timestamptz not null default now(),

  -- the world, as it read at the moment of the decision
  spot             numeric,
  iv               numeric,
  iv_median        numeric,
  event_state      text,                 -- PRE | CLEAR | POST
  price_state      text,                 -- down | flat | up
  conviction       integer,
  conviction_parts jsonb,                -- all eight families, as read
  keep_pct         numeric,
  keep_delta       numeric,
  hedge_needs      numeric,

  -- every pick offered, taken or not. `chosen` is the 1-based index,
  -- NULL when the answer was to do nothing — which is a decision and
  -- has to be scored like any other.
  picks            jsonb not null,
  chosen           integer,
  declined_why     text,

  -- what the observer said, so a wrong call can be traced to a wrong read
  observations     jsonb,
  quotes_source    text,                 -- polygon | none | dry

  -- the book at the time
  shares           numeric,
  book             jsonb,

  -- filled in when the expiry resolves
  expiry           date,
  underlying_close numeric,
  outcomes         jsonb,                -- per pick: assigned, pl, would-have
  scored_at        timestamptz,

  created_at       timestamptz not null default now(),
  -- One decision per expiry per day. Re-committing the same morning
  -- overwrites rather than duplicating.
  unique (ticker, taken_on, expiry)
);

create index if not exists planner_commits_unscored_idx
  on public.planner_commits (expiry)
  where scored_at is null;

create index if not exists planner_commits_recent_idx
  on public.planner_commits (ticker, taken_on desc);

alter table public.planner_commits enable row level security;

drop policy if exists planner_commits_read on public.planner_commits;
create policy planner_commits_read on public.planner_commits
  for select to authenticated using (true);

drop policy if exists planner_commits_write on public.planner_commits;
create policy planner_commits_write on public.planner_commits
  for all to authenticated using (true) with check (true);

drop policy if exists planner_commits_service on public.planner_commits;
create policy planner_commits_service on public.planner_commits
  for all to service_role using (true) with check (true);
