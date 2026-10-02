-- IBKR's own realized P&L on a closing option fill (fifoPnlRealized from the
-- 09:00 Daily Flex backfill). Null until that report delivers it; the app
-- falls back to average cost, IBKR's method on this account. Nik, 28 Sep 2026.
alter table public.option_trades
  add column if not exists realized_pl numeric,
  add column if not exists realized_pl_source text;
comment on column public.option_trades.realized_pl is
  'IBKR fifoPnlRealized for a closing fill (Daily Flex), dollars; null until the 09:00 backfill delivers it';
