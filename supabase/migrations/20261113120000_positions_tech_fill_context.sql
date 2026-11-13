-- Positions page data (handoff 2026-11-13-positions, Nik's answers A3, A3b and A4, 13 Nov 2026).
--
-- A3b: the 100-day average next to the 20, 50 and 200-day ones (ticker-technicals fills it on every row).
-- A3: support and resistance zones on the latest row only: swing pivots from about 3 months of daily highs and lows
--     (a high or low beyond the 3 sessions each side), merged within one band (half-width ATR(14) x 0.5),
--     strength = how many pivots merged. Up to 4 below and 4 above the last completed close.
--     [{kind:'support'|'resistance', lo, hi, mid, strength, last}]
alter table public.ticker_technicals add column if not exists sma100 numeric;
alter table public.ticker_technicals add column if not exists zones jsonb;

-- A4: where each sold leg sat when it was sold. One row per opening sale (option_trades.id), written once by the
-- option-fill-context job and never overwritten:
--   underlying  the stock price at the fill (a same-day fill: the quote nearest the execution time, else the latest)
--   iv          that strike's IV (option_chain_next mid IV for the expiry, strike and side; else the leg's own mark IV;
--               else the 30-day ATM IV)
--   td, cd      trading days after the trade date through the expiry (weekends and market_calendar closed days out),
--               and calendar days
--   z0          ln(K / underlying) / (iv x sqrt(td / 252)), signed (a sale on the expiry day uses the part of the
--               session left at the fill instead of td)
--   approx      false only for a same-day fill with the strike's own IV; true for every backfill
--   source      'fill' (same day), 'backfill' (leg_marks_daily on the trade date), 'backfill-close' (daily_closes and
--               the 30-day ATM IV on the trade date)
create table if not exists public.option_fill_context (
  option_trade_id uuid primary key references public.option_trades(id) on delete cascade,
  ticker text not null,
  side text not null check (side in ('call', 'put')),
  underlying numeric not null,
  iv numeric not null,
  td int not null,
  cd int not null,
  z0 numeric,
  approx boolean not null default true,
  source text not null,
  created_at timestamptz not null default now()
);
create index if not exists option_fill_context_ticker_idx on public.option_fill_context (ticker);

-- Members of the book read their own rows (as leg_marks_daily); only the service role writes.
alter table public.option_fill_context enable row level security;
drop policy if exists "option_fill_context: own books read" on public.option_fill_context;
create policy "option_fill_context: own books read" on public.option_fill_context
  for select to authenticated
  using (exists (select 1 from public.option_trades o where o.id = option_fill_context.option_trade_id and o.book_id in (select public.my_books())));
revoke insert, update, delete, truncate on public.option_fill_context from anon, authenticated;
grant select on public.option_fill_context to authenticated;
