/* ============================================================
   tlt_mirror — hand the price back to nvda-marks
   ============================================================
   The previous migration had the mirror copy tlt_quote and
   tlt_option_marks out of the generic ticker_quotes/option_greeks
   tables. That was the right shape for a 15-minute feed and is the
   wrong shape now.

   nvda-marks (the name is a misnomer; it prices every book) has been
   extended to write tlt_quote and tlt_option_marks directly on its
   own 60-second cron. If the mirror kept copying, it would upsert
   mp-refresh's 15-minute-old values over one-minute-old ones every
   three minutes — the position would visibly jump backwards in time.
   Two writers, one row, slower one wins on cadence. Remove it.

   Worse, mp-refresh's cron is '*/15 13-19', so its last write of the
   day is 19:45 UTC — 3:45pm ET. The mirror would have been pinning
   the TLT price to a quarter-hour before the close, every close,
   which is precisely the window that decides assignment on a
   near-the-money weekly.

   Back to what a mirror should do: move the position, nothing else.
   ============================================================ */

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

  insert into public.tlt_share_lots
    (id, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share, source)
  select id, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share, source
  from public.share_lots where ticker = 'TLT'
  on conflict (id) do update set
     qty_remaining = excluded.qty_remaining,
     cost_per_share = excluded.cost_per_share,
     fifo_order = excluded.fifo_order;

  insert into public.tlt_share_sells
    (id, trade_date, quantity, price, source)
  select id, trade_date, quantity, price, source
  from public.share_sells where ticker = 'TLT'
  on conflict (id) do update set
     quantity = excluded.quantity,
     price = excluded.price;
end $$;

select public.tlt_mirror();

-- Freshness, not values: after nvda-marks has run once, both books should
-- carry an age measured in seconds. TLT reading minutes older than NVDA means
-- the function did not deploy.
select 'NVDA' as book, round(extract(epoch from (now() - max(captured_at)))) as secs_old
  from public.nvda_quote
union all
select 'TLT', round(extract(epoch from (now() - max(captured_at))))
  from public.tlt_quote;
