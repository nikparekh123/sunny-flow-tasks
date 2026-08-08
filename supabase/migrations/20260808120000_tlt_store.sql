/* ============================================================
   TLT book — the second instrument. Parallel `tlt_`-prefixed tables,
   mirroring the NVDA store exactly so the same screens/derivation read
   them unchanged (position/insights/peers/history via a TLTStore).

   Three groups:
   • Position + market data (tlt_option_trades … tlt_iv_daily) — fed by
     IBKR Flex sync (service-role writes; authenticated reads); empty
     until the sync routes TLT fills here.
   • tlt_macro_events — the long-end calendar, USER-editable in the app
     (authenticated read + write). Seeded with the current slate.
   • tlt_voter_bloc + tlt_bloc_meta — the committee leans, USER-owned and
     device-independent (authenticated read + write). Seeded 2026 seats.
   ============================================================ */

-- ---------- 1 · position (mirror of nvda_*) ----------
create table if not exists public.tlt_option_trades (
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
create index if not exists tlt_opt_open_idx on public.tlt_option_trades (voided_at) where voided_at is null;
create unique index if not exists tlt_opt_ibkr_idx on public.tlt_option_trades (ibkr_trade_id) where ibkr_trade_id is not null;

create table if not exists public.tlt_share_lots (
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

create table if not exists public.tlt_share_sells (
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

create table if not exists public.tlt_quote (
  ticker         text primary key,           -- TLT + IEF/SHY/TLH/AGG/LQD
  spot           numeric,
  day_change_pct numeric,
  prev_close     numeric,
  captured_at    timestamptz
);

create table if not exists public.tlt_option_marks (
  option_trade_id uuid primary key references public.tlt_option_trades(id) on delete cascade,
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

create table if not exists public.tlt_daily_closes (
  ticker      text not null,
  date        date not null,
  close_price numeric not null,
  primary key (ticker, date)
);

create table if not exists public.tlt_option_marks_eod (
  option_trade_id uuid not null references public.tlt_option_trades(id) on delete cascade,
  date        date not null,
  mark        numeric,
  delta       numeric,
  theta       numeric,
  captured_at timestamptz,
  primary key (option_trade_id, date)
);

create table if not exists public.tlt_iv_daily (
  date        date primary key,
  atm_iv      numeric,
  hv30        numeric,
  iv_52w_low  numeric,
  iv_52w_high numeric,
  captured_at timestamptz
);

-- ---------- 2 · macro events (user-editable calendar) ----------
create table if not exists public.tlt_macro_events (
  id          uuid primary key default gen_random_uuid(),
  class_key   text not null,                  -- fomc | prints | auctions | refunding | custom
  class_name  text not null,                  -- "FOMC"
  class_cat   text not null,                  -- "Rate decisions"
  event_date  date not null,
  label       text not null,                  -- "Sep 15–16"
  tag         text,                           -- "SEP · projections"
  outcome     text,                           -- what happened (past events)
  tlt_move    numeric,                        -- TLT % move (past events)
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);
create index if not exists tlt_macro_date_idx on public.tlt_macro_events (event_date);

-- ---------- 3 · voter bloc (user-owned leans, device-independent) ----------
create table if not exists public.tlt_voter_bloc (
  code        text primary key,               -- HAM, LOG, …
  name        text not null,
  seat        text not null,
  lean        int  not null default 0 check (lean between -2 and 2),
  seen        text,
  note        text,
  chair       boolean default false,
  moved       text,                           -- 'in' | 'out' | null
  sort        int not null,
  updated_at  timestamptz default now()
);
create table if not exists public.tlt_bloc_meta (
  id           int primary key default 1 check (id = 1),
  need         int not null default 7,
  verified     text,
  reverify_by  text,
  swing_window text,
  updated_at   timestamptz default now()
);

-- ---------- 4 · RLS ----------
-- position + market data: authenticated read, service-role writes (the sync).
do $$
declare t text;
begin
  foreach t in array array[
    'tlt_option_trades','tlt_share_lots','tlt_share_sells','tlt_quote',
    'tlt_option_marks','tlt_daily_closes','tlt_option_marks_eod','tlt_iv_daily'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format($p$create policy %I on public.%I for select to authenticated using (true)$p$, t||'_auth_read', t);
  end loop;
end $$;

-- user-editable tables: authenticated read AND write (the app edits directly).
do $$
declare t text;
begin
  foreach t in array array['tlt_macro_events','tlt_voter_bloc','tlt_bloc_meta'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format($p$create policy %I on public.%I for all to authenticated using (true) with check (true)$p$, t||'_auth_rw', t);
  end loop;
end $$;

-- ---------- 5 · realtime (live position tables push to the app) ----------
alter publication supabase_realtime add table
  public.tlt_quote, public.tlt_option_marks, public.tlt_option_trades,
  public.tlt_share_lots, public.tlt_share_sells;

-- ============================================================
-- SEED · the voter bloc (2026 committee) + its meta
-- ============================================================
insert into public.tlt_bloc_meta (id, need, verified, reverify_by, swing_window)
values (1, 7, 'Aug 6', 'Aug 27', 'All four move on CPI Aug 12 → PCE Aug 28.')
on conflict (id) do nothing;

insert into public.tlt_voter_bloc (code, name, seat, lean, seen, note, chair, moved, sort) values
  ('HAM','Hammack','Cleveland', 2,'Jul 30',null,false,null,0),
  ('LOG','Logan','Dallas',      2,'Jul 28',null,false,null,1),
  ('KAS','Kashkari','Minneapolis',2,'Aug 4',null,false,'in',2),
  ('WAR','Warsh','Chair',       1,'Jul 29','low-guidance',true,'in',3),
  ('PHL','Philadelphia','Philadelphia',1,'Jul 21',null,false,null,4),
  ('WIL','Williams','New York',  0,'Jul 31',null,false,null,5),
  ('JEF','Jefferson','Vice Chair',0,'Jul 22',null,false,null,6),
  ('COO','Cook','Governor',      0,'Jul 25',null,false,null,7),
  ('BAR','Barr','Supervision',   0,'Jul 18',null,false,'out',8),
  ('G1','Governor','Governor',  -1,'—',null,false,null,9),
  ('G2','Governor','Governor',  -1,'—',null,false,null,10),
  ('G3','Governor','Governor',  -2,'—',null,false,null,11)
on conflict (code) do nothing;

-- ============================================================
-- SEED · the macro calendar (current slate + each class's last print)
-- ============================================================
insert into public.tlt_macro_events (class_key, class_name, class_cat, event_date, label, tag, outcome, tlt_move) values
  -- FOMC
  ('fomc','FOMC','Rate decisions','2026-07-29','Jul 28–29','statement','Held · no cut signalled',0.8),
  ('fomc','FOMC','Rate decisions','2026-09-16','Sep 15–16','SEP · projections',null,null),
  ('fomc','FOMC','Rate decisions','2026-10-28','Oct 27–28','statement only',null,null),
  ('fomc','FOMC','Rate decisions','2026-12-09','Dec 8–9','SEP · projections',null,null),
  -- Inflation prints
  ('prints','Inflation prints','CPI and PCE','2026-07-15','Jul 15','CPI · June','Core hotter by 0.1',-1.4),
  ('prints','Inflation prints','CPI and PCE','2026-08-12','Aug 12','CPI · July',null,null),
  ('prints','Inflation prints','CPI and PCE','2026-08-28','Aug 28','Core PCE · July',null,null),
  ('prints','Inflation prints','CPI and PCE','2026-09-10','Sep 10','CPI · August',null,null),
  ('prints','Inflation prints','CPI and PCE','2026-10-13','Oct 13','CPI · September',null,null),
  -- Auctions
  ('auctions','Auctions','Long-end supply','2026-07-10','Jul 10','30-year','30-year tailed 1.2bp',-0.6),
  ('auctions','Auctions','Long-end supply','2026-08-13','Aug 13','30-year · reopening',null,null),
  ('auctions','Auctions','Long-end supply','2026-08-19','Aug 19','20-year · new issue',null,null),
  ('auctions','Auctions','Long-end supply','2026-08-20','Aug 20','30-year TIPS',null,null),
  ('auctions','Auctions','Long-end supply','2026-09-10','Sep 10','30-year · new issue',null,null),
  -- Refunding
  ('refunding','Refunding','Quarterly announcement','2026-08-05','Aug 5','Q3 refunding','Coupon sizes unchanged',1.1),
  ('refunding','Refunding','Quarterly announcement','2026-11-04','Nov 4','Q4 refunding',null,null),
  ('refunding','Refunding','Quarterly announcement','2027-02-03','Feb 3 ’27','Q1 refunding',null,null)
on conflict do nothing;
