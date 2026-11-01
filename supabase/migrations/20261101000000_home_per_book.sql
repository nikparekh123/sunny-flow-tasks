-- One Home per book (31 Oct 2026, step 4 of the cousin's book).
--
-- sunny-home now builds one book per call (the cron sends nothing for book S,
-- {"book":"N"} for the cousin's) and each book's side rows carry its book_id.
-- Two keys still allowed one row per week or day for everyone; they become
-- per book. Applied in two halves around the sunny-home deploy, so the old code
-- (on_conflict kind,period_start / day) never met a missing key.

-- 1. Before the deploy: the per-book keys, beside the old ones.
create unique index if not exists reports_book_kind_period_key
  on public.reports (book_id, kind, period_start);
create unique index if not exists account_history_book_day_key
  on public.account_history (book_id, day);

-- 1b. home_snapshot was one row (check id = 1); book_id (unique) now keeps one per book.
alter table public.home_snapshot drop constraint if exists home_snapshot_id_check;

-- 2. After the deploy: the old keys go; (book_id, day) is the history's key.
alter table public.reports drop constraint if exists reports_kind_period_start_key;
alter table public.account_history drop constraint if exists account_history_pkey;
alter table public.account_history
  add constraint account_history_pkey primary key using index account_history_book_day_key;
alter table public.reports
  add constraint reports_book_kind_period_key unique using index reports_book_kind_period_key;

-- 3. Book N's Home: every minute like book S's (same schedule as sunny-home),
--    and its account history after the IBKR daily account sync (10:35, 13:35).
select cron.schedule('sunny-home-N', '* * * * *',
  $$SELECT public.cron_invoke_function_body('sunny-home', '{"book":"N"}'::jsonb)$$);
select cron.schedule('account-history-daily-N', '45 10,13 * * *',
  $$SELECT public.cron_invoke_function_body('sunny-home', '{"mode":"history","book":"N"}'::jsonb, 120000)$$);
