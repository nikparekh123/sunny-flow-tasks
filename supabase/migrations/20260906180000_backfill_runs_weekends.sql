-- ⚠ THE BACKFILL SKIPPED WEEKENDS AND THAT COST TWO DAYS, NOT ONE.
-- IBKR's intraday Trade Confirmation feed stopped returning confirms after
-- 2026-09-02 (the query is fine and generates fresh; IBKR is simply not
-- populating <TradeConfirms>). The Activity Flex backfill still works, so it
-- became the only automatic path in — but at `0 9 * * 1-5` a FRIDAY fill did
-- not land until MONDAY morning.
--
-- Proven, not assumed: on Sunday 2026-09-06 the Activity report already
-- carried Friday's twenty fills, and the natural-key adoption absorbed every
-- hand-entered row rather than duplicating it. So a Saturday run would have
-- had them, and the worst case drops from three days to one.
--
-- Running it on a day with nothing new is harmless: the report is a rolling
-- 15-business-day window and every row dedupes on ibkr_trade_id.
SELECT cron.schedule(
  'ibkr-flex-backfill-daily',
  '0 9 * * *',
  (SELECT command FROM cron.job WHERE jobname = 'ibkr-flex-backfill-daily')
);
