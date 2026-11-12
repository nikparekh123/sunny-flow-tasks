-- 12 Nov 2026 (Nik: yes). The market walls job ran ten names in a row inside one 240 s call and ran out of time
-- before AVGO, the tenth (its walls stopped on 2 Nov). Two calls of five. PEP's own gamma job goes: neither book holds
-- PEP now, and gamma-close-held covers any held name without a job of its own.
select cron.unschedule('gex-walls-market');
select cron.schedule('gex-walls-market', '20 21 * * 1-5',
  $$select public.cron_invoke_function_body('gex-walls', '{"mode":"daily","tickers":["SPY","QQQ","NVDA","MSFT","AAPL"]}'::jsonb, 240000)$$);
select cron.schedule('gex-walls-market-2', '22 21 * * 1-5',
  $$select public.cron_invoke_function_body('gex-walls', '{"mode":"daily","tickers":["AMZN","GOOGL","META","TSLA","AVGO"]}'::jsonb, 240000)$$);
select cron.unschedule('gamma-close-pep');
