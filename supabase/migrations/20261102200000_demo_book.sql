-- The demo book D (2 Nov 2026). Nik wants to show his cousin a full app before the cousin's own book N has a trade,
-- and chose to point the cousin's login at the demo until then ("Point his own code at the demo").
--
-- Why a book of its own and not samples in N: ibkr-flex-sync audits N's legs against IBKR every night and would raise
-- "Book N's option book does not reconcile" for every made-up leg, and N's NAV comes from IBKR ($50K cash), so made-up
-- legs would sit beside a value that does not hold them. D has no IBKR feed at all, so nothing ever checks it.
--
-- What it holds: $50,000 on 29 Oct (the day N was funded), traded the way Nik trades, at real prices. NKE and UBER:
-- LEAPS, hedge calls, insurance puts and weekly calls sold; the Oct 30 calls rolled (NKE bought back, UBER expired).
-- Every open price is that contract's IBKR mark on the day before; the daily values use real marks (seeded from the
-- same contracts in book S for 29-30 Oct, then mp-refresh marks D's own legs like any other).
--
-- demo_book_roll() writes D's IBKR-shaped day (account_daily + account_positions_daily) for each day book S has a
-- full IBKR report and D does not, once D's legs have that day's marks; cron demo-book-roll runs it after S's sync.
--
-- To hand the cousin his real book back, one line:
--   update book_members set book_id = 'N' where book_id = 'D'
--     and user_id = (select id from auth.users where email = 'book-n@sunnyfi.co');

insert into public.books (id, name, ibkr_accounts) values ('D', 'Demo', '{}') on conflict (id) do nothing;

do $$
declare a4 uuid := gen_random_uuid(); b4 uuid := gen_random_uuid();
begin
  if exists (select 1 from option_trades where book_id = 'D') then return; end if;
  insert into option_trades (id, book_id, source, note, ticker, trade_date, executed_at, action, option_type, direction,
                             contracts, strike, premium, expiry, commission, net_cash, closes_trade_id, rolled_from, closed_via)
  select coalesce(t.id, gen_random_uuid()), 'D', 'seed', 'Demo book sample (2 Nov 2026)', t.tk, t.d::date, t.at::timestamptz,
         t.act, t.ty, t.dir, t.n, t.k, t.px, t.exp::date, round(0.65 * t.n, 2),
         round((case when (t.act = 'open') = (t.dir = 'short') then 1 else -1 end) * t.px * t.n * 100 - 0.65 * t.n, 2),
         t.closes, t.rolled, t.via
  from (values
    -- 29 Oct: the positions, at 28 Oct's marks, and the calls for the 30th
    (null::uuid, 'NKE',  '2026-10-29', '2026-10-29 14:05+00', 'open',  'call', 'long',  20, 30.0, 10.45, '2028-01-21', null::uuid, null::uuid, null::text),
    (null,       'NKE',  '2026-10-29', '2026-10-29 14:06+00', 'open',  'call', 'long',   6, 42.5,  1.15, '2027-01-15', null, null, null),
    (null,       'NKE',  '2026-10-29', '2026-10-29 14:07+00', 'open',  'put',  'long',  10, 32.5,  0.95, '2027-01-15', null, null, null),
    (a4,         'NKE',  '2026-10-29', '2026-10-29 14:08+00', 'open',  'call', 'short', 20, 38.0,  0.45, '2026-10-30', null, null, null),
    (null,       'UBER', '2026-10-29', '2026-10-29 14:10+00', 'open',  'call', 'long',   8, 65.0, 18.90, '2029-01-19', null, null, null),
    (null,       'UBER', '2026-10-29', '2026-10-29 14:11+00', 'open',  'call', 'long',   6, 80.0,  0.87, '2027-01-15', null, null, null),
    (null,       'UBER', '2026-10-29', '2026-10-29 14:12+00', 'open',  'put',  'long',   3, 65.0,  3.90, '2027-01-15', null, null, null),
    (b4,         'UBER', '2026-10-29', '2026-10-29 14:13+00', 'open',  'call', 'short',  8, 68.0,  0.15, '2026-10-30', null, null, null),
    -- 30 Oct: NKE's calls bought back and rolled a week; UBER's expire; next week's calls sold
    (null,       'NKE',  '2026-10-30', '2026-10-30 19:40+00', 'close', 'call', 'short', 20, 38.0,  0.80, '2026-10-30', a4,   null, 'rolled'),
    (null,       'NKE',  '2026-10-30', '2026-10-30 19:41+00', 'open',  'call', 'short', 20, 39.0,  0.67, '2026-11-06', null, a4,   null),
    (null,       'UBER', '2026-10-30', '2026-10-30 19:45+00', 'open',  'call', 'short',  8, 66.0,  2.20, '2026-11-06', null, b4,   null)
  ) as t(id, tk, d, at, act, ty, dir, n, k, px, exp, closes, rolled, via);
end $$;

-- 29-30 Oct marks for D's legs: the same contracts' daily marks in book S.
insert into public.leg_marks_daily (option_trade_id, day, mark, iv, delta, gamma, theta, vega, underlying, captured_at)
select distinct on (x.id, l.day) x.id, l.day, l.mark, l.iv, l.delta, l.gamma, l.theta, l.vega, l.underlying, l.captured_at
from option_trades x
join option_trades s on s.book_id = 'S' and s.ticker = x.ticker and s.option_type = x.option_type
                    and s.strike = x.strike and s.expiry = x.expiry
