# IBKR Hard Cutover — Runbook

Wipes manually-entered trades from a chosen cutover date forward, after
IBKR Flex has backfilled the same date range. **Run interactively, not
as a migration** — this is a one-time human-driven step with a
go/no-go decision after preview.

## Prerequisites

1. `ibkr-flex-sync` Edge function is live and ingesting daily (✓ as of 2026-06-08)
2. A **backfill Flex Query** in IBKR with `Period = "Last 90 Business Days"`
   (or whatever date range you want IBKR to be source of truth for)
3. The backfill has run at least once and populated `option_trades`,
   `share_lots`, `share_sells` with `source = 'ibkr_flex'`

## Step 1 — Run the backfill

Two options:

**Option A: Temporarily change the IBKR Flex Query in IBKR's UI**
1. Open the existing query (ID 1535729) → change Period from "Today" to "Last 90 Business Days"
2. Save
3. Invoke ibkr-flex-sync manually:
   ```bash
   curl -X POST \
     "https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/ibkr-flex-sync" \
     -H "Authorization: Bearer <publishable-key>" \
     -H "Content-Type: application/json" \
     -d '{"trigger":"backfill"}'
   ```
4. Verify counts (see Step 2)
5. **Change the Period back to "Today"** in IBKR before next cron run!

**Option B: Create a separate "Backfill" Flex Query in IBKR**
1. New query with same field selection, but `Period = "Last 90 Business Days"`
2. Note the new Query ID
3. Set `IBKR_FLEX_BACKFILL_QUERY_ID` in Supabase secrets
4. *(Requires a follow-up to ibkr-flex-sync to accept a query_id override in
   the request body — not built yet)*

Option A is the quick path. Option B is the durable path.

## Step 2 — Verify backfill coverage

```sql
-- Date range and counts of IBKR-sourced data
SELECT 'option_trades' AS table_name,
       MIN(trade_date) AS first_date,
       MAX(trade_date) AS last_date,
       COUNT(*) AS row_count
FROM option_trades WHERE source = 'ibkr_flex'
UNION ALL
SELECT 'share_sells', MIN(trade_date), MAX(trade_date), COUNT(*)
FROM share_sells WHERE source = 'ibkr_flex'
UNION ALL
SELECT 'share_lots', MIN(acquired_date), MAX(acquired_date), COUNT(*)
FROM share_lots WHERE source = 'ibkr_flex';
```

Confirm:
- `first_date` ≤ your intended cutover date
- `last_date` is recent (today or yesterday)
- `row_count` is plausible (~10-100 per month depending on activity)

## Step 3 — Preview what will be deleted

Pick a CUTOVER_DATE that's covered by your IBKR backfill. Recommended: the
oldest date you see in Step 2's `first_date`.

```sql
-- Preview rows that will be deleted
SELECT 'option_trades' AS table_name, COUNT(*) AS to_delete
FROM option_trades
WHERE source = 'manual' AND trade_date >= 'YYYY-MM-DD'   -- ← CUTOVER_DATE
UNION ALL
SELECT 'share_sells', COUNT(*)
FROM share_sells
WHERE source = 'manual' AND trade_date >= 'YYYY-MM-DD'
UNION ALL
SELECT 'share_lots', COUNT(*)
FROM share_lots
WHERE source = 'manual' AND acquired_date >= 'YYYY-MM-DD';
```

If counts look reasonable, proceed. If they're surprisingly high, stop and
investigate — you may be about to delete more than you intend.

## Step 4 — Delete (transaction-wrapped for safety)

```sql
BEGIN;

DELETE FROM option_trades
  WHERE source = 'manual' AND trade_date >= 'YYYY-MM-DD';

DELETE FROM share_sells
  WHERE source = 'manual' AND trade_date >= 'YYYY-MM-DD';

DELETE FROM share_lots
  WHERE source = 'manual' AND acquired_date >= 'YYYY-MM-DD';

-- Sanity check: should show 0 manual rows ≥ cutover
SELECT 'option_trades' AS table_name, COUNT(*) AS remaining_manual
FROM option_trades
WHERE source = 'manual' AND trade_date >= 'YYYY-MM-DD'
UNION ALL
SELECT 'share_sells', COUNT(*)
FROM share_sells
WHERE source = 'manual' AND trade_date >= 'YYYY-MM-DD'
UNION ALL
SELECT 'share_lots', COUNT(*)
FROM share_lots
WHERE source = 'manual' AND acquired_date >= 'YYYY-MM-DD';

-- If all good:
COMMIT;
-- If anything looks wrong:
-- ROLLBACK;
```

## Step 5 — Verify in the iOS app

1. Pull-to-refresh on the Trades tab
2. Confirm positions match IBKR exactly
3. Confirm no duplicate-looking rows

If anything's off, the transaction kept the data — re-investigate before
running again.

## Step 6 — Switch Flex Query back to "Today"

If you used Option A, **don't forget this step.** Cron will keep using
whatever period the query has set, so leaving it at "Last 90 Business
Days" means every 15-min cron run pulls 90 days of data unnecessarily.
