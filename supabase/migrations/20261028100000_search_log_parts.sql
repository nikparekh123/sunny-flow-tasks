-- Sunny search at launch (block 27, 28 Oct 2026): answers are text parts, not cards. Each logged answer keeps its
-- parts, its source line, the one-line recap and what the history list shows (preview: the big number and the line
-- under it, or the recap), so "your last 10" reads straight from the log, per login, across days and devices.
alter table public.search_log
  add column if not exists parts   jsonb,
  add column if not exists source  jsonb,
  add column if not exists recap   text,
  add column if not exists preview jsonb;
create index if not exists search_log_user_at on public.search_log (book_id, user_id, at desc);

-- The weekly review: a text answer has no cards, so "came back with no card" now means no parts.
create or replace view public.search_misses with (security_invoker = true) as
  select id, at, question, answer, can_answer, check_ok, unverified, feedback, cards, ms, cost_usd
  from public.search_log
  where at > now() - interval '7 days'
    and (can_answer is false or check_ok is false or feedback in ('down', 'not_asked') or coalesce(array_length(cards, 1), 0) = 0)
  order by at desc;
