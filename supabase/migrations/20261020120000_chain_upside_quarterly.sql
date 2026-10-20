-- The quarterly call (Nik, 20 Oct 2026): weekly calls sold at the money, delta
-- kept by calls on the next Jan/Apr/Jul/Oct expiry at 1.5 SD to that expiry.
-- chain-next stores that chain as tenor 'q', 1x to 1.8x the price.
alter table public.option_chain_upside drop constraint if exists option_chain_upside_tenor_check;
alter table public.option_chain_upside
  add constraint option_chain_upside_tenor_check check (tenor = any (array['3m', '12m', 'q']));
