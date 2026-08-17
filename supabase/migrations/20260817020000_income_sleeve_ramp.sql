/* ============================================================
   The ramp: how much to BUY, not just what to write.

   Until now the sleeve only ever sized writes against shares already held, so
   on an empty book every name read "no shares yet, nothing to write against"
   and the screen never said what to do about it. Nik: "Doesn't show how much
   to buy for each ticker."

   His rule, 2026-08-17: start at $5,000 of income a week and add $5,000 each
   week until $30,000. Slow on purpose — each step is a week of real behaviour
   before the next one is taken, and it can be stopped at any rung.

   ── The cap is not reachable on the planned capital ────────────────────────
   Writing both legs earns roughly 4% of the block a week at current premiums,
   so $30,000 a week needs about $735,000 of stock and the same again promised
   in short puts. On the $600,000 Nik planned the ceiling is nearer $24,500.
   The cap stays at 30,000 because it is his stated goal; the sleeve will simply
   stop being able to fill it, and the card says how much stock each step needs
   rather than pretending.

   One row, deliberately. This is sleeve-wide policy, not per-name, and putting
   it on income_sleeve_names would invite three different answers.
   ============================================================ */

create table if not exists public.income_sleeve_settings (
  id              int primary key default 1,
  -- the ramp
  ramp_start_on   date    not null default '2026-08-17',
  ramp_start      numeric not null default 5000,    -- week one's income target
  ramp_step       numeric not null default 5000,    -- added each week after
  ramp_cap        numeric not null default 30000,   -- the stated goal
  ramp_paused     boolean not null default false,   -- hold at the current rung
  updated_at      timestamptz default now(),
  constraint income_sleeve_settings_one_row check (id = 1)
);

comment on table public.income_sleeve_settings is
  'Sleeve-wide policy, one row. The ramp turns a weekly income target into a '
  'share purchase per name; income-sleeve reads it and emits the buy line.';

alter table public.income_sleeve_settings enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies
                 where schemaname='public' and tablename='income_sleeve_settings'
                   and policyname='income_sleeve_settings_auth_read') then
    create policy income_sleeve_settings_auth_read on public.income_sleeve_settings
      for select to authenticated using (true);
  end if;
end $$;

insert into public.income_sleeve_settings (id) values (1) on conflict (id) do nothing;

-- PostgREST caches the column list. Without this the function asks for a table
-- the API layer does not know about yet and silently gets nothing back, which is
-- how started_on looked like it had failed to apply twice on 2026-08-16.
notify pgrst, 'reload schema';

select * from public.income_sleeve_settings;

/* To hold at the current rung rather than stepping up:
     update public.income_sleeve_settings set ramp_paused = true where id = 1;
   To change the goal:
     update public.income_sleeve_settings set ramp_cap = 25000 where id = 1;   */
