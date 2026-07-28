/* ============================================================
   NVDA store — keep-current + end-of-day booking (pure SQL crons).

   1. nvda_mirror()  — forwards NVDA rows (>= Jul 1) from the legacy
      book into the nvda_* store. The battle-tested ibkr-flex-sync keeps
      the legacy tables current; this just mirrors NVDA into the new
      store every 3 min. Idempotent upsert by id (updates voids, closes,
      qty_remaining, realized_pl as they change). SECURITY DEFINER so it
      bypasses RLS on the nvda_* tables.

   2. nvda_eod()     — at the close, snapshots the day's per-leg marks
      into nvda_option_marks_eod (feeds the by-source history chart) and
      books NVDA + peers closes into nvda_daily_closes (feeds the peers
      5-session cards). Dates are the America/New_York market date.

   NOTE: this depends on the legacy ibkr-flex-sync continuing to land
   NVDA in the legacy tables. If that's ever retired, replace nvda_mirror
   with a direct IBKR Flex feed into the nvda_* tables.
   ============================================================ */

create extension if not exists pg_cron with schema extensions;

-- ---------- 1 · mirror legacy NVDA → nvda_* ----------
create or replace function public.nvda_mirror() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.nvda_option_trades
    (id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,
     closes_trade_id,rolled_from,closed_via,share_pnl,source,ibkr_trade_id,executed_at,last_synced_at,voided_at)
  select id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,
     closes_trade_id,rolled_from,closed_via,share_pnl,source,ibkr_trade_id,executed_at,last_synced_at,voided_at
  from public.option_trades where ticker='NVDA' and trade_date >= '2026-07-01'
  on conflict (id) do update set
     action=excluded.action, contracts=excluded.contracts, premium=excluded.premium,
     closes_trade_id=excluded.closes_trade_id, rolled_from=excluded.rolled_from,
     closed_via=excluded.closed_via, share_pnl=excluded.share_pnl,
     executed_at=excluded.executed_at, last_synced_at=excluded.last_synced_at, voided_at=excluded.voided_at;

  insert into public.nvda_share_lots
    (id,acquired_date,fifo_order,qty_original,qty_remaining,cost_per_share,source,ibkr_trade_id,executed_at,last_synced_at,voided_at)
  select id,acquired_date,fifo_order,qty_original,qty_remaining,cost_per_share,source,ibkr_trade_id,executed_at,last_synced_at,voided_at
  from public.share_lots where ticker='NVDA' and acquired_date >= '2026-07-01'
  on conflict (id) do update set
     qty_remaining=excluded.qty_remaining, cost_per_share=excluded.cost_per_share,
     executed_at=excluded.executed_at, last_synced_at=excluded.last_synced_at, voided_at=excluded.voided_at;

  insert into public.nvda_share_sells
    (id,trade_date,quantity,price,realized_pl,fifo_reconciled_at,source,ibkr_trade_id,executed_at,last_synced_at,voided_at)
  select id,trade_date,quantity,price,coalesce(realized_pl,0),fifo_reconciled_at,source,ibkr_trade_id,executed_at,last_synced_at,voided_at
  from public.share_sells where ticker='NVDA' and trade_date >= '2026-07-01'
  on conflict (id) do update set
     realized_pl=excluded.realized_pl, fifo_reconciled_at=excluded.fifo_reconciled_at,
     executed_at=excluded.executed_at, last_synced_at=excluded.last_synced_at, voided_at=excluded.voided_at;
end $$;

-- ---------- 2 · end-of-day booking ----------
create or replace function public.nvda_eod() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.nvda_option_marks_eod (option_trade_id, date, mark, delta, theta, captured_at)
  select option_trade_id, (captured_at at time zone 'America/New_York')::date, mark, delta, theta, captured_at
  from public.nvda_option_marks
  on conflict (option_trade_id, date) do update set
     mark=excluded.mark, delta=excluded.delta, theta=excluded.theta, captured_at=excluded.captured_at;

  insert into public.nvda_daily_closes (ticker, date, close_price)
  select ticker, (captured_at at time zone 'America/New_York')::date, spot
  from public.nvda_quote where spot is not null
  on conflict (ticker, date) do update set close_price=excluded.close_price;
end $$;

-- ---------- 3 · schedules ----------
do $$ begin
  if exists (select 1 from cron.job where jobname='nvda-mirror-3min') then perform cron.unschedule('nvda-mirror-3min'); end if;
  if exists (select 1 from cron.job where jobname='nvda-eod')        then perform cron.unschedule('nvda-eod'); end if;
  perform cron.schedule('nvda-mirror-3min', '*/3 13-22 * * 1-5', 'select public.nvda_mirror()');
  perform cron.schedule('nvda-eod',         '10 21 * * 1-5',     'select public.nvda_eod()');
end $$;

-- run the mirror once now so the store is current immediately
select public.nvda_mirror();
