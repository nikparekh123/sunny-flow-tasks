-- To do for owners only (31 Oct 2026, step 3 of the cousin's book).
--
-- Nik: his cousin (a viewer of book N) must not see To do, anywhere. sunny-home
-- now splits what it builds (forOwners): everything that says what to trade
-- (the To do face, the Insights verdict, chips and order counts, the Gamma
-- page's plan and hedges, each name's write plan) goes here, one row per book,
-- and RLS lets only the book's owners read it. The app and sunny-search lay it
-- back over home_snapshot for an owner. A book with a viewer gets a snapshot
-- with none of it, so a viewer's phone never receives an order.
--
-- Only the service role writes (no insert or update policy).

create table if not exists public.home_todo (
  book_id  text primary key references public.books (id),
  payload  jsonb not null,
  built_at timestamptz,
  build    text
);

alter table public.home_todo enable row level security;

revoke all on public.home_todo from anon, authenticated;
grant select on public.home_todo to authenticated;

drop policy if exists "home_todo: owners read" on public.home_todo;
create policy "home_todo: owners read" on public.home_todo
  for select to authenticated
  using (book_id in (select public.my_owned_books()));
