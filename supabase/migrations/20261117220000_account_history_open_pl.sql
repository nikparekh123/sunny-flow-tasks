-- Open P&L (Nik, 17 Nov 2026): what the open positions are up or down since they were opened, premium
-- included (IBKR position value minus cost basis; a sold option's cost basis is minus its premium).
-- Replaces Unrealized in Home's stat row on the phone and the web. sunny-home writes it per day.
alter table public.account_history add column if not exists open_pl numeric;
