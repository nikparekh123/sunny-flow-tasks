-- Audit, 13 Oct 2026: two objects answered without a login.
-- sync_heartbeat's read policy was granted to `public`, and the account
-- sync's detail line carried the account value; option_greeks_latest ran as
-- its owner, so RLS on option_greeks_live never applied. The app and the
-- website both sign in, and the edge functions use the service role, so
-- neither change touches a real reader.
drop policy if exists sync_heartbeat_read on public.sync_heartbeat;
create policy sync_heartbeat_read on public.sync_heartbeat for select to authenticated using (true);
revoke select on public.sync_heartbeat from anon;
alter view public.option_greeks_latest set (security_invoker = on);
revoke select on public.option_greeks_latest from anon;
update public.sync_heartbeat set detail = regexp_replace(detail, ' · close [0-9.]+', '') where feed = 'ibkr-account-sync';
