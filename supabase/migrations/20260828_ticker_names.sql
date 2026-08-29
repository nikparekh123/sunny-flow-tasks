-- Applied to prod 2026-08-28 via the Management API.
--
-- The company's own name, resolved once and kept. Nothing stored it: positions.name
-- echoes the ticker back, earnings_events.company_name is NULL for every held name,
-- guidance_events has no such column, and sunny-rail resolved names from Polygon into
-- an in-memory Map that dies with every cold start.
--
-- The New page's news filter needs it: "does this headline name the company I hold"
-- is the whole keep rule, and without a name it fell through to "does not name the
-- company" on stories that plainly did — "Walt Disney vs. Netflix" under NFLX,
-- "Constellation's New Power Deals" under CEG.

create table if not exists ticker_names (
  ticker     text primary key,
  name       text not null,
  updated_at timestamptz not null default now()
);

comment on table ticker_names is
 'Company name per ticker, from Polygon /v3/reference/tickers. Written on demand by new-page when a held name is missing, so it fills itself and costs one call per ticker ever.';

alter table ticker_names enable row level security;
drop policy if exists ticker_names_read on ticker_names;
create policy ticker_names_read on ticker_names for select to anon, authenticated using (true);
grant select on ticker_names to anon, authenticated;
grant all on ticker_names to service_role;
