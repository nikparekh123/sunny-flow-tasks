-- Activity (handoff 2026-11-18, round 161): what happened, when, in order. sunny-home writes one row per event as it
-- builds (trade pickups from IBKR, expirations, dividends paid, a held name crossing its 20, 50 or 200-day, nearing or
-- going through this week's walls, a big move); a row updates in place when the same thing changes the same day
-- (crossed back). Members of the book read; only the service role writes.
create table if not exists public.activity_events (
  id         bigserial primary key,
  book_id    text not null,
  key        text not null,
  day        date not null,
  at         timestamptz not null,
  kind       text not null check (kind in ('ibkr', 'lvl', 'move')),
  t          text,
  title      text not null,
  body       text,
  opens      text,
  data       jsonb,
  updated_at timestamptz not null default now(),
  unique (book_id, key)
);
create index if not exists activity_events_book_day on public.activity_events (book_id, day desc);
alter table public.activity_events enable row level security;
drop policy if exists activity_events_read on public.activity_events;
create policy activity_events_read on public.activity_events for select to authenticated
  using (exists (select 1 from public.book_members m where m.book_id = activity_events.book_id and m.user_id = auth.uid()));
grant select on public.activity_events to authenticated;
