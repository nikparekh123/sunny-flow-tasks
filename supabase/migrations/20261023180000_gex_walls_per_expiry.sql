-- Handoff 31 (13d, the Walls screen): one gex_walls row per expiry per day for the book, beside the
-- combined 45-day row (expiry null). The 2nd walls' gamma and the sleeping walls ride along.
alter table public.gex_walls
  add column if not exists expiry date,
  add column if not exists call_wall2_gex numeric,
  add column if not exists put_wall2_gex numeric,
  add column if not exists sleep jsonb;

create index if not exists gex_walls_ticker_expiry_day on public.gex_walls (ticker, expiry, day desc) where expiry is not null;
