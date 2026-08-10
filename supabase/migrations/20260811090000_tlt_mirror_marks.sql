/* ============================================================
   tlt_mirror, part two — the price, not just the trades
   ============================================================
   The trades mirrored correctly and the TLT screen still rendered
   nothing. The reason is one line in NvDerive.position:

       guard let spot = quote?.spot, spot > 0 else { return nil }

   No spot, no position — and tlt_quote had nothing in it, because
   the first mirror copied trades, lots and sells and stopped there.
   For NVDA those two tables are filled by the nvda-marks edge
   function; TLT has no equivalent and does not need one.

   mp-refresh already prices every ticker it finds in option_trades
   into the generic ticker_quotes and option_greeks tables, and TLT
   has been in option_trades since 10 Aug. So the data is already
   arriving — it just has nowhere to land. This copies it across on
   the same three-minute cron, which is why no new edge function
   (and no dashboard deploy) is involved.

   ticker_quotes carries no prev_close, so it is backed out of the
   day change. Guarded against a -100% day, which would divide by
   zero; a null prev_close is honest, a crash is not.
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

  -- TLT plus the bond complex the peers row compares it against.
  insert into public.tlt_quote (ticker, spot, day_change_pct, prev_close, captured_at)
  select q.ticker, q.spot, q.day_change_pct,
         case when q.day_change_pct is null or q.day_change_pct <= -100 then null
              else q.spot / (1 + q.day_change_pct / 100.0) end,
         q.captured_at
  from public.ticker_quotes q
  where q.ticker in ('TLT','IEF','SHY','TLH','AGG','LQD')
    and q.spot is not null
  on conflict (ticker) do update set
     spot = excluded.spot, day_change_pct = excluded.day_change_pct,
     prev_close = excluded.prev_close, captured_at = excluded.captured_at;

  -- Greeks are keyed on the legacy option_trades id, which the mirror
  -- preserves, so the join needs no translation.
  insert into public.tlt_option_marks
    (option_trade_id, mark, delta, gamma, theta, vega, iv, open_interest, volume, captured_at)
  select g.option_trade_id, g.last_mark, g.delta, g.gamma, g.theta, g.vega,
         g.iv, g.open_interest, g.volume, g.captured_at
  from public.option_greeks g
  join public.tlt_option_trades t on t.id = g.option_trade_id
  on conflict (option_trade_id) do update set
     mark = excluded.mark, delta = excluded.delta, gamma = excluded.gamma,
     theta = excluded.theta, vega = excluded.vega, iv = excluded.iv,
     open_interest = excluded.open_interest, volume = excluded.volume,
     captured_at = excluded.captured_at;
end $$;

select public.tlt_mirror();

-- What landed. Expect a TLT row with a live spot, and marks on the open legs.
select 'quote' as what, ticker, spot::text as v, captured_at from public.tlt_quote
union all
select 'marks', option_trade_id::text, mark::text, captured_at from public.tlt_option_marks
order by 1, 2;
