-- IBKR's commission and net cash per option fill, in IBKR's sign: commission
-- negative (a cost), net cash positive when sold and negative when bought,
-- commission included. Written by ibkr-flex-sync from 12 Oct 2026 on; older
-- rows stay null (account_daily carries each day's commission total from
-- Change in NAV, which is what the period figures add up).
alter table public.option_trades add column if not exists commission numeric;
alter table public.option_trades add column if not exists net_cash numeric;
