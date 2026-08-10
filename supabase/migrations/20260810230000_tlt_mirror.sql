/* ============================================================
   tlt_mirror — the missing link in the TLT chain
   ============================================================
   IBKR lands every ticker in the legacy tables: ibkr-flex-sync
   writes option_trades / share_lots / share_sells without filtering
   by symbol, and the TLT legs opened on 10 Aug 2026 are sitting
   there now.

   nvda_mirror() then forwards ticker='NVDA' into the nvda_* store
   every three minutes, which is what the app reads.

   TLT has the first link and the last — tlt_option_trades and
   friends were created on 8 Aug — but nothing in between. So the
   trades arrive, land correctly, and are never copied anywhere the
   app looks. The position appears to be missing when it is only
   one join away.

   This is nvda_mirror with the ticker swapped and no date floor:
   the TLT book starts on 10 Aug 2026, so there is no legacy history
   to exclude.
   ============================================================ */

create extension if not exists pg_cron with schema extensions;

create or replace function public.tlt_mirror() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.tlt_option_trades
    (id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,
     closes_trade_id,rolled_from,closed_via,share_pnl,source,ibkr_trade_id,executed_at,last_synced_at,voided_at)
  select id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,
     closes_trade_id,rolled_from,closed_via,share_pnl,source,ibkr_trade_id,executed_at,last_synced_at,voided_at
  from public.option_trades where ticker = 'TLT'
  on conflict (id) do update set
     action=excluded.action, contracts=excluded.contracts, premium=excluded.premium,
     closes_trade_id=excluded.closes_trade_id, rolled_from=excluded.rolled_from,
     closed_via=excluded.closed_via, share_pnl=excluded.share_pnl,
     executed_at=excluded.executed_at, last_synced_at=excluded.last_synced_at, voided_at=excluded.voided_at;

  -- Shares will arrive by assignment rather than purchase — the 82 and 82.50 puts
  -- expire 12 Aug with TLT around 82 — so the lots table matters from Wednesday.
  insert into public.tlt_share_lots
    (id,acquired_date,fifo_order,qty_original,qty_remaining,cost_per_share,source,ibkr_trade_id,executed_at,last_synced_at,voided_at)
  select id,acquired_date,fifo_order,qty_original,qty_remaining,cost_per_share,source,ibkr_trade_id,executed_at,last_synced_at,voided_at
  from public.share_lots where ticker = 'TLT'
  on conflict (id) do update set
     qty_remaining=excluded.qty_remaining, cost_per_share=excluded.cost_per_share,
     executed_at=excluded.executed_at, last_synced_at=excluded.last_synced_at, voided_at=excluded.voided_at;

  insert into public.tlt_share_sells
    (id,sell_date,qty,price_per_share,realized_pl,source,ibkr_trade_id,executed_at,last_synced_at,voided_at)
  select id,sell_date,qty,price_per_share,realized_pl,source,ibkr_trade_id,executed_at,last_synced_at,voided_at
  from public.share_sells where ticker = 'TLT'
  on conflict (id) do update set
     qty=excluded.qty, price_per_share=excluded.price_per_share, realized_pl=excluded.realized_pl,
     executed_at=excluded.executed_at, last_synced_at=excluded.last_synced_at, voided_at=excluded.voided_at;
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'tlt-mirror-3min') then
    perform cron.unschedule('tlt-mirror-3min');
  end if;
  -- Same cadence and window as the NVDA mirror.
  perform cron.schedule('tlt-mirror-3min', '*/3 13-22 * * 1-5', 'select public.tlt_mirror()');
end $$;

-- Run once now so the store is current immediately rather than in three minutes.
select public.tlt_mirror();
