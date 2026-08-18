/* ============================================================
   reconcile_share_fifo(), pass 3: IBKR decides whether a ticker is held

   INTU and LULU each sold MORE than the ledger says they ever owned, by
   exactly the amount that reappears as a buy three days later:

       INTU   seed lots 400    sold 600 on 17 Jul    bought 200 on 20 Jul
       LULU   seed lots 1,000  sold 1,500 on 17 Jul  bought 500 on 20 Jul

   The 'seed' rows are hand-entered pre-July history and they under-record what
   was actually held. The IBKR rows from July onward are complete. FIFO cannot
   produce a correct share count from a ledger that is missing buys, and no
   change to the date guard fixes it: relaxing the guard zeroes INTU and LULU
   correctly but also drops NKE from 2,000 to 1,500, and 2,000 is what IBKR
   reports. The same shape needs opposite answers, so the ledger alone cannot
   decide it.

   IBKR's OpenPositions can. This is the narrow version of that idea: if IBKR
   does not report a ticker as held, it is not held, and its lots go to zero.
   It does NOT touch counts that merely disagree, so NKE keeps its 2,000 and
   FIFO still owns every number it is capable of owning.

   Two guards, because zeroing shares is the one mistake worth being paranoid
   about:

     1. Nothing happens unless positions carries a reconciled_through date. An
        empty or half-written positions table must never wipe the book, the
        same guard reconcilePositions already uses.

     2. A ticker with ANY lot acquired after that date is skipped entirely.
        positions is T+1, so shares bought today are invisible to it, and
        without this a same-day buy would be erased the moment it landed.
   ============================================================ */

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
  baseline date;
begin
  -- Pass 1. Every lot back to what was actually bought.
  update public.share_lots
     set qty_remaining = qty_original
   where voided_at is null
     and qty_original is not null
     and qty_remaining is distinct from qty_original;

  -- Pass 2. Replay every sell, oldest first, consuming lots FIFO.
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

    update public.share_sells
       set realized_pl = case when s.src = 'ibkr' then realized_pl else realized end,
           fifo_reconciled_at = now()
     where id = s.id;

    done := done + 1;
  end loop;

  /* Pass 3. A ticker IBKR does not report as held is not held. Only reached
     when the whole of that ticker's lot history predates IBKR's last snapshot,
     so nothing bought since it can be caught by this. */
  select max(reconciled_through) into baseline from public.positions;

  if baseline is not null then
    /* Alias sl, NOT l. `l` is already a plpgsql RECORD variable, declared for
       pass 2's inner loop, and inside a function the variable wins over a table
       alias of the same name: `l.voided_at` resolved against the record and
       threw 42703 "record l has no field voided_at" at runtime. The CREATE
       succeeded, so it only failed when the function was actually called. */
    update public.share_lots sl
       set qty_remaining = 0
     where sl.voided_at is null
       and sl.qty_remaining > 0
       and not exists (
             select 1 from public.positions p
              where p.ticker = sl.ticker
                and p.status = 'open'
                and coalesce(p.quantity, 0) > 0)
       and not exists (
             select 1 from public.share_lots f
              where f.ticker = sl.ticker
                and f.voided_at is null
                and f.acquired_date > baseline);
  end if;

  return done;
end $$;

comment on function public.reconcile_share_fifo() is
  'Rebuilds share_lots.qty_remaining from qty_original by replaying every '
  'share_sell FIFO in date order, then zeroes any ticker IBKR does not report '
  'as held. Idempotent by construction. Recomputes realized_pl only where '
  'realized_pl_source is not ''ibkr''.';

select public.reconcile_share_fifo() as sells_replayed;
select public.nvda_mirror();
select public.tlt_mirror();

select l.ticker,
       sum(l.qty_remaining) as held_now,
       coalesce(max(p.quantity), 0) as ibkr_says,
       case when sum(l.qty_remaining) = coalesce(max(p.quantity), 0)
            then 'ok' else 'CHECK' end as verdict
  from public.share_lots l
  left join public.positions p
         on p.ticker = l.ticker and p.status = 'open'
 where l.voided_at is null
 group by l.ticker
having sum(l.qty_remaining) > 0 or coalesce(max(p.quantity), 0) > 0
 order by 1;
