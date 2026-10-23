-- Gamma walls for the market (Nik, 23 Oct 2026): SPY, QQQ, the Mag 7 and AVGO join the daily log
-- after the book's names, so a history builds for the broad read (how many names sit above their
-- flip, where the index walls are) before anything is tested against it.

select cron.unschedule('gex-walls-market') where exists (select 1 from cron.job where jobname = 'gex-walls-market');
select cron.schedule('gex-walls-market', '20 21 * * 1-5',
  $$ select public.cron_invoke_function_body('gex-walls',
       '{"mode":"daily","tickers":["SPY","QQQ","NVDA","MSFT","AAPL","AMZN","GOOGL","META","TSLA","AVGO"]}'::jsonb, 240000) $$);
