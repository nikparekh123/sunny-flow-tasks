-- Sunny search log (step 5, 27 Oct 2026): every question asked, its answer, whether its figures checked against the
-- data it read, what it cost, and Nik's thumbs. sunny-search writes it with the service key; members of a book can
-- read their own book's rows. search_misses is the weekly review: the last 7 days' questions that could not be
-- answered, failed the number check, got a thumbs down or "not what I asked", or came back with no card.
create table if not exists public.search_log (
  id          bigserial   primary key,
  book_id     text        not null references public.books(id),
  user_id     uuid,
  at          timestamptz not null default now(),
  question    text        not null,
  thread_len  int         not null default 0,
  deep        boolean     not null default false,
  model       text,
  effort      text,
  answer      text,
  big         jsonb,
  cards       text[],
  lookups     jsonb,
  can_answer  boolean,
  check_ok    boolean,
  unverified  text[],
  retried     boolean     not null default false,
  ms          int,
  tokens      jsonb,
  cost_usd    numeric(10, 5),
  feedback    text check (feedback in ('up', 'down', 'not_asked')),
  feedback_at timestamptz
);
create index if not exists search_log_book_at on public.search_log (book_id, at desc);
alter table public.search_log enable row level security;
drop policy if exists "search_log: own books read" on public.search_log;
create policy "search_log: own books read" on public.search_log for select to authenticated
  using (book_id in (select public.my_books()));

create or replace view public.search_misses with (security_invoker = true) as
  select id, at, question, answer, can_answer, check_ok, unverified, feedback, cards, ms, cost_usd
  from public.search_log
  where at > now() - interval '7 days'
    and (can_answer is false or check_ok is false or feedback in ('down', 'not_asked') or coalesce(array_length(cards, 1), 0) = 0)
  order by at desc;