join leg_marks_daily l on l.option_trade_id = s.id and l.day >= x.trade_date and l.day <= '2026-10-30'
where x.book_id = 'D'
order by x.id, l.day, l.captured_at desc
on conflict (option_trade_id, day) do nothing;

/* D's IBKR-shaped days. A day is written once every leg open that night has its mark; the cash is the $50,000 deposit
   plus every trade's net cash to that day; an expired leg drops out on its expiry day, as in IBKR's report. */
create or replace function public.demo_book_roll() returns int
language plpgsql security definer set search_path = public as $$
declare d date; n int := 0; missing int; cash numeric; opts numeric; prev numeric; comm numeric; comm_mtd numeric;
begin
  for d in
    select report_date from account_daily where book_id = 'S' and report_date >= '2026-10-29'
    group by report_date having count(*) >= 2
    except select report_date from account_daily where book_id = 'D'
    order by 1
  loop
    create temp table if not exists demo_legs (ticker text, option_type text, strike numeric, expiry date, net int, avg numeric, mark numeric) on commit drop;
    truncate demo_legs;
    insert into demo_legs
    select o.ticker, o.option_type, o.strike, o.expiry,
      sum(case when (o.action = 'open') = (o.direction = 'long') then 1 else -1 end * o.contracts)::int,
      sum(case when o.action = 'open' then o.premium * o.contracts end) / nullif(sum(case when o.action = 'open' then o.contracts end), 0),
      (select l.mark from leg_marks_daily l join option_trades x on x.id = l.option_trade_id
        where x.book_id = 'D' and x.ticker = o.ticker and x.option_type = o.option_type and x.strike = o.strike
          and x.expiry = o.expiry and l.day = d and l.mark is not null
        order by l.captured_at desc limit 1)
    from option_trades o
    where o.book_id = 'D' and o.voided_at is null and o.trade_date <= d and o.expiry > d
    group by o.ticker, o.option_type, o.strike, o.expiry;
    delete from demo_legs where net = 0;
    select count(*) into missing from demo_legs where mark is null;
    exit when missing > 0;   -- marks not captured yet: try again on the next run

    delete from account_positions_daily where book_id = 'D' and report_date = d;
    insert into account_positions_daily (account_id, report_date, conid, symbol, underlying, asset_category, put_call, strike,
      expiry, multiplier, position, mark_price, position_value, cost_basis_money, fifo_pnl_unrealized, synced_at, book_id)
    select 'DEMO', d, 'DEMO-' || ticker || '-' || upper(left(option_type, 1)) || '-' || strike || '-' || expiry,
      rpad(ticker, 6) || to_char(expiry, 'YYMMDD') || upper(left(option_type, 1)) || lpad((strike * 1000)::bigint::text, 8, '0'),
      ticker, 'OPT', upper(left(option_type, 1)), strike, expiry, 100, net, mark,
      round(net * mark * 100, 2), round(net * avg * 100, 2), round(net * (mark - avg) * 100, 2), now(), 'D'
    from demo_legs;

    select 50000 + coalesce(sum(net_cash), 0), coalesce(sum(commission) filter (where trade_date = d), 0),
           coalesce(sum(commission) filter (where date_trunc('month', trade_date) = date_trunc('month', d)), 0)
      into cash, comm, comm_mtd
      from option_trades where book_id = 'D' and voided_at is null and trade_date <= d;
    select coalesce(sum(net * mark * 100), 0) into opts from demo_legs;
    select nav into prev from account_daily where book_id = 'D' and report_date < d order by report_date desc limit 1;
    insert into account_daily (account_id, report_date, nav, cash, stock, options, interest_accruals, starting_value, mtm,
      realized, change_in_unrealized, deposits_withdrawals, dividends, interest, change_in_interest_accruals, commissions,
      other_fees, twr, interest_accrued, commissions_mtd, broker_interest_mtd, other_fees_mtd, synced_at, book_id)
    values ('DEMO', d, round(cash + opts, 2), round(cash, 2), 0, round(opts, 2), 0, coalesce(prev, 0), 0, 0, 0,
      case when prev is null then 50000 else 0 end, 0, 0, 0, comm, 0, 0, 0, comm_mtd, 0, 0, now(), 'D');
    n := n + 1;
  end loop;
  if n > 0 then
    insert into ibkr_sync_runs (status, trigger, finished_at, notes, book_id)
    values ('success', 'manual', now(), 'demo_book_roll: ' || n || ' day(s)', 'D');
  end if;
  return n;
end $$;
revoke all on function public.demo_book_roll() from public, anon, authenticated;

select public.demo_book_roll();

select cron.schedule('demo-book-roll', '41 10,13 * * *', 'select public.demo_book_roll()');
select cron.schedule('sunny-home-D', '* * * * *',
  $$SELECT public.cron_invoke_function_body('sunny-home', '{"book":"D"}'::jsonb)$$);
select cron.schedule('account-history-daily-D', '46 10,13 * * *',
  $$SELECT public.cron_invoke_function_body('sunny-home', '{"mode":"history","book":"D"}'::jsonb, 120000)$$);
