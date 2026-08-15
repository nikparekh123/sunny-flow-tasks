/* ============================================================
   Five views flagged CRITICAL by Supabase's linter for being SECURITY DEFINER.

   A SECURITY DEFINER view runs with its CREATOR's permissions, so anyone who can
   reach the view reads the underlying data regardless of their own grants or any
   row-level security on the tables beneath it. security_invoker flips that: the
   view runs as whoever is querying.

   CHECKED BEFORE FLIPPING, because switching a view whose callers lack rights on
   the base tables makes it silently return nothing rather than erroring:

     view                     base table          who reads it
     option_iv_daily_change   option_greeks       NOTHING. Only its own migration
                                                  and a stale CLAUDE.md line.
     option_greeks_latest     option_greeks       mp-refresh, health-monitor
     ticker_quotes_latest     ticker_quotes       mp-refresh, ticker-iv-snapshot,
                                                  alert-dispatcher
     ticker_iv_summary        ticker_iv_daily     ticker-iv-snapshot
     bnf_universe_latest      bnf_universe_data   NOTHING

   Every reader is an edge function on the service key, which bypasses RLS
   entirely, so none of them change behaviour. The iOS app reads none of these
   five directly. All four base tables already answer the app's publishable key
   with HTTP 200, so even a direct read would still work.

   ALTER VIEW rather than CREATE OR REPLACE: the definitions are untouched, only
   the execution context changes.
   ============================================================ */

alter view public.option_iv_daily_change set (security_invoker = on);
alter view public.option_greeks_latest   set (security_invoker = on);
alter view public.ticker_quotes_latest   set (security_invoker = on);
alter view public.ticker_iv_summary      set (security_invoker = on);
alter view public.bnf_universe_latest    set (security_invoker = on);

-- Should list security_invoker=true against all five.
select c.relname as view_name, c.reloptions
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relkind = 'v'
  and c.relname in ('option_iv_daily_change','option_greeks_latest',
                    'ticker_quotes_latest','ticker_iv_summary','bnf_universe_latest')
order by c.relname;
