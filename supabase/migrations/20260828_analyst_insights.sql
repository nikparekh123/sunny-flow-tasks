-- Applied to prod 2026-08-28 via the Management API.
--
-- The analyst insight: a paragraph of the firm's own analysis, arriving only
-- with a rating. It is the only vendor prose the product prints, and until now
-- nothing stored it — intel-sync fetched guidance, ratings, consensus and news,
-- and the insights endpoint was only ever hit by income-scanner's probe.
--
-- `benzinga_rating_id` joins exactly to `analyst_actions.benzinga_id` (verified
-- 4 of 4 on live rows), which is what lets the New page's action card carry its
-- own insight under a rule rather than showing it as a separate section.

create table if not exists analyst_insights (
  benzinga_id        text primary key,
  benzinga_rating_id text,
  ticker             text not null,
  date               date not null,
  firm               text,
  rating             text,
  rating_action      text,
  price_target       numeric,
  insight            text not null,
  updated_at         timestamptz not null default now()
);

create index if not exists analyst_insights_ticker_date on analyst_insights (ticker, date desc);
create index if not exists analyst_insights_rating on analyst_insights (benzinga_rating_id);

comment on table analyst_insights is
 'Benzinga analyst-insights, one row per insight. Arrives only attached to a rating, so it can never be more frequent than analyst_actions. The text OPENS WITH A RESTATEMENT of the rating ("RBC Capital reiterated their Sector Perform rating...") and only then gives its bullets — a reader-facing card must SELECT from it, never truncate the first sentence, which duplicates the row above it.';

alter table analyst_insights enable row level security;
drop policy if exists analyst_insights_read on analyst_insights;
create policy analyst_insights_read on analyst_insights for select to anon, authenticated using (true);
grant select on analyst_insights to anon, authenticated;
grant all on analyst_insights to service_role;
