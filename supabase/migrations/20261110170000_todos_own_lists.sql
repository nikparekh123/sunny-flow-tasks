-- To do, own lists (Nik, 10 Nov 2026: "yes give him his own private list"). Nik's list stays as it was: shared by
-- his two logins (book S's owners) and seen by no one else. Any other book member (the cousin) gets a list of his
-- own that only his login can read or write; Nik does not see it either.
-- owner: null = Nik's list (book S's owners); else the one login whose own list it is. Set on insert by the trigger.

alter table public.todos add column if not exists owner uuid references auth.users(id) on delete cascade;
create index if not exists todos_owner on public.todos (owner);

create or replace function public.is_book_member() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.book_members m where m.user_id = auth.uid())
$$;

-- On insert by a signed-in login: Nik's logins write to his list (owner null), anyone else to their own.
create or replace function public.todos_touch() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.owner := case when public.is_book_s_owner() then null else auth.uid() end;
  end if;
  if new.done and (tg_op = 'INSERT' or not old.done) then new.done_at := now();
  elsif not new.done then new.done_at := null;
  end if;
  return new;
end $$;

drop policy if exists todos_s_owners on public.todos;
drop policy if exists todos_own_list on public.todos;
create policy todos_own_list on public.todos for all to authenticated
  using ((owner is null and public.is_book_s_owner()) or (owner = auth.uid() and not public.is_book_s_owner() and public.is_book_member()))
  with check ((owner is null and public.is_book_s_owner()) or (owner = auth.uid() and not public.is_book_s_owner() and public.is_book_member()));

-- Reminders: Nik's to book S as before; an own list's to its login alone (meta.user_id, which apns-deliver v18
-- honours: Nik is a member of book N too, so a book N alert would reach his phone).
create or replace function public.todo_reminders() returns integer language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'America/New_York')::date; n integer;
begin
  if extract(hour from now() at time zone 'America/New_York') <> 8 then return 0; end if;
  insert into public.alert_dispatch (category, dedup_key, title, body, deep_link, book_id, meta)
  select 'todo', 'todo:' || t.id || ':' || d, 'To do · today', t.text, 'sunny://todo',
         coalesce((select m.book_id from public.book_members m where m.user_id = t.owner order by m.book_id limit 1), 'S'),
         case when t.owner is null then jsonb_build_object('todo_id', t.id) else jsonb_build_object('todo_id', t.id, 'user_id', t.owner) end
  from public.todos t where not t.done and t.due = d
  on conflict (dedup_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.todo_reminders() from public, anon, authenticated;
