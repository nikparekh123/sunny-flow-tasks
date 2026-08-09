/* ============================================================
   Context calendar — the world around the position
   ============================================================
   The planner's "what matters / what won't matter" lists are only
   honest if the calendar behind them is real. Before this migration
   macro_events held holidays and Fed decisions only, and
   earnings_events held NVDA alone. That made "nothing on the
   calendar" a statement about our table rather than about the week.

   It was also actively wrong: CPI lands 12 Aug 2026, the same session
   as a 60-contract expiry, and the planner had no idea.

   Two seeds:
     1. macro_events   — CPI, Employment Situation, FOMC
     2. earnings_events — the semi peers, scoped to NVDA

   Dates are as published by BLS and the Federal Reserve. CPI and jobs
   are seeded only as far as the published schedule was verifiable
   (through Oct 2026); BLS blocks automated fetches, so November
   onward needs a manual top-up from bls.gov/schedule. FOMC runs
   through 2027 and is tentative past the next meeting by the Fed's
   own note.

   Both inserts are idempotent on their natural keys, so re-running is
   safe and a later, better feed can overwrite in place.
   ============================================================ */

-- ── 1. macro ────────────────────────────────────────────────────────
-- 8:30 ET for BLS releases, 14:00 ET for the FOMC statement.
insert into public.macro_events
  (event_date, event_time, timezone, country, name, category, importance, summary, source, source_id)
values
  ('2026-08-12', '08:30', 'America/New_York', 'US', 'CPI (July 2026)',                'inflation', 3, 'Consumer prices, July data.',      'manual', 'bls-cpi-2026-07'),
  ('2026-09-04', '08:30', 'America/New_York', 'US', 'Employment Situation (Aug 2026)','jobs',      3, 'Payrolls and unemployment, August.','manual', 'bls-empsit-2026-08'),
  ('2026-09-11', '08:30', 'America/New_York', 'US', 'CPI (August 2026)',              'inflation', 3, 'Consumer prices, August data.',    'manual', 'bls-cpi-2026-08'),
  ('2026-10-02', '08:30', 'America/New_York', 'US', 'Employment Situation (Sep 2026)','jobs',      3, 'Payrolls and unemployment, September.','manual','bls-empsit-2026-09'),
  ('2026-10-14', '08:30', 'America/New_York', 'US', 'CPI (September 2026)',           'inflation', 3, 'Consumer prices, September data.', 'manual', 'bls-cpi-2026-09'),
  -- FOMC. The Sep and Oct rows already exist under this exact name; the
  -- conflict clause updates them in place rather than duplicating.
  ('2026-09-16', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day.', 'manual', 'fomc-2026-09'),
  ('2026-10-28', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day.', 'manual', 'fomc-2026-10'),
  ('2026-12-09', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day.', 'manual', 'fomc-2026-12'),
  ('2027-01-27', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day, tentative.', 'manual', 'fomc-2027-01'),
  ('2027-03-17', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day, tentative.', 'manual', 'fomc-2027-03'),
  ('2027-04-28', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day, tentative.', 'manual', 'fomc-2027-04'),
  ('2027-06-09', '14:00', 'America/New_York', 'US', 'Fed Interest Rate Decision', 'rates', 3, 'FOMC statement day, tentative.', 'manual', 'fomc-2027-06')
on conflict (event_date, name, country) do update
  set event_time = excluded.event_time,
      category   = excluded.category,
      importance = excluded.importance,
      summary    = excluded.summary,
      source_id  = excluded.source_id;

-- ── 2. the neighbourhood ────────────────────────────────────────────
-- Semis trade as a bloc through earnings season, so a peer print inside
-- the window is a real observation about the week. AMD's 4 Aug print is
-- seeded deliberately: a peer that reported six days ago is context, not
-- history.
--
-- notes carries confirmation status, because "AVGO reports Wednesday"
-- and "AVGO probably reports Wednesday" are different claims and the
-- card should never blur them.
insert into public.earnings_events
  (ticker, company_name, report_date, report_time, fiscal_period,
   scope_tag, peer_of_tickers, sector_etf, source, notes)
values
  ('AMD',  'Advanced Micro Devices',        '2026-08-04', 'amc', 'Q2 2026', 'peer', array['NVDA'], 'SMH', 'manual', 'confirmed, reported'),
  ('AVGO', 'Broadcom',                      '2026-09-02', 'amc', 'Q3 FY26', 'peer', array['NVDA'], 'SMH', 'manual', 'confirmed'),
  ('MU',   'Micron Technology',             '2026-09-23', 'amc', 'Q4 FY26', 'peer', array['NVDA'], 'SMH', 'manual', 'estimated, not company-confirmed'),
  ('TSM',  'Taiwan Semiconductor',          '2026-10-15', 'bmo', 'Q3 2026', 'peer', array['NVDA'], 'SMH', 'manual', 'estimated, not company-confirmed'),
  ('AMD',  'Advanced Micro Devices',        '2026-11-03', 'amc', 'Q3 2026', 'peer', array['NVDA'], 'SMH', 'manual', 'estimated, not company-confirmed')
on conflict (ticker, report_date) do update
  set report_time     = excluded.report_time,
      fiscal_period   = excluded.fiscal_period,
      scope_tag       = excluded.scope_tag,
      peer_of_tickers = excluded.peer_of_tickers,
      sector_etf      = excluded.sector_etf,
      notes           = excluded.notes;
