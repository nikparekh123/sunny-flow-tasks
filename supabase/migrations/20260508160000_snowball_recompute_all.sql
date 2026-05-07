-- Universe-wide lens recompute. Same as snowball_recompute_one but for
-- every ticker — used at the end of `↻ Sync from API` so the user
-- doesn't have to manually trigger sector defaults to see lens values.
create or replace function public.snowball_recompute_all()
returns int
language plpgsql security definer set search_path = public as $$
declare
  t text;
  n int := 0;
begin
  for t in select ticker from public.snowball loop
    perform public.snowball_recompute_one(t);
    n := n + 1;
  end loop;
  return n;
end;
$$;

grant execute on function public.snowball_recompute_all() to authenticated, anon;
