-- Search's own part of Home (18 Nov 2026, the speed review, Nik picked 1 and 2): the pieces of sunny-home's build
-- that no screen reads any more but Search still answers from (plan, flow_profile) leave home_snapshot and
-- home_todo, which every phone and the web download every 15 s, for this row per book. Only sunny-search reads it,
-- with the service key (plan for the book's owners only, as before); no policy, so no login reads it directly.
create table if not exists public.home_search (
  book_id  text primary key,
  payload  jsonb not null,
  built_at timestamptz,
  build    text
);
alter table public.home_search enable row level security;
revoke all on public.home_search from anon, authenticated;
