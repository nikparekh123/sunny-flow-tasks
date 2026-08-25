-- Feed heartbeats: prove a sync RAN, not that a cron queued a request.
--
-- pg_cron records "succeeded" the moment net.http_post returns a request id.
-- It says nothing about whether the function ran, or wrote, or failed. Three
-- days of "succeeded" is what an analyst feed with a hole in it looks like,
-- and #19 in the tracker is the same lie about the snapshot pipeline.
--
-- A row here is written by the function itself, at the end, after the writes.
-- Age of the row is therefore evidence. `rows_written` is kept because a feed
-- that runs daily and writes nothing for a week is also worth seeing, without
-- being an alert on its own: analysts are quiet at weekends and over holidays.
create table if not exists public.sync_heartbeat (
  feed          text primary key,
  ran_at        timestamptz not null default now(),
  rows_written  integer     not null default 0,
  detail        text
);

comment on table public.sync_heartbeat is
  'One row per data feed, stamped by the feed itself on a successful run. Age is the health signal; cron status is not.';

alter table public.sync_heartbeat enable row level security;

drop policy if exists sync_heartbeat_read on public.sync_heartbeat;
create policy sync_heartbeat_read on public.sync_heartbeat
  for select using (true);
