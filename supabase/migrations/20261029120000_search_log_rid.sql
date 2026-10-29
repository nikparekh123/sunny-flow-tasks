-- Sunny search (29 Oct 2026): an answer the phone lost on the way (the connection dropped while the server
-- finished) can be fetched again by the request id the phone sent; the phone's own error is kept for review.
alter table public.search_log
  add column if not exists rid text,
  add column if not exists reply jsonb,
  add column if not exists client_error text;
create index if not exists search_log_rid on public.search_log (rid) where rid is not null;
