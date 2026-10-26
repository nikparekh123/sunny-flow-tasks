-- Handoff 32: each held name's tape and dealer gamma, one name per call, two minutes apart.
--   gamma-close-*   after the close (23:20 UTC = 7:20 PM EDT / 6:20 PM EST; Theta's end of day is in by then):
--                   moves the dealer positions on and saves the day's views.
--   gamma-live-*    every 30 minutes in the session (14:05-20:35 UTC): today's tape so far, views only.
do $$
declare t text; i int := 0;
begin
  foreach t in array array['BABA','FIS','LULU','NFLX','NKE','PEP','UBER','TSLA'] loop
    perform cron.schedule('gamma-close-' || lower(t), (20 + 2 * i) || ' 23 * * 1-5',
      format($c$ select public.cron_invoke_function_body('gex-walls', '{"mode":"tape_gamma","ticker":"%s"}'::jsonb, 240000) $c$, t));
    perform cron.schedule('gamma-live-' || lower(t), (5 + 2 * i) || ',' || (35 + 2 * i) || ' 14-20 * * 1-5',
      format($c$ select public.cron_invoke_function_body('gex-walls', '{"mode":"tape_gamma","ticker":"%s"}'::jsonb, 240000) $c$, t));
    i := i + 1;
  end loop;
end $$;
