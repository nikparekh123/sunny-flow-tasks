-- 2026-10-09: earnings-sync moved from Benzinga (cancelled add-on) to Nasdaq's
-- public calendar. Allow the new source value. Applied via the Management API.
alter table public.earnings_events drop constraint if exists earnings_events_source_check;
alter table public.earnings_events add constraint earnings_events_source_check
  check (source = any (array['manual','investing.com','fmp','iex','benzinga','nasdaq','other']));
