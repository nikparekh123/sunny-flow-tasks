-- PLANNER INPUTS, test on one name (Nik, 16 Oct 2026). The five questions behind
-- next week's calls: is selling worth it (IV, realised, IV rank), where is the price
-- likely by Friday (EMA/SMA, RSI, momentum, expected move), what walls sit near it
-- (turning points, moving-average lines, open-interest walls, Nik's own levels).
-- Written by the ticker-technicals edge function; NKE only until Nik has seen it.
-- Market data, not personal: readable by any signed-in login.

create table if not exists public.ticker_technicals (
  ticker     text    not null,
  day        date    not null,
  close      numeric not null,
  sma20      numeric, sma50 numeric, sma200 numeric,
  ema20      numeric, ema50 numeric,
  rsi14      numeric,
  chg5_pct   numeric, chg21_pct numeric,
  hv20       numeric, hv30 numeric,      -- realised volatility, annualised
  atm_iv     numeric,                    -- ~30-day at-the-money IV (ticker_iv_daily)
  iv_rank    numeric,                    -- 0-100: where today's IV sits in its 1-year range
  iv_pctile  numeric,                    -- 0-100: share of the last year's days with lower IV
  richness   numeric,                    -- atm_iv / hv20: above 1 means options price more movement than the stock shows
  updated_at timestamptz not null default now(),
  primary key (ticker, day)
);

create table if not exists public.ticker_walls (
  ticker     text    not null,
  kind       text    not null check (kind in ('swing_high', 'swing_low', 'sma50', 'sma200', 'ema20', 'ema50',
                                              'oi_call', 'oi_put', 'manual')),
  price      numeric not null,
  strength   numeric,                    -- touches for a turning point, contracts for an OI wall
  expiry     date,                       -- OI walls: the Friday they belong to
  note       text,
  asof       timestamptz not null default now()
);
create index if not exists ticker_walls_ticker_idx on public.ticker_walls (ticker);

alter table public.ticker_technicals enable row level security;
alter table public.ticker_walls enable row level security;
create policy "ticker_technicals: signed-in read" on public.ticker_technicals for select to authenticated using (true);
create policy "ticker_walls: signed-in read" on public.ticker_walls for select to authenticated using (true);
