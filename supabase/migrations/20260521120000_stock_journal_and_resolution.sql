-- Stock journal + option-resolution metadata.
--
-- Adds the data needed to:
--   1. Record manual share sales (and assignment-driven share sales)
--      via a small share_sells log.
--   2. Track HOW an option close was resolved (expired worthless,
--      rolled, assigned, manual) and snapshot share P&L on
--      assignment closes so it survives future avg_cost changes.
--   3. Accumulate realized stock P&L per position without losing
--      history when CSV uploads update qty / avg_cost.
--
-- Mental model:
--   • positions.quantity / avg_cost remain the source of truth for
--     CURRENT state of shares. CSV upserts these. Manual sells and
--     assignments mutate them.
--   • positions.realized_stock_pl is a running accumulator that
--     SURVIVES CSV upserts. Updated only by share sales / assignments.
--   • share_sells is the audit log for each manual / assignment sale.
--   • option_trades.closed_via tags how each close happened; on
--     assignment closes, share_pnl snapshots the realized stock P&L
--     at that moment.

-- ── positions: realized_stock_pl accumulator ────────────────────────
alter table public.positions
  add column if not exists realized_stock_pl numeric not null default 0;

comment on column public.positions.realized_stock_pl is
  'Running total of realized stock P&L for this ticker. Updated when '
  'shares are sold (manual or assignment). Preserved across CSV upserts.';

-- ── option_trades: resolution metadata on closes / rolls ────────────
alter table public.option_trades
  add column if not exists closed_via text
    check (closed_via in ('expired_worthless', 'rolled', 'assigned', 'manual'));

alter table public.option_trades
  add column if not exists rolled_from uuid
    references public.option_trades(id) on delete set null;

alter table public.option_trades
  add column if not exists share_pnl numeric;

comment on column public.option_trades.closed_via is
  'How the option was closed (only set on action=close rows). '
  'expired_worthless | rolled | assigned | manual.';
comment on column public.option_trades.rolled_from is
  'When this open was created by a roll, points at the original open. '
  'Only set on action=open rows.';
comment on column public.option_trades.share_pnl is
  'Snapshot of realized stock P&L from this close. Set only on '
  'assigned short-call closes; preserves the (strike − avg_cost) × shares '
  'computation at the time of assignment so future avg_cost changes '
  'cannot corrupt history.';

create index if not exists option_trades_rolled_from_idx
  on public.option_trades (rolled_from)
  where rolled_from is not null;

-- ── share_sells: manual / assignment share-sale audit log ───────────
create table if not exists public.share_sells (
  id                       uuid primary key default gen_random_uuid(),
  ticker                   text not null,
  quantity                 integer not null check (quantity > 0),
  price                    numeric not null check (price >= 0),
  trade_date               date not null,
  source                   text not null default 'manual'
                             check (source in ('manual', 'assignment')),
  -- When source='assignment', link to the option close that triggered
  -- the sale. Lets us walk back from the trades matrix to the underlying
  -- option event.
  linked_option_close_id   uuid
                             references public.option_trades(id)
                             on delete set null,
  -- Realized P&L snapshot at the moment of sale:
  --   (price − avg_cost_at_sale_time) × quantity
  -- Stored so future avg_cost changes don't rewrite history.
  realized_pl              numeric not null default 0,
  note                     text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index if not exists share_sells_ticker_idx     on public.share_sells (ticker);
create index if not exists share_sells_date_idx       on public.share_sells (trade_date desc);
create index if not exists share_sells_linked_idx
  on public.share_sells (linked_option_close_id)
  where linked_option_close_id is not null;

-- Reuse the shared updated_at trigger function from positions.
create trigger share_sells_set_updated_at
  before update on public.share_sells
  for each row execute function public.positions_set_updated_at();

-- ── RLS — same model as option_trades: authenticated full access ────
alter table public.share_sells enable row level security;

drop policy if exists "share_sells: authenticated read"   on public.share_sells;
drop policy if exists "share_sells: authenticated insert" on public.share_sells;
drop policy if exists "share_sells: authenticated update" on public.share_sells;
drop policy if exists "share_sells: authenticated delete" on public.share_sells;

create policy "share_sells: authenticated read"
  on public.share_sells for select to authenticated using (true);
create policy "share_sells: authenticated insert"
  on public.share_sells for insert to authenticated with check (true);
create policy "share_sells: authenticated update"
  on public.share_sells for update to authenticated using (true) with check (true);
create policy "share_sells: authenticated delete"
  on public.share_sells for delete to authenticated using (true);

-- Realtime so the trades matrix updates on insert.
alter publication supabase_realtime add table public.share_sells;
