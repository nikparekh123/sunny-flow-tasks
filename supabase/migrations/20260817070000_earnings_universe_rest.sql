/* ============================================================
   Confirmed report dates for the rest of the scanner universe, supplied by Nik
   2026-08-17. 100 names, on top of the 17 in 20260817060000.

   ANNOUNCED, not inferred, so date_estimated is false and the normal one-week
   margin rule applies rather than the two-week window an estimate gets.

   Why this matters more than housekeeping: a name with no date on file is
   SKIPPED by design, because a guard that cannot fire looks exactly like a guard
   with nothing to catch. Before today the whole table held three future dates.

   ── Five rows deliberately dropped ─────────────────────────────────────────
   The source listed a second, earlier date for five names, all already past:

     VST  7 Aug   RKLB 10 Aug   SMCI 11 Aug   CSCO 12 Aug   AMAT 13 Aug

   Those are the prints that just happened, not the next ones. Loading them would
   be harmless in itself — the engines only read report_date >= today — but a
   past date sitting beside a future one invites the wrong one being trusted
   later, so they stay out and the reason is recorded here.

   Held names carry scope_tag 'position'; the rest are 'top50'. It answers "why
   is this ticker here", and screening a name is not the same as trading it.
   ============================================================ */

insert into public.earnings_events
  (ticker, report_date, scope_tag, date_estimated, source) values
  ('BIDU', '2026-08-18', 'top50', false, 'manual'),
  ('HD', '2026-08-18', 'top50', false, 'manual'),
  ('EL', '2026-08-19', 'top50', false, 'manual'),
  ('LOW', '2026-08-19', 'top50', false, 'manual'),
  ('TGT', '2026-08-19', 'top50', false, 'manual'),
  ('BABA', '2026-08-20', 'top50', false, 'manual'),
  ('DE', '2026-08-20', 'top50', false, 'manual'),
  ('WMT', '2026-08-20', 'top50', false, 'manual'),
  ('INTU', '2026-08-25', 'top50', false, 'manual'),
  ('CRM', '2026-08-26', 'top50', false, 'manual'),
  ('CRWD', '2026-08-26', 'top50', false, 'manual'),
  ('SJM', '2026-08-26', 'top50', false, 'manual'),
  ('LULU', '2026-08-27', 'position', false, 'manual'),
  ('MRVL', '2026-08-27', 'top50', false, 'manual'),
  ('ULTA', '2026-08-27', 'top50', false, 'manual'),
  ('WDAY', '2026-08-27', 'top50', false, 'manual'),
  ('MDT', '2026-09-01', 'top50', false, 'manual'),
  ('CHWY', '2026-09-02', 'top50', false, 'manual'),
  ('SNOW', '2026-09-02', 'top50', false, 'manual'),
  ('CPB', '2026-09-03', 'top50', false, 'manual'),
  ('DELL', '2026-09-03', 'top50', false, 'manual'),
  ('ADBE', '2026-09-10', 'top50', false, 'manual'),
  ('ORCL', '2026-09-14', 'top50', false, 'manual'),
  ('CCL', '2026-09-17', 'top50', false, 'manual'),
  ('GIS', '2026-09-23', 'top50', false, 'manual'),
  ('COST', '2026-09-24', 'top50', false, 'manual'),
  ('NKE', '2026-09-24', 'position', false, 'manual'),
  ('ACN', '2026-10-01', 'top50', false, 'manual'),
  ('CAG', '2026-10-01', 'top50', false, 'manual'),
  ('DAL', '2026-10-08', 'top50', false, 'manual'),
  ('UNH', '2026-10-09', 'top50', false, 'manual'),
  ('C', '2026-10-13', 'top50', false, 'manual'),
  ('GS', '2026-10-13', 'top50', false, 'manual'),
  ('JPM', '2026-10-13', 'top50', false, 'manual'),
  ('PEP', '2026-10-13', 'top50', false, 'manual'),
  ('WFC', '2026-10-13', 'top50', false, 'manual'),
  ('ASML', '2026-10-14', 'top50', false, 'manual'),
  ('BAC', '2026-10-14', 'top50', false, 'manual'),
  ('MS', '2026-10-14', 'top50', false, 'manual'),
  ('AAL', '2026-10-15', 'top50', false, 'manual'),
  ('SNAP', '2026-10-15', 'top50', false, 'manual'),
  ('TSM', '2026-10-15', 'top50', false, 'manual'),
  ('GE', '2026-10-20', 'top50', false, 'manual'),
  ('JNJ', '2026-10-20', 'top50', false, 'manual'),
  ('VZ', '2026-10-20', 'top50', false, 'manual'),
  ('IBM', '2026-10-21', 'top50', false, 'manual'),
  ('LRCX', '2026-10-21', 'top50', false, 'manual'),
  ('PG', '2026-10-21', 'top50', false, 'manual'),
  ('HSY', '2026-10-22', 'top50', false, 'manual'),
  ('INTC', '2026-10-22', 'top50', false, 'manual'),
  ('MA', '2026-10-22', 'top50', false, 'manual'),
  ('MCD', '2026-10-22', 'top50', false, 'manual'),
  ('NEE', '2026-10-22', 'top50', false, 'manual'),
  ('SHOP', '2026-10-22', 'top50', false, 'manual'),
  ('ABBV', '2026-10-23', 'top50', false, 'manual'),
  ('AXP', '2026-10-23', 'top50', false, 'manual'),
  ('CL', '2026-10-23', 'top50', false, 'manual'),
  ('CVX', '2026-10-23', 'top50', false, 'manual'),
  ('XOM', '2026-10-23', 'top50', false, 'manual'),
  ('KMB', '2026-10-27', 'top50', false, 'manual'),
  ('PYPL', '2026-10-27', 'top50', false, 'manual'),
  ('SPOT', '2026-10-27', 'top50', false, 'manual'),
  ('TXN', '2026-10-27', 'top50', false, 'manual'),
  ('BA', '2026-10-28', 'top50', false, 'manual'),
  ('FDX', '2026-10-28', 'top50', false, 'manual'),
  ('NOW', '2026-10-28', 'top50', false, 'manual'),
  ('T', '2026-10-28', 'top50', false, 'manual'),
  ('VRT', '2026-10-28', 'top50', false, 'manual'),
  ('COIN', '2026-10-29', 'top50', false, 'manual'),
  ('CVNA', '2026-10-29', 'top50', false, 'manual'),
  ('LLY', '2026-10-29', 'top50', false, 'manual'),
  ('MO', '2026-10-29', 'top50', false, 'manual'),
  ('MRK', '2026-10-29', 'top50', false, 'manual'),
  ('SBUX', '2026-10-29', 'top50', false, 'manual'),
  ('UBER', '2026-10-29', 'top50', false, 'manual'),
  ('PFE', '2026-11-03', 'top50', false, 'manual'),
  ('SMCI', '2026-11-03', 'top50', false, 'manual'),
  ('SOFI', '2026-11-03', 'top50', false, 'manual'),
  ('V', '2026-11-03', 'top50', false, 'manual'),
  ('ABNB', '2026-11-04', 'top50', false, 'manual'),
  ('ARM', '2026-11-04', 'top50', false, 'manual'),
  ('CAT', '2026-11-04', 'top50', false, 'manual'),
  ('EBAY', '2026-11-04', 'top50', false, 'manual'),
  ('MSTR', '2026-11-04', 'top50', false, 'manual'),
  ('QBTS', '2026-11-05', 'top50', false, 'manual'),
  ('SMR', '2026-11-05', 'top50', false, 'manual'),
  ('SOUN', '2026-11-05', 'top50', false, 'manual'),
  ('VST', '2026-11-05', 'top50', false, 'manual'),
  ('O', '2026-11-09', 'top50', false, 'manual'),
  ('RIOT', '2026-11-10', 'top50', false, 'manual'),
  ('RIVN', '2026-11-10', 'top50', false, 'manual'),
  ('IONQ', '2026-11-11', 'top50', false, 'manual'),
  ('MARA', '2026-11-11', 'top50', false, 'manual'),
  ('QCOM', '2026-11-11', 'top50', false, 'manual'),
  ('ZTS', '2026-11-11', 'top50', false, 'manual'),
  ('AMAT', '2026-11-12', 'top50', false, 'manual'),
  ('RGTI', '2026-11-16', 'top50', false, 'manual'),
  ('RKLB', '2026-11-16', 'top50', false, 'manual'),
  ('CSCO', '2026-11-18', 'top50', false, 'manual'),
  ('OKLO', '2026-11-18', 'top50', false, 'manual')
on conflict (ticker, report_date) do update set date_estimated = false;

notify pgrst, 'reload schema';

select count(*) filter (where report_date >= current_date) as future_dates,
       count(*) filter (where date_estimated) as estimates
  from public.earnings_events;
