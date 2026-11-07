-- New Home (handoff 6 Nov 2026, Pass 2): each sector's share of the S&P 500, for the heat map's header
-- ("Technology · 34% of the S&P 500"). market-tape reads SPY's sector weights from Yahoo once a day onto the
-- sector fund's row (etf = true).
alter table public.market_sectors add column if not exists sp_weight numeric;
alter table public.market_sectors add column if not exists sp_weight_at timestamptz;
