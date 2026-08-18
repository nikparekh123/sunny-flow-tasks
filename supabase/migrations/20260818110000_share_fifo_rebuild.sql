/* ============================================================
   reconcile_share_fifo(), rebuild instead of increment

   THE BUG
   The old function did two jobs in one loop, behind one gate:

       WHERE fifo_reconciled_at IS NULL

   It consumed share_lots.qty_remaining AND booked realized_pl together. Then
   the realized-P&L fix taught upsertStock to import IBKR's own fifoPnlRealized
   and stamp fifo_reconciled_at on ingest, so the reconcile would leave the
   number alone. That worked for the number and silently switched off lot
   consumption for every sell IBKR had already priced.

   NVDA, 2026-08-18: 10,700 shares bought, 9,700 consumed, 1,000 stranded. The
   stranded 1,000 is exactly the 900 + 100 sold on 17 Aug, which arrived first
   through the overnight Daily Flex (pre-stamped, never consumed). The 14 Aug
   sells arrived intraday, were consumed normally, and were only re-stamped
   later. IBKR reports the account flat in NVDA; the app showed 1,000 shares.

   WHY REBUILD AND NOT A SECOND STAMP
   The obvious repair is a separate lots_consumed_at column. It cannot be
   seeded safely: a sell ingested intraday and later re-written by the Daily
   Flex is byte-for-byte indistinguishable from one never consumed, because the
   sync overwrites note and fifo_reconciled_at on update. Seeding from either
   would have double-consumed the 14 Aug rows and destroyed 6,500 real shares.

   So the function now resets every lot to qty_original and replays the whole
   sell history FIFO in date order. It cannot double-count by construction, it
   is idempotent by construction, and it self-heals any drift that already
   exists. A plpgsql function is one transaction, so no reader ever observes
   the reset state. The book is small enough that a full replay is cheap.

   realized_pl is now OWNED by whoever priced it. IBKR's fifoPnlRealized is
   authoritative and is never overwritten, because our local FIFO genuinely
   cannot rebuild the basis of an assignment call-away whose lots are gone.
   Everything else is recomputed. realized_pl_source records which.
   ============================================================ */

-- ── 1 · who priced this sell ───────────────────────────────────────────────
alter table public.share_sells
  add column if not exists realized_pl_source text;

comment on column public.share_sells.realized_pl_source is
  'ibkr = realized_pl came from IBKR fifoPnlRealized and is authoritative; '
  'fifo = computed locally by reconcile_share_fifo() and safe to recompute.';

/* Seeded from the note the sync writes, which is a reliable record of who
   priced the row (unlike fifo_reconciled_at, which says nothing about whether
   the lots were ever consumed). Going forward upsertStock sets it explicitly. */
update public.share_sells
   set realized_pl_source = case
         when note like '%fifoPnlRealized%' then 'ibkr'
         else 'fifo'
       end
 where realized_pl_source is null;

-- ── 3 · the function ───────────────────────────────────────────────────────
create or replace function public.reconcile_share_fifo() returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  s        record;
  l        record;
  need     numeric;
  take     numeric;
  realized numeric;
  done     integer := 0;
begin
  /* Pass 1. Every lot back to what was actually bought. This is the whole
     difference from the old version: consumption is derived fresh from the
     sell history every run, never accumulated across runs. */
  update public.share_lots
     set qty_remaining = qty_original
   where voided_at is null
     and qty_original is not null
     and qty_remaining is distinct from qty_original;

  /* Pass 2. Replay every sell, oldest first, consuming lots FIFO. No
     fifo_reconciled_at gate: a rebuild must see the complete history or it is
     not a rebuild. */
  for s in
    select id, ticker, quantity, price, trade_date,
           coalesce(realized_pl_source, 'fifo') as src
      from public.share_sells
     where voided_at is null
     order by trade_date, created_at
  loop
    need     := s.quantity;
    realized := 0;

    for l in
      select id, qty_remaining, cost_per_share
        from public.share_lots
       where ticker = s.ticker
         and voided_at is null
         and qty_remaining > 0
         and acquired_date <= s.trade_date
       order by acquired_date, fifo_order
    loop
      exit when need <= 0;
      take := least(need, l.qty_remaining);

      update public.share_lots
         set qty_remaining = qty_remaining - take
       where id = l.id;

      realized := realized + (s.price - l.cost_per_share) * take;
      need     := need - take;
    end loop;

    /* IBKR's number stands. Ours is rewritten. A sell whose lots predate the
       ledger leaves need > 0 and simply consumes what exists, which is why the
       local figure must never overwrite an authoritative one. */
    update public.share_sells
       set realized_pl = case when s.src = 'ibkr' then realized_pl else realized end,
           fifo_reconciled_at = now()
     where id = s.id;

    done := done + 1;
  end loop;

  return done;
end $$;

comment on function public.reconcile_share_fifo() is
  'Rebuilds share_lots.qty_remaining from qty_original by replaying every '
  'share_sell FIFO in date order. Idempotent by construction. Recomputes '
  'realized_pl only where realized_pl_source is not ''ibkr''.';

-- ── 4 · run it, then push the result into the app's mirrors ────────────────
select public.reconcile_share_fifo() as sells_replayed;

select public.nvda_mirror();
select public.tlt_mirror();

/* ── 5 · the arithmetic, checked ─────────────────────────────────────────
   held_now must equal should_be on every row. Anything else means the replay
   disagrees with the sell history and must not be trusted. Before this ran:
   NVDA held 1,000 against 10,700 bought, TLT held 1,100 against 1,100. */
select l.ticker,
       l.ever_bought,
       coalesce(s.ever_sold, 0)                  as ever_sold,
       l.held_now,
       l.ever_bought - coalesce(s.ever_sold, 0)  as should_be,
       case when l.held_now = l.ever_bought - coalesce(s.ever_sold, 0)
            then 'ok' else 'MISMATCH' end        as verdict
  from (select ticker,
               sum(qty_original)  as ever_bought,
               sum(qty_remaining) as held_now
          from public.share_lots
         where voided_at is null
         group by ticker) l
  left join (select ticker, sum(quantity) as ever_sold
               from public.share_sells
              where voided_at is null
              group by ticker) s on s.ticker = l.ticker
 order by 1;
