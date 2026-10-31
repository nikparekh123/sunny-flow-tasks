-- Book N syncs (31 Oct 2026): step 1 of the second book. Nik's cousin's IBKR account U29584055 gets its own
-- Flex token (secret IBKR_FLEX_TOKEN_N) and three queries: trades 1691893 (TCF, Today), daily 1691898 (Activity,
-- last 5 business days), account 1691900 (Activity, 30 days by day). ibkr-flex-sync and ibkr-account-sync take
-- {"book":"N"} and tag every row with it. Nothing here may move a figure of book S: every place that added the
-- whole table up now adds one book at a time.

insert into public.books (id, name, ibkr_accounts) values ('N', 'N', array['U29584055'])
on conflict (id) do update set ibkr_accounts = excluded.ibkr_accounts;

-- positions: one row per name per BOOK. Both books may hold the same shares (the sync's reconcile writes per book).
alter table public.positions drop constraint if exists positions_ticker_key;
alter table public.positions add constraint positions_book_ticker_key unique (book_id, ticker);

-- Which book a sync run was for. health-monitor and Home's freshness read book S's runs, so N's quiet successes
-- can never hide an S failure.
alter table public.ibkr_sync_runs add column if not exists book_id text not null default 'S' references public.books(id);

-- The account value per book. It summed every account in account_daily, so N's cash would have joined S's value.
-- book_id goes last (a replaced view may only add columns at the end); readers filter book_id=eq.S.
create or replace view public.account_value_daily with (security_invoker = on) as
 select report_date,
    count(*) as accounts,
    sum(nav) as nav,
    sum(cash) as cash,
    sum(stock) as stock,
    sum(options) as options,
    sum(interest_accruals) as interest_accruals,
    sum(mtm) as mtm,
    sum(deposits_withdrawals) as deposits_withdrawals,
    sum(interest) as interest,
    sum(interest_accrued) as interest_accrued,
    sum(commissions) as commissions,
    sum(other_fees) as other_fees,
    sum(commissions_mtd) as commissions_mtd,
    sum(broker_interest_mtd) as broker_interest_mtd,
    sum(coalesce(dividends, 0::numeric)) as dividends,
    book_id
   from public.account_daily
  group by book_id, report_date;

-- The LEAP mark shadow test is book S's: a contract both books hold would otherwise count twice.
create or replace view public.leap_model_vs_ibkr with (security_invoker = true) as
 select s.day,
    s.ticker,
    s.put_call,
    s.strike,
    s.expiry,
    p."position",
    p.mark_price as ibkr,
    s.bid,
    s.ask,
    s.mid,
    s.m_smooth,
    s.m_ibkr,
    s.m_smile,
    round((s.mid - p.mark_price) * p."position" * 100::numeric, 2) as err_mid,
    round((s.m_smooth - p.mark_price) * p."position" * 100::numeric, 2) as err_smooth,
    round((s.m_ibkr - p.mark_price) * p."position" * 100::numeric, 2) as err_ibkr,
    round((s.m_smile - p.mark_price) * p."position" * 100::numeric, 2) as err_smile
   from public.leap_model_shadow s
     join public.account_positions_daily p on p.report_date = s.day and p.underlying = s.ticker and p.put_call = s.put_call
       and p.strike = s.strike and p.expiry = s.expiry and p.asset_category = 'OPT'::text and p.book_id = 'S';

-- FIFO inside a book: a sale only ever consumes its own book's lots, and the zero-out baseline is each book's own.
create or replace function public.reconcile_share_fifo()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  s        record;
  l        record;
  need     numeric;
  take     numeric;
  realized numeric;
  done     integer := 0;
begin
  update public.share_lots
     set qty_remaining = qty_original
   where voided_at is null
     and qty_original is not null
     and qty_remaining is distinct from qty_original;

  for s in
    select id, book_id, ticker, quantity, price, trade_date,
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
         and book_id = s.book_id
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

  update public.share_lots sl
     set qty_remaining = 0
    from (select book_id, max(reconciled_through) as baseline
            from public.positions
           group by book_id
          having max(reconciled_through) is not null) b
   where b.book_id = sl.book_id
     and sl.voided_at is null
     and sl.qty_remaining > 0
     and not exists (
           select 1 from public.positions p
            where p.book_id = sl.book_id
              and p.ticker = sl.ticker
              and p.status = 'open'
              and coalesce(p.quantity, 0) > 0)
     and not exists (
           select 1 from public.share_lots f
            where f.book_id = sl.book_id
              and f.ticker = sl.ticker
              and f.voided_at is null
              and f.acquired_date > b.baseline);

  return done;
end $function$;

-- Expired legs close inside their own book: the same contract open in both books is two residuals, not one.
create or replace function public.close_expired_option_legs(buffer_days integer default 6)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare inserted integer;
begin
  with keyagg as (
    select book_id, ticker, option_type, direction, strike, expiry,
           sum(contracts) filter (where action='open')  as opened,
           coalesce(sum(contracts) filter (where action='close'),0) as closed
    from public.option_trades where voided_at is null
    group by book_id, ticker, option_type, direction, strike, expiry),
  residuals as (
    select book_id, ticker, option_type, direction, strike, expiry, opened-closed as residual
    from keyagg
    where expiry < current_date - make_interval(days => buffer_days) and opened-closed > 0),
  ins as (
    insert into public.option_trades
      (book_id, ticker, trade_date, action, option_type, direction, contracts, strike, premium, expiry, source, note)
    select book_id, ticker, expiry, 'close', option_type, direction, residual, strike, 0, expiry, 'expiry', 'auto-closed at expiry'
    from residuals returning 1)
  select count(*) into inserted from ins;
  return inserted;
end $function$;
