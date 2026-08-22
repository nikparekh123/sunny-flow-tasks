/* ============================================================
   scanner_closes, the history the scanner already downloads and throws away

   income-scanner pulls 600 days per name on every run, uses it for the market
   day detector, realised vol, the 52-week range and the own-gap test, and then
   discards it. So questions that need history cannot be answered at all:

     how long does a name stay within 5% of its 52-week low
     what did the edge look like on the days it was cheap
     how far has an average cost fallen against how far the price fell

   Nik asked the first one and it was unanswerable. Locally there are 559 closes
   for NVDA, QQQ and SMH and about 104 for everything else, which is five months
   and cannot support a 52-week anything.

   ⚠ A SEPARATE TABLE, NOT daily_closes. That table holds 28 tickers and several
   consumers read it with a flat `limit 120` across ALL tickers (NvdaStore does
   exactly this). Adding 144 names at 600 rows each would turn a 120-row NVDA
   history into a day and a half of everything, silently. The two tables have
   different jobs: daily_closes serves the screens, this serves research.
   ============================================================ */

create table if not exists public.scanner_closes (
  ticker  text    not null,
  date    date    not null,
  close   numeric not null,
  primary key (ticker, date)
);

create index if not exists scanner_closes_ticker_date_idx
  on public.scanner_closes (ticker, date desc);

comment on table public.scanner_closes is
  'Daily closes for the scanner universe, written by income-scanner from the '
  '600-day pull it already makes. Research history; the screens read '
  'daily_closes instead.';

alter table public.scanner_closes enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='scanner_closes' and policyname='sc_auth_read') then
    create policy sc_auth_read on public.scanner_closes
      for select to authenticated using (true);
  end if;
end $$;

notify pgrst, 'reload schema';
