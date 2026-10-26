-- Handoff 32: the Gamma tab shows the Home watchlist names as open-interest walls only ("OI only, no tape
-- labels"), so their expiries are logged one by one after each close like the book's.
select cron.schedule('gex-walls-watch', '25 21 * * 1-5', $$ select public.cron_invoke_function_body('gex-walls',
  '{"mode":"daily","per_expiry":true,"tickers":["INTU","ADBE","PYPL","VZ","TMUS","SPCX","TSLA","APP"]}'::jsonb, 240000) $$);
