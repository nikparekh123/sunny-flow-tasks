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

> ⛔ **DO NOT change query 1535729's Period.** The old "Option A"
> (temporarily switch 1535729 from "Today" to a multi-day period) is
> **wrong and removed.** Query 1535729 is a **Trade Confirmation Flex
> (TCF)** report — IBKR *locks* its Period to "Today"; saving any other
> period fails or silently yields empty reports. Never touch it.

**Use a separate Daily Flex query (the only supported path — now built):**
1. In IBKR's portal, create a **Daily Flex** query (NOT Trade
   Confirmation Flex) with the same field selection and
   `Period = "Last 90 Business Days"` (or "Year to Date" / whatever
   range you want IBKR to own). Note its **Query ID**.
   - There is already a Daily Flex query **1540791** at
     `Period = "Last 5 Business Days"` (the nightly backfill cron). If
     5 business days is enough coverage, reuse it. For a deeper cutover,
     make a longer-period Daily Flex query and use its ID below.
2. Invoke `ibkr-flex-sync` with a `query_id` **override in the request
   body** — this points the sync at the Daily query for one run and
   leaves the TCF env var (`IBKR_FLEX_QUERY_ID` = 1535729) untouched:
   ```bash
   curl -X POST \
     "https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/ibkr-flex-sync" \
     -H "Authorization: Bearer <publishable-or-service-key>" \
     -H "Content-Type: application/json" \
     -d '{"trigger":"backfill","query_id":"<DAILY_QUERY_ID>"}'
   ```
   `trigger=backfill` bypasses the ET market-hours gate; the `query_id`
   override is honored only for backfill/manual triggers, never cron.
3. Daily Flex has T+1 (overnight) latency — fine for backfill.
4. Verify counts (see Step 2).

There is no "switch it back" step — the TCF query was never touched.

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

## Step 6 — (nothing to undo)

The backfill ran against a **separate** Daily Flex query via the
`query_id` body override, so the intraday TCF query (1535729) and the
cron were never modified. There is nothing to switch back.
