-- Handoff 32, 26 Oct 2026: readable buys and sells per contract since tracking began, so each wall's confidence
-- can include one-sidedness (|sold - bought| / (sold + bought)).
alter table public.dealer_pos add column if not exists cum_buy numeric not null default 0;
alter table public.dealer_pos add column if not exists cum_sell numeric not null default 0;
