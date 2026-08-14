/* ============================================================
   nvda_planner_state needs a phase, so the income wheel sticks.

   nvda-accumulate hard-coded phase = 'ACCUMULATE'. The wheel is a different
   objective (income, no share target) rather than a setting, so it gets a real
   switch instead of a request-body flag the app would have to remember to send.

   Leaving this at ACCUMULATE keeps every existing behaviour exactly as it is.
   ============================================================ */

alter table public.nvda_planner_state
  add column if not exists phase text not null default 'ACCUMULATE';

-- Only the three the function knows about, plus the new one. A typo here would
-- silently fall back to ACCUMULATE and look like the wheel simply never fired.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'nvda_planner_state_phase_chk') then
    alter table public.nvda_planner_state
      add constraint nvda_planner_state_phase_chk
      check (phase in ('ACCUMULATE','HOLD','HARVEST','WHEEL'));
  end if;
end $$;

-- Turn the wheel ON. Comment this line out to stay on accumulation.
update public.nvda_planner_state set phase = 'WHEEL' where id = 1;

select id, phase, target_shares, cash_ceiling from public.nvda_planner_state where id = 1;
