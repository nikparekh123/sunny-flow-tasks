-- Try in Payoff (handoff 2026-11-24 §4): a strike tried from Intelligence (phone) or What if (web) is kept per book and
-- name and shows on both apps as a leg "from Intelligence" with a switch and an X. Members read; owners write (as
-- payoff_targets). Replaces the prototype's localStorage sunny.try186.
create table if not exists public.payoff_tries (
  book_id text not null, ticker text not null, id text not null,
  side text not null check (side in ('s','b')), ty text not null check (ty in ('c','p')),
  strike numeric not null check (strike > 0), expiry date not null, n integer not null check (n > 0),
  on_ boolean not null default true, set_at timestamptz not null default now(),
  primary key (book_id, ticker, id)
);
alter table public.payoff_tries enable row level security;
drop policy if exists payoff_tries_read on public.payoff_tries;
create policy payoff_tries_read on public.payoff_tries for select to authenticated
  using (exists (select 1 from public.book_members m where m.book_id = payoff_tries.book_id and m.user_id = auth.uid()));
drop policy if exists payoff_tries_write on public.payoff_tries;
create policy payoff_tries_write on public.payoff_tries for all to authenticated
  using (exists (select 1 from public.book_members m where m.book_id = payoff_tries.book_id and m.user_id = auth.uid() and m.role = 'owner'))
  with check (exists (select 1 from public.book_members m where m.book_id = payoff_tries.book_id and m.user_id = auth.uid() and m.role = 'owner'));
grant select, insert, update, delete on public.payoff_tries to authenticated;
