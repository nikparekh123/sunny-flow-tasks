-- BOOKS AND LOCK-DOWN (Nik, 16 Oct 2026). Steps 2 and 3 of the second-account plan.
--
-- A book is one person's money: S = Nik (IBKR U13741475 + U21749479, summed as one
-- account since 12 Oct), N = his cousin (added once his IBKR account exists). Every
-- personal row carries book_id; today all of it is S (the column default, so every
-- writer keeps working unchanged). A login sees only the books it belongs to:
-- Nik owns S (and will own N); the cousin will be a viewer of N only.
--
-- Before this, every signed-in login could read the whole book and insert, edit or
-- delete trades, and several database functions that change data could be run with
-- the app's public key. Edge functions use the service role and are not affected.

begin;

-- ── 1. Books and who belongs to them ─────────────────────────────────────────
create table if not exists public.books (
  id            text primary key,              -- 'S', 'N': the switcher label
  name          text not null,
  ibkr_accounts text[] not null default '{}',
  created_at    timestamptz not null default now()
);
create table if not exists public.book_members (
  user_id    uuid not null references auth.users (id) on delete cascade,
  book_id    text not null references public.books (id) on delete cascade,
  role       text not null check (role in ('owner', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (user_id, book_id)
);
alter table public.books enable row level security;
alter table public.book_members enable row level security;

insert into public.books (id, name, ibkr_accounts)
values ('S', 'Niket', array['U13741475', 'U21749479'])
on conflict (id) do nothing;

-- Every login that can see the book today keeps seeing it: Nik's two emails own it,
-- Rads (last signed in 29 Apr) can read it but no longer edit.
insert into public.book_members (user_id, book_id, role)
select u.id, 'S', case when u.email in ('nik@sunnyfi.co', 'hello@nikparekh.com') then 'owner' else 'viewer' end
from auth.users u
on conflict do nothing;

-- The caller's books, and the ones it may change. SECURITY DEFINER so policies can
-- read book_members without exposing it.
create or replace function public.my_books() returns setof text
language sql stable security definer set search_path = '' as $$
  select book_id from public.book_members where user_id = (select auth.uid())
$$;
create or replace function public.my_owned_books() returns setof text
language sql stable security definer set search_path = '' as $$
  select book_id from public.book_members where user_id = (select auth.uid()) and role = 'owner'
$$;
-- Feed health, sync runs and system alerts: Nik's eyes only (owner of S).
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.book_members
                 where user_id = (select auth.uid()) and book_id = 'S' and role = 'owner')
$$;
revoke execute on function public.my_books(), public.my_owned_books(), public.is_admin() from public, anon;
grant execute on function public.my_books(), public.my_owned_books(), public.is_admin() to authenticated, service_role;

create policy "books: members read" on public.books for select to authenticated
  using (id in (select public.my_books()));
create policy "book_members: own rows" on public.book_members for select to authenticated
  using (user_id = (select auth.uid()));

-- ── 2. Tag every personal table with its book (all S today) ───────────────────
do $$
declare t text;
begin
  foreach t in array array['option_trades', 'positions', 'share_lots', 'share_sells', 'strategy_overlay',
                           'reports', 'theta_checks', 'account_daily', 'account_positions_daily',
                           'account_history', 'home_snapshot', 'alert_dispatch'] loop
    execute format('alter table public.%I add column if not exists book_id text not null default %L references public.books (id)', t, 'S');
    execute format('create index if not exists %I on public.%I (book_id)', t || '_book_id_idx', t);
  end loop;
end $$;
alter table public.home_snapshot add constraint home_snapshot_book_id_key unique (book_id);

-- ── 3. Replace the "any signed-in user" policies ─────────────────────────────
do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
           where schemaname = 'public'
             and tablename = any (array['option_trades', 'positions', 'share_lots', 'share_sells', 'strategy_overlay',
                                        'reports', 'theta_checks', 'account_daily', 'account_positions_daily',
                                        'account_history', 'home_snapshot', 'alert_dispatch',
                                        'leg_marks_daily', 'option_greeks', 'option_greeks_live',
                                        'ibkr_sync_runs', 'ibkr_sync_alerts', 'sync_heartbeat', 'system_alerts',
                                        'mp_refresh_runs', 'push_devices'])
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Read: your own books only.
do $$
declare t text;
begin
  foreach t in array array['option_trades', 'positions', 'share_lots', 'share_sells', 'strategy_overlay',
                           'reports', 'theta_checks', 'account_daily', 'account_positions_daily',
                           'account_history', 'home_snapshot', 'alert_dispatch'] loop
    execute format('create policy %I on public.%I for select to authenticated using (book_id in (select public.my_books()))',
                   t || ': own books read', t);
  end loop;
end $$;

-- Write: only a book's owner, and only on the tables the website edits (the
-- sunnyfi.co positions page adds, edits and deletes trades; IBKR stays the source).
do $$
declare t text;
begin
  foreach t in array array['option_trades', 'positions', 'share_lots', 'share_sells', 'strategy_overlay'] loop
    execute format('create policy %I on public.%I for insert to authenticated with check (book_id in (select public.my_owned_books()))',
                   t || ': owner insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (book_id in (select public.my_owned_books())) with check (book_id in (select public.my_owned_books()))',
                   t || ': owner update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (book_id in (select public.my_owned_books()))',
                   t || ': owner delete', t);
  end loop;
end $$;

-- Marks and greeks follow their trade's book.
do $$
declare t text;
begin
  foreach t in array array['leg_marks_daily', 'option_greeks', 'option_greeks_live'] loop
    execute format('create policy %I on public.%I for select to authenticated using (exists (select 1 from public.option_trades o where o.id = option_trade_id and o.book_id in (select public.my_books())))',
                   t || ': own books read', t);
  end loop;
end $$;

-- Feed health and sync logs: admin only.
do $$
declare t text;
begin
  foreach t in array array['ibkr_sync_runs', 'ibkr_sync_alerts', 'sync_heartbeat', 'system_alerts', 'mp_refresh_runs'] loop
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_admin()))',
                   t || ': admin read', t);
  end loop;
end $$;

-- ── 4. Push: each phone belongs to the login that registered it ──────────────
alter table public.push_devices add column if not exists user_id uuid references auth.users (id) on delete cascade;
alter table public.push_devices alter column user_id set default auth.uid();
-- The one phone registered today is Nik's.
update public.push_devices set user_id = (select id from auth.users where email = 'nik@sunnyfi.co') where user_id is null;
create policy "push_devices: own phone" on public.push_devices for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ── 5. Database functions that change data: scheduler and service role only ──
-- (pg_cron runs as postgres and the edge functions use the service role, so
-- nothing scheduled changes.) The website's health page keeps get_cron_status.
do $$
declare r record;
begin
  for r in select p.proname, p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('capture_leg_marks_daily', 'close_expired_option_legs', 'cron_invoke_function',
                               'cron_invoke_function_body', 'option_greeks_to_live', 'prune_option_greeks_90d',
                               'prune_ticker_quotes_30d', 'raise_system_alert', 'clear_system_alert',
                               'reconcile_share_fifo', 'ticker_quotes_to_live', 'get_cron_status') loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    if r.proname <> 'get_cron_status' then
      execute format('revoke execute on function %s from authenticated', r.sig);
    end if;
    execute format('grant execute on function %s to service_role', r.sig);
  end loop;
end $$;

commit;
