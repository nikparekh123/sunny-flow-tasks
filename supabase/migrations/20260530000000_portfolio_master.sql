/* ============================================================
   Portfolio master data — option Greeks/OI/IV/Vol + ticker quotes.

   Populated by the `mp-refresh` edge function, which polls Polygon
   (a.k.a. "massive.com") every ~15 minutes during market hours via
   pg_cron. Read by the /portfolio page (and downstream Positions /
   Dashboard / Income after the PD-5 hard cutover).

   One row per open option_trade (option_greeks) and one row per held
   ticker (ticker_quotes). We upsert in place — `captured_at` is the
   freshness indicator; if you want time-series history later, swap the
   PK to (option_trade_id, captured_at) and add an `(option_trade_id,
   captured_at desc)` index.
   ============================================================ */

-- ─── option_greeks ────────────────────────────────────────────
create table if not exists public.option_greeks (
  option_trade_id uuid primary key
    references public.option_trades(id) on delete cascade,
  -- Per-share Greeks at contract level (so portfolio aggregation
  -- multiplies by contracts × 100 × side-sign — see usePortfolioGreeks
  -- in PD-3).
  delta            numeric,
  gamma            numeric,
  theta            numeric,
  vega             numeric,
  -- Implied vol as a decimal (0.42 = 42%).
  iv               numeric,
  -- Liquidity / interest signals.
  open_interest    integer,
  volume           integer,
  -- Last mark on the contract (mid / last / vwap fallback chain).
  last_mark        numeric,
  captured_at      timestamptz not null default now()
);

create index if not exists idx_option_greeks_captured_at
  on public.option_greeks (captured_at desc);

alter table public.option_greeks enable row level security;

-- Readable by any authenticated user (single-tenant app — trades are
-- scoped to the user already and Greeks are FK-bound to a trade row).
create policy "option_greeks readable to authenticated"
  on public.option_greeks for select
  to authenticated
  using (true);

-- Writes are service-role only (the edge function), no user mutates.


-- ─── ticker_quotes ────────────────────────────────────────────
create table if not exists public.ticker_quotes (
  ticker          text primary key,
  -- Latest spot. Polygon's lastTrade.p > lastQuote.p > day.c > prevDay.c
  -- fallback chain (matches existing refresh-prices behavior).
  spot            numeric,
  -- Day change as a percent, signed (e.g. 0.81 for +0.81%, −0.41 for down).
  day_change_pct  numeric,
  -- 1-year beta vs SPY. NULL until we wire a source (deferred to PD-2);
  -- the page falls back to 1.0 (or hides beta-weighted) when null.
  beta            numeric,
  captured_at     timestamptz not null default now()
);

create index if not exists idx_ticker_quotes_captured_at
  on public.ticker_quotes (captured_at desc);

alter table public.ticker_quotes enable row level security;

create policy "ticker_quotes readable to authenticated"
  on public.ticker_quotes for select
  to authenticated
  using (true);
