-- Handoff 31 (13c): the quarterly's puts ('qp'), so the To do face can price the January put walls.
alter table public.option_chain_upside drop constraint if exists option_chain_upside_tenor_check;
alter table public.option_chain_upside add constraint option_chain_upside_tenor_check
  check (tenor = any (array['3m', '12m', 'q', 'qp']));
