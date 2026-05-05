-- Fix Supabase security advisor finding:
--   "View public.tag_stats is defined with the SECURITY DEFINER property"
--
-- Postgres views default to "definer" semantics: they run with the
-- privileges of whoever created the view (typically `postgres`), which
-- means they ignore the RLS policies on the underlying `reports` and
-- `tags` tables. We want the view to read with the *querying* user's
-- privileges so member-gated RLS still applies.
--
-- security_invoker = true (added in PG 15) does exactly that.

ALTER VIEW public.tag_stats SET (security_invoker = true);
