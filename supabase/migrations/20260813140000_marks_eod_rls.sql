/* ============================================================
   RLS enabled with no policy reads as EMPTY, not as an error.

   Both store migrations list *_option_marks_eod in a policy loop, but the loop
   uses bare `create policy` — which throws if the policy already exists and
   aborts the whole do-block, leaving every table after that point in the array
   with RLS on and nothing granting select. The app's read then returns zero rows
   with no error to notice, so every leg renders "no mark".

   Reports what exists, then creates only what is missing.
   ============================================================ */

-- 1 · what is actually there right now
select c.relname as table_name,
       c.relrowsecurity as rls_on,
       coalesce(string_agg(p.policyname, ', '), '(NONE — reads return empty)') as policies
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
left join pg_policies p on p.schemaname='public' and p.tablename = c.relname
where c.relname in ('nvda_option_marks','nvda_option_marks_eod',
                    'tlt_option_marks','tlt_option_marks_eod')
group by c.relname, c.relrowsecurity
order by c.relname;

-- 2 · grant authenticated select wherever it is missing
do $$
declare t text;
begin
  foreach t in array array['nvda_option_marks','nvda_option_marks_eod',
                           'tlt_option_marks','tlt_option_marks_eod'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies
                   where schemaname='public' and tablename=t and policyname=t||'_auth_read') then
      execute format($p$create policy %I on public.%I for select to authenticated using (true)$p$,
                     t||'_auth_read', t);
      raise notice 'created missing select policy on %', t;
    end if;
  end loop;
end $$;

-- 3 · confirm
select c.relname as table_name,
       coalesce(string_agg(p.policyname, ', '), '(STILL NONE)') as policies
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
left join pg_policies p on p.schemaname='public' and p.tablename = c.relname
where c.relname in ('nvda_option_marks','nvda_option_marks_eod',
                    'tlt_option_marks','tlt_option_marks_eod')
group by c.relname
order by c.relname;
