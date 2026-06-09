/* ============================================================
   mp_refresh_runs — one row per mp-refresh invocation (success or
   failure). Powers the /health page's "is the pipeline alive?" view.

   We log EVERY invocation, not just failures, so the page can show
   freshness ("last run 3 minutes ago") and cron health ("12 runs
   today, 0 errors") in addition to surfacing failure details.

   Retention: keep forever for now (a row is ~1 KB; 96 rows/day at
   15-min cadence = ~35 MB/year). When that becomes a problem add a
   `delete from mp_refresh_runs where started_at < now() - interval
   '90 days'` to the same cron schedule.
   ============================================================ */

create table if not exists public.mp_refresh_runs (
  id              uuid primary key default gen_random_uuid(),
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,                 -- null while in-flight; set on completion
  status          text not null default 'running'
                  check (status in ('running', 'ok', 'error')),
  legs_total      integer,
  legs_updated    integer,
  legs_failed     integer,
  tickers_total   integer,
  tickers_updated integer,
  /** Human-readable error text on failure. NULL on success. */
  error_text      text,
  /** Per-leg failure details (up to 10) for the most recent run.
   *  Shape mirrors what the edge function already returns:
   *  [{ id, ticker, occ, reason }]. */
  failures        jsonb default '[]'::jsonb,
  /** Caller hint — 'manual' for UI/curl, 'cron' for the scheduled job. */
  invoked_by      text default 'manual'
);

create index if not exists idx_mp_refresh_runs_started_at
  on public.mp_refresh_runs (started_at desc);

create index if not exists idx_mp_refresh_runs_status_started
  on public.mp_refresh_runs (status, started_at desc);

alter table public.mp_refresh_runs enable row level security;

drop policy if exists "mp_refresh_runs readable to authenticated" on public.mp_refresh_runs;
create policy "mp_refresh_runs readable to authenticated"
  on public.mp_refresh_runs for select
  to authenticated
  using (true);

-- Writes are service-role only (the edge function), no user mutates.
