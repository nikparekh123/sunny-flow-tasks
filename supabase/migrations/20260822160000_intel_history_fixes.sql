/* ============================================================
   Two storage faults found on the first real ingest

   1. name_news failed entirely: 21000, duplicate constrained values within one
      command. The same article carries several tickers, so an article id is not
      unique per row. The key is (ticker, id).

   2. analyst_consensus is keyed on ticker alone, so every run OVERWRITES it and
      no history exists. That makes "has the street been getting more negative"
      unanswerable, which is the whole reason to have it. Keyed on
      (ticker, as_of_date) it becomes a series.

   ⚠ AND THE GENERAL POINT. Nothing is ever deleted, so everything accumulates
   from the day it is first fetched. But the FETCH window is 180 days, so
   anything older that has never been pulled is not "old data we have", it is
   data we do not have and cannot get once the subscription lapses. Same lesson
   as the option history: pull the depth while it is paid for.
   ============================================================ */

drop table if exists public.name_news;
create table public.name_news (
  ticker text not null,
  id text not null,
  published timestamptz, title text, publisher text, url text,
  updated_at timestamptz default now(),
  primary key (ticker, id)
);
create index if not exists name_news_ticker_pub_idx on public.name_news (ticker, published desc);

alter table public.analyst_consensus drop constraint if exists analyst_consensus_pkey;
alter table public.analyst_consensus
  add column if not exists as_of_date date generated always as ((as_of at time zone 'UTC')::date) stored;
alter table public.analyst_consensus add primary key (ticker, as_of_date);

comment on table public.analyst_consensus is
  'One row per ticker per DAY, not one per ticker. Overwriting it lost the '
  'series, and the direction of travel is the only trustworthy thing in it: '
  'the target itself is an all-time aggregate (NKE 91.56 against a spot of '
  '40.91 on 22 Aug).';

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='name_news') then
    execute 'alter table public.name_news enable row level security';
    execute 'create policy name_news_read on public.name_news for select to authenticated using (true)';
  end if;
end $$;

notify pgrst, 'reload schema';
