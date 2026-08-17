/* ============================================================
   Put size becomes a setting, because it is a MARGIN decision.

   The shipped rule sized puts one-for-one with the block, so every assignment
   doubled the position: 1,000 shares, 2,000, 4,000. A name that keeps falling
   grows the position exponentially into the fall.

   Simulated on NKE's own daily returns over ten weeks, that one choice is the
   difference between a median average sitting 13% BELOW the market and a 70%
   loss in the worst 5%. A fixed count grows the block in a straight line and the
   averaging-down works exactly as Nik described it.

   The number itself is his, not the engine's: only he can see what IBKR is
   asking for, and the requirement moves (AVGO wanted five times the usual into
   its print). null keeps the old one-for-one behaviour.

   Calls are NOT settable and never will be. You cannot sell a call against
   stock you do not own, so they stay one-for-one with the shares held.
   ============================================================ */

alter table public.income_sleeve_names
  add column if not exists put_contracts int;

comment on column public.income_sleeve_names.put_contracts is
  'How many puts to sell each week, fixed. NULL means one per 100 shares held, '
  'which compounds the block on every assignment. Set from the margin the broker '
  'is actually asking for.';

-- Nothing is set yet: sizes are Nik's call once he has the margin numbers.
--   update public.income_sleeve_names set put_contracts = 10 where ticker = 'NFLX';
--   update public.income_sleeve_names set put_contracts = 19 where ticker = 'NKE';

notify pgrst, 'reload schema';

select ticker, active, put_contracts, started_on from public.income_sleeve_names
 order by active desc, sort;
