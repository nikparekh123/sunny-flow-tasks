/* ============================================================
   executed_at — capture IBKR execution time so sync latency is
   measurable from real data
   ============================================================
   The IBKR Flex report already sends an execution timestamp
   (dateTime = "YYYYMMDD;HHMMSS", Eastern). ibkr-flex-sync now parses
   it to UTC and writes it here. Differencing against last_synced_at
   (also UTC) gives the true end-to-end sync latency per trade:

     select id, ticker, executed_at, last_synced_at,
            round(extract(epoch from (last_synced_at - executed_at))/60.0, 1)
              as latency_min
     from option_trades
     where source = 'ibkr_flex' and executed_at is not null
     order by last_synced_at desc;

   Nullable: existing rows and manual entries stay null. Backfilled
   naturally as new trades sync.
   ============================================================ */

alter table public.option_trades add column if not exists executed_at timestamptz;
alter table public.share_lots    add column if not exists executed_at timestamptz;
alter table public.share_sells   add column if not exists executed_at timestamptz;

comment on column public.option_trades.executed_at is
  'IBKR execution time (UTC), parsed from Flex dateTime (Eastern) by ibkr-flex-sync. '
  'Null for manual / pre-migration rows. last_synced_at - executed_at = sync latency.';
comment on column public.share_lots.executed_at is 'IBKR execution time (UTC). See option_trades.executed_at.';
comment on column public.share_sells.executed_at is 'IBKR execution time (UTC). See option_trades.executed_at.';
