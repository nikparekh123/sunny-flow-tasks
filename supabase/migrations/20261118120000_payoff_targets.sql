-- Payoff targets (handoff 2026-11-18, A6): a target price set on the web's Payoff, per book and name, that the
-- phone's Payoff shows (dashed line, ring, the P&L at it). Members of the book read it; only its owners set it.
create table if not exists public.payoff_targets (
  book_id text not null,
  ticker  text not null,
  price   numeric not null check (price > 0),
  set_at  timestamptz not null default now(),
  primary key (book_id, ticker)
);
alter table public.payoff_targets enable row level security;
drop policy if exists payoff_targets_read on public.payoff_targets;
create policy payoff_targets_read on public.payoff_targets for select to authenticated
  using (exists (select 1 from public.book_members m where m.book_id = payoff_targets.book_id and m.user_id = auth.uid()));
drop policy if exists payoff_targets_write on public.payoff_targets;
create policy payoff_targets_write on public.payoff_targets for all to authenticated
  using (exists (select 1 from public.book_members m where m.book_id = payoff_targets.book_id and m.user_id = auth.uid() and m.role = 'owner'))
  with check (exists (select 1 from public.book_members m where m.book_id = payoff_targets.book_id and m.user_id = auth.uid() and m.role = 'owner'));
grant select, insert, update, delete on public.payoff_targets to authenticated;
