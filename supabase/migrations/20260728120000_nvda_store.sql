/* ============================================================
   NVDA strategy store — greenfield. New `nvda_`-prefixed tables in
   public (no schema-exposure config needed; nothing overlaps the
   legacy 17-ticker book). Seeded from NVDA rows dated >= 2026-07-01.
   The new app + realtime + sync read/write ONLY these tables.

   Design decisions:
   • Position tables are NVDA-only (no ticker column). closes_trade_id
     / rolled_from are plain uuids (no self-FK) so a Jul-1 seed can't
     fail on a close that points at a pre-Jul open.
   • Latest-only realtime marks (60s upsert) + a daily EOD leg snapshot
     for the by-source history chart.
   • RLS: authenticated reads; edge functions write via service role.
   • The live tables are added to the realtime publication so the app
     subscribes instead of polling.
   ============================================================ */

-- ---------- 1 · position ----------
create table if not exists public.nvda_option_trades (
  id             uuid primary key default gen_random_uuid(),
  trade_date     date not null,
  action         text not null check (action in ('open','close')),
  option_type    text not null check (option_type in ('call','put')),
  direction      text not null check (direction in ('long','short')),
  contracts      numeric not null,
  strike         numeric not null,
  premium        numeric not null,
  expiry         date not null,
  closes_trade_id uuid,
  rolled_from    uuid,
  closed_via     text,
  share_pnl      numeric,
  source         text,
  ibkr_trade_id  text,
  executed_at    timestamptz,
  last_synced_at timestamptz,
  voided_at      timestamptz,
  created_at     timestamptz default now()
);
create index if not exists nvda_opt_open_idx on public.nvda_option_trades (voided_at) where voided_at is null;
create unique index if not exists nvda_opt_ibkr_idx on public.nvda_option_trades (ibkr_trade_id) where ibkr_trade_id is not null;

create table if not exists public.nvda_share_lots (
  id             uuid primary key default gen_random_uuid(),
  acquired_date  date not null,
  fifo_order     int not null,
  qty_original   numeric not null,
  qty_remaining  numeric not null,
  cost_per_share numeric not null,
  source         text,
  ibkr_trade_id  text,
  executed_at    timestamptz,
  last_synced_at timestamptz,
  voided_at      timestamptz,
  created_at     timestamptz default now()
);

create table if not exists public.nvda_share_sells (
  id             uuid primary key default gen_random_uuid(),
  trade_date     date not null,
  quantity       numeric not null,
  price          numeric not null,
  realized_pl    numeric default 0,
  fifo_reconciled_at timestamptz,
  source         text,
  ibkr_trade_id  text,
  executed_at    timestamptz,
  last_synced_at timestamptz,
  voided_at      timestamptz,
  created_at     timestamptz default now()
);

-- ---------- 2 · realtime market data (60s, latest-only) ----------
create table if not exists public.nvda_quote (
  ticker         text primary key,          -- NVDA + peers/ETFs
  spot           numeric,
  day_change_pct numeric,
  prev_close     numeric,
  captured_at    timestamptz
);

create table if not exists public.nvda_option_marks (
  option_trade_id uuid primary key references public.nvda_option_trades(id) on delete cascade,
  mark           numeric,
  delta          numeric,
  gamma          numeric,
  theta          numeric,
  vega           numeric,
  iv             numeric,
  open_interest  int,
  volume         int,
  captured_at    timestamptz
);

-- ---------- 3 · daily closes (peers 5-session) + EOD leg marks (history) ----------
create table if not exists public.nvda_daily_closes (
  ticker      text not null,
  date        date not null,
  close_price numeric not null,
  primary key (ticker, date)
);

create table if not exists public.nvda_option_marks_eod (
  option_trade_id uuid not null references public.nvda_option_trades(id) on delete cascade,
  date        date not null,
  mark        numeric,
  delta       numeric,
  theta       numeric,
  captured_at timestamptz,
  primary key (option_trade_id, date)
);

-- ---------- 4 · seller-score inputs (daily) ----------
create table if not exists public.nvda_iv_daily (
  date        date primary key,
  atm_iv      numeric,
  hv30        numeric,
  iv_52w_low  numeric,
  iv_52w_high numeric,
  captured_at timestamptz
);

