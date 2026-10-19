-- A share BUY can close a short (an assigned call leaves him short the shares,
-- he buys them back). IBKR books that trade's realized P&L, with the call's
-- premium in it, on the BUY. share_lots had nowhere to keep it, so Sunny
-- dropped it (KR, 21 Sep 2026: +$42.81). Null on an ordinary buy.
alter table public.share_lots
  add column if not exists realized_pl numeric,
  add column if not exists realized_pl_source text;

comment on column public.share_lots.realized_pl is
  'IBKR fifoPnlRealized on a buy that closes a short (Daily Flex). Null on ordinary buys and until the nightly Daily Flex delivers it.';

-- KR buy-back of 21 Sep 2026, from IBKR''s September statement (outside the
-- nightly 5-business-day backfill window).
update public.share_lots
   set realized_pl = 42.811485, realized_pl_source = 'ibkr'
 where ibkr_trade_id = '10248577022' and ticker = 'KR';
