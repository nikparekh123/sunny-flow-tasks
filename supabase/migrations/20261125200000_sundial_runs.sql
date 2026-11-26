-- Sundial 1.0 (docs/SUNDIAL.md): the selling engine's saved answers. One row per book, name, kind and day:
-- 'plan' is the 3:45 PM run (15 minutes before the close), 'drop' the first big-drop run of the day. The payload is the
-- function's answer for that name (the Income board's columns: toSell, close, working, expiring, banked).
-- It says what to trade, so only the book's OWNERS read it (as home_todo); only the function writes (service role).
create table if not exists public.sundial_runs (
  id bigserial primary key,
  book_id text not null,
  ticker text not null,
  kind text not null check (kind in ('plan', 'drop')),
  day date not null,
  run_at timestamptz not null default now(),
  build text,
  payload jsonb not null,
  unique (book_id, ticker, kind, day)
);
alter table public.sundial_runs enable row level security;
drop policy if exists sundial_runs_owner_read on public.sundial_runs;
create policy sundial_runs_owner_read on public.sundial_runs for select to authenticated
  using (book_id in (select public.my_owned_books()));
revoke insert, update, delete on public.sundial_runs from anon, authenticated;

-- The scheduler (25 Nov 2026): every minute 13-21 UTC on weekdays; the function itself checks the session, watches for
-- the big drop and runs the day's plan once from 15 minutes before the close (early closes honoured).
select cron.schedule('sundial-tick', '* 13-21 * * 1-5', $$select public.cron_invoke_function_body('sundial', '{"mode":"tick"}'::jsonb)$$);
