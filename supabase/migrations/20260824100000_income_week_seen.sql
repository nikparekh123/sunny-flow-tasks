-- Which Monday cards have been read.
--
-- Nik: "gone means once I've read it." So the weekly card needs to remember
-- which week it has already shown, and one row per week is the whole state.
--
-- NOT reused from income_card_seen. That table is keyed by TICKER and carries
-- two dates whose job is to decide which per-position bullets get a NEW tag.
-- Bending it to also mean "this week's summary was read" would give one row two
-- unrelated meanings, which is how a table stops being readable.
create table if not exists income_week_seen (
  week_from  date primary key,          -- Monday of the week the card reported on
  seen_at    timestamptz not null default now()
);

comment on table income_week_seen is
  'One row per weekly summary card that has been shown. Presence = already read.';

alter table income_week_seen enable row level security;

drop policy if exists income_week_seen_service on income_week_seen;
create policy income_week_seen_service on income_week_seen
  for all to service_role using (true) with check (true);