-- ---------- 5 · events (Macro / Earnings / Corporate) ----------
create table if not exists public.nvda_events (
  id          uuid primary key default gen_random_uuid(),
  event_date  date not null,
  event_time  text,                          -- 'AMC' | '14:00' | '—'
  category    text not null check (category in ('Macro','Earnings','Corporate')),
  weight      text not null check (weight in ('high','med','low')),
  title       text not null,
  line        text,
  note        text,
  mine        boolean default false,
  stats       jsonb default '[]'::jsonb,     -- exactly 3: [{"k":..,"v":..}, ...]
  created_at  timestamptz default now()
);
create index if not exists nvda_events_date_idx on public.nvda_events (event_date);

-- ---------- 6 · RLS (authenticated read; service role writes) ----------
do $$
declare t text;
begin
  foreach t in array array[
    'nvda_option_trades','nvda_share_lots','nvda_share_sells','nvda_quote',
    'nvda_option_marks','nvda_daily_closes','nvda_option_marks_eod','nvda_iv_daily','nvda_events'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format($p$create policy %I on public.%I for select to authenticated using (true)$p$, t||'_auth_read', t);
  end loop;
end $$;

-- ---------- 7 · realtime publication (live tables push to the app) ----------
alter publication supabase_realtime add table
  public.nvda_quote, public.nvda_option_marks, public.nvda_option_trades,
  public.nvda_share_lots, public.nvda_share_sells;

-- ============================================================
-- SEED · copy NVDA rows dated >= 2026-07-01 from the legacy book
-- (ids preserved so closes_trade_id / rolled_from stay consistent).
-- ============================================================
insert into public.nvda_option_trades
  (id, trade_date, action, option_type, direction, contracts, strike, premium, expiry,
   closes_trade_id, rolled_from, closed_via, share_pnl, source, ibkr_trade_id,
   executed_at, last_synced_at, voided_at)
select id, trade_date, action, option_type, direction, contracts, strike, premium, expiry,
   closes_trade_id, rolled_from, closed_via, share_pnl, source, ibkr_trade_id,
   executed_at, last_synced_at, voided_at
from public.option_trades
where ticker = 'NVDA' and trade_date >= '2026-07-01'
on conflict (id) do nothing;

insert into public.nvda_share_lots
  (id, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share,
   source, ibkr_trade_id, executed_at, last_synced_at, voided_at)
select id, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share,
   source, ibkr_trade_id, executed_at, last_synced_at, voided_at
from public.share_lots
where ticker = 'NVDA' and acquired_date >= '2026-07-01'
on conflict (id) do nothing;

insert into public.nvda_share_sells
  (id, trade_date, quantity, price, realized_pl, fifo_reconciled_at,
   source, ibkr_trade_id, executed_at, last_synced_at, voided_at)
select id, trade_date, quantity, price, coalesce(realized_pl,0), fifo_reconciled_at,
   source, ibkr_trade_id, executed_at, last_synced_at, voided_at
from public.share_sells
where ticker = 'NVDA' and trade_date >= '2026-07-01'
on conflict (id) do nothing;

-- seed NVDA daily closes (for the self 5-session card) from Jul 1
insert into public.nvda_daily_closes (ticker, date, close_price)
select ticker, date, close_price from public.daily_closes
where ticker in ('NVDA','QQQ','SPY','SMH','AVGO','AMD','ARM','INTC') and date >= '2026-06-01'
on conflict (ticker, date) do nothing;

-- ---------- 8 · first real event: NVDA Q2 FY27 earnings ----------
insert into public.nvda_events (event_date, event_time, category, weight, title, line, note, mine, stats)
values (
  '2026-08-26', 'AMC', 'Earnings', 'high',
  'NVIDIA · Q2 FY27 results',
  'The print the whole book is positioned around',
  'Consensus EPS ~$2.08 on ~$91.82B revenue. The Oct and Jan puts are the floor through it; stop selling the weeklies the week of.',
  true,
  '[{"k":"Est. EPS","v":"$2.08"},{"k":"Est. revenue","v":"$91.82B"},{"k":"Your exposure","v":"Direct"}]'::jsonb
)
on conflict do nothing;
