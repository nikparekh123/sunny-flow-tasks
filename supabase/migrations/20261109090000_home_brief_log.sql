-- Each moment's Home brief, kept so the web's moment tabs (Pre · Open · Post · Weekend) can reread an
-- earlier brief (Nik, 9 Nov 2026). One row per book, tab and audience: sunny-home overwrites it as it
-- builds, so each tab holds the last brief of its moment (with built_for, the day it was for).
--   audience 'all':    the copy without orders (brief_doc_open), for every member of the book
--   audience 'owners': the whole brief, for the book's owners only (the To do rule of 31 Oct 2026)
create table if not exists public.home_brief_log (
  book_id    text        not null,
  tab        text        not null check (tab in ('pre', 'open', 'post', 'weekend')),
  audience   text        not null check (audience in ('all', 'owners')),
  moment     text        not null,
  built_for  date        not null,
  doc        jsonb,
  built_at   timestamptz not null default now(),
  build      text,
  primary key (book_id, tab, audience)
);

alter table public.home_brief_log enable row level security;

drop policy if exists "home_brief_log: members read" on public.home_brief_log;
create policy "home_brief_log: members read" on public.home_brief_log
  for select to authenticated
  using (
    book_id in (select public.my_books())
    and (audience = 'all' or book_id in (select public.my_owned_books()))
  );

-- Written only by sunny-home with the service role; no one else writes.
revoke insert, update, delete on public.home_brief_log from anon, authenticated;
grant select on public.home_brief_log to authenticated;
