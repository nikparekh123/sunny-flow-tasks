-- "Done for this week" on a name's call sale (Nik, 26 Oct 2026). He sold 12 of NFLX's 17 calls on purpose (closed
-- the 67s at 85% captured, sold 12 at 64, bought 4 Jan 70 calls), and To do kept asking for the other 5 plus the hedge
-- calls those 5 would need. A row here means the week's sale is finished: sunny-home sells nothing more for that name
-- that week and sizes the hedge on what is sold. Written only through mark_sale_done() by the book's owner.
create table if not exists public.sale_done (
  book_id text        not null references public.books(id),
  ticker  text        not null,
  week    date        not null,
  done_at timestamptz not null default now(),
  primary key (book_id, ticker, week)
);
alter table public.sale_done enable row level security;
drop policy if exists "sale_done: own books read" on public.sale_done;
create policy "sale_done: own books read" on public.sale_done for select to authenticated
  using (book_id in (select public.my_books()));

create or replace function public.mark_sale_done(p_ticker text, p_week date, p_done boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare b text;
begin
  select m into b from public.my_owned_books() as m limit 1;
  if b is null then raise exception 'only the book''s owner can change its plan'; end if;
  if p_done then
    insert into public.sale_done (book_id, ticker, week) values (b, upper(p_ticker), p_week) on conflict do nothing;
  else
    delete from public.sale_done where book_id = b and ticker = upper(p_ticker) and week = p_week;
  end if;
end $$;
revoke all on function public.mark_sale_done(text, date, boolean) from public, anon;
grant execute on function public.mark_sale_done(text, date, boolean) to authenticated;
