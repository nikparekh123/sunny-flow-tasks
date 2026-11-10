-- To do (handoff 2026-11-10-todo): Nik's own notes, one list for the app and the web.
-- Nik, 10 Nov 2026: "only for me to see, not Nicolay". The list belongs to book S's owners (Nik's two logins),
-- so both his logins share it and the cousin's login (book N only) can neither read nor write it.
-- Answers: done items kept forever; "today" is New York's day; a push at 8:00 AM New York on the due day.

create table if not exists public.todos (
  id          uuid primary key default gen_random_uuid(),
  text        text not null check (length(btrim(text)) between 1 and 500),
  due         date,
  note        text not null default '' check (length(note) <= 2000),
  done        boolean not null default false,
  done_at     timestamptz,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists todos_open on public.todos (done, due);

-- done_at follows done; updated_at on every change.
create or replace function public.todos_touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.done and (tg_op = 'INSERT' or not old.done) then new.done_at := now();
  elsif not new.done then new.done_at := null;
  end if;
  return new;
end $$;
drop trigger if exists todos_touch on public.todos;
create trigger todos_touch before insert or update on public.todos for each row execute function public.todos_touch();

-- Only an owner of book S.
create or replace function public.is_book_s_owner() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.book_members m where m.user_id = auth.uid() and m.book_id = 'S' and m.role = 'owner')
$$;
alter table public.todos enable row level security;
drop policy if exists todos_s_owners on public.todos;
create policy todos_s_owners on public.todos for all to authenticated
  using (public.is_book_s_owner()) with check (public.is_book_s_owner());
revoke all on public.todos from anon;
grant select, insert, update, delete on public.todos to authenticated;

-- The due-day reminder: at 8:00 AM New York, one push per open item due that day, to book S's phones
-- (apns-deliver sends a book's alerts to its members only). The cron runs at 12:00 and 13:00 UTC so 8:00 New York
-- is covered in summer and winter; the hour check keeps it to one run, the dedup key to one push per item a day.
create or replace function public.todo_reminders() returns integer language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'America/New_York')::date; n integer;
begin
  if extract(hour from now() at time zone 'America/New_York') <> 8 then return 0; end if;
  insert into public.alert_dispatch (category, dedup_key, title, body, deep_link, book_id, meta)
  select 'todo', 'todo:' || t.id || ':' || d, 'To do · today', t.text, 'sunny://todo', 'S', jsonb_build_object('todo_id', t.id)
  from public.todos t where not t.done and t.due = d
  on conflict (dedup_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.todo_reminders() from public, anon, authenticated;

select cron.unschedule('todo-reminders') where exists (select 1 from cron.job where jobname = 'todo-reminders');
select cron.schedule('todo-reminders', '0 12,13 * * *', $$select public.todo_reminders()$$);
