-- Research Nik adds for Sunny search (27 Oct 2026): Investing Pro and other sources, read from his screenshots and
-- text in research-inbox, checked by him, then saved here. Numbers go to research_numbers (one row a figure, with its
-- label, unit, period, source and date); writing goes to research_notes. Context only: the search quotes it with its
-- source and date and never uses it for To do, strikes or hedges. Any signed-in book member may read it; only the
-- service key writes.
create table if not exists public.research_numbers (
  id          bigserial   primary key,
  ticker      text        not null,
  asof        date        not null,
  source      text        not null,
  topic       text        not null,
  metric      text        not null,
  label       text        not null,
  period      text        not null default '',
  value       numeric,
  value_text  text,
  unit        text,
  file        text,
  checked_at  timestamptz,
  created_at  timestamptz not null default now(),
  unique (ticker, asof, source, topic, metric, period)
);
create index if not exists research_numbers_ticker on public.research_numbers (ticker, asof desc);
create table if not exists public.research_notes (
  id          bigserial   primary key,
  ticker      text        not null,
  asof        date        not null,
  source      text        not null,
  title       text        not null,
  body        text        not null,
  file        text,
  checked_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists research_notes_ticker on public.research_notes (ticker, asof desc);
alter table public.research_numbers enable row level security;
alter table public.research_notes enable row level security;
drop policy if exists "research_numbers: members read" on public.research_numbers;
create policy "research_numbers: members read" on public.research_numbers for select to authenticated
  using (exists (select 1 from public.book_members m where m.user_id = (select auth.uid())));
drop policy if exists "research_notes: members read" on public.research_notes;
create policy "research_notes: members read" on public.research_notes for select to authenticated
  using (exists (select 1 from public.book_members m where m.user_id = (select auth.uid())));
