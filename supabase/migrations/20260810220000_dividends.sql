/* ============================================================
   dividends — ex-dates and cash amounts, per ticker
   ============================================================
   TLT distributes monthly, so an ex-date lands inside roughly one
   expiry in four. The drop is mechanical: the price falls by the
   distribution on the ex-date whatever the market thinks.

   That matters in two opposite directions and the planner has to
   tell them apart. Accumulating near 75, a drop that raises the
   odds of assignment is welcome — it is how the shares arrive.
   Running income at 88, the same drop is an unwanted push toward
   being assigned on stock you did not want yet.

   Once shares exist the distribution is income in its own right,
   offsetting what the protective puts cost. On 50,000 shares at a
   4% yield that is not a rounding error.

   Generic by ticker rather than tlt_*, because NVDA pays a token
   dividend too and any future position would want the same.
   ============================================================ */

create table if not exists public.dividends (
  ticker        text not null,
  ex_date       date not null,
  pay_date      date,
  record_date   date,
  declared_on   date,
  cash_amount   numeric,
  frequency     integer,              -- 12 = monthly, 4 = quarterly
  dividend_type text,                 -- CD = regular, SC = special
  source        text not null default 'polygon',
  updated_at    timestamptz not null default now(),
  primary key (ticker, ex_date)
);

create index if not exists dividends_upcoming_idx
  on public.dividends (ticker, ex_date desc);

alter table public.dividends enable row level security;

drop policy if exists dividends_read on public.dividends;
create policy dividends_read on public.dividends
  for select to authenticated using (true);

drop policy if exists dividends_write on public.dividends;
create policy dividends_write on public.dividends
  for all to service_role using (true) with check (true);
