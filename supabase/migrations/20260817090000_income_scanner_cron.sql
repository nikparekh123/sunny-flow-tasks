/* ============================================================
   income-scanner on a cron.

   Until now it ran only when poked by hand, so income_scanner_results held
   whatever the last manual run wrote — and the Income screen, which reads the
   table rather than calling the function, would have shown a stale day.

   ── Why nightly and not intraday ───────────────────────────────────────────
   Every gate it applies is slow-moving: a 12-month return, a 3-month return,
   60-day volatility, a 52-week position, the worst non-earnings day. None of
   those change between lunch and the close. The two that do move, implied vol
   and open interest, are read at the same time each day so the series is
   comparable rather than a mix of times.

   05:20 UTC = 01:20 ET, well after the US close and well before the open, so a
   run always sees a complete session and never a half-formed one.

   ── Why it is one run and not many ─────────────────────────────────────────
   ~280 Polygon calls across 143 names, and the fan-out is already the cause of
   the connection failures that made LULU look like it had no market. Running it
   more often would buy nothing and cost reliability.
   ============================================================ */

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

do $$
declare
  proj_url text := 'https://ziwoutsnuywjnsyfbzsp.supabase.co';
  svc_key  text;
begin
  select decrypted_secret into svc_key
    from vault.decrypted_secrets where name = 'service_role_key' limit 1;
  if svc_key is null then
    raise notice 'Skipped income-scanner-nightly: vault secret "service_role_key" not set.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'income-scanner-nightly') then
    perform cron.unschedule('income-scanner-nightly');
  end if;

  perform cron.schedule(
    'income-scanner-nightly',
    '20 5 * * 2-6',          -- Tue-Sat UTC = after each Mon-Fri US close
    format($f$
      select net.http_post(
        url     := %L,
        headers := jsonb_build_object('Content-Type','application/json',
                                      'Authorization','Bearer ' || %L),
        body    := '{}'::jsonb,
        timeout_milliseconds := 240000
      );
    $f$, proj_url || '/functions/v1/income-scanner', svc_key)
  );
end $$;

select jobname, schedule, active from cron.job where jobname like 'income-%';
