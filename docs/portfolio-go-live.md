# Portfolio go-live — operator checklist

Run this top-to-bottom the first time. ~10 minutes if everything is set
up correctly; longer if the `POLYGON_API_KEY` secret or pg_net extension
needs to be added.

Replace the four placeholders inline once, then copy-paste the commands:

```
<PROJECT-REF>        # e.g. abcdefghijkl (in your Supabase URL: https://<PROJECT-REF>.supabase.co)
<SERVICE-ROLE-KEY>   # Supabase dashboard → Project Settings → API → service_role
<ANON-KEY>           # same place, "anon public" — only used in step 4
<PROD-URL>           # e.g. https://sunnyfi.co  (drop the `https://` if you want, the curl works either way)
```

---

## 1. Run the migrations (~30 s)

The two PD-1 migrations create the tables and stage the cron job.

**Option A — CLI:**
```bash
cd "/path/to/sunny-flow-tasks"
supabase db push
```

**Option B — Dashboard:**
1. Open Supabase → SQL Editor.
2. Paste the contents of `supabase/migrations/20260530000000_portfolio_master.sql` → Run.
3. Paste the contents of `supabase/migrations/20260530000100_mp_refresh_cron.sql` → Run.

**Verify** (Supabase → Table Editor):
- `option_greeks` exists with 9 columns (option_trade_id, delta, gamma, theta, vega, iv, open_interest, volume, last_mark, captured_at).
- `ticker_quotes` exists with 4 columns (ticker, spot, day_change_pct, beta, captured_at).
- Both are empty for now — that's expected.

---

## 2. Confirm the Polygon secret is set (~10 s)

```bash
supabase secrets list | grep POLYGON_API_KEY
```
Should print `POLYGON_API_KEY` with a redacted value. If not:
```bash
supabase secrets set POLYGON_API_KEY=<your-polygon-key>
```

---

## 3. Deploy the edge function (~30 s)

```bash
supabase functions deploy mp-refresh
```

Should print something like `Function mp-refresh deployed`. Re-run if you
hit a transient error.

---

## 4. Invoke it once manually (~5 s)

This populates `option_greeks` and `ticker_quotes` for the first time
without waiting on the cron.

**Option A — curl:**
```bash
curl -X POST "https://<PROJECT-REF>.functions.supabase.co/mp-refresh" \
  -H "Authorization: Bearer <ANON-KEY>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Option B — UI:**
1. Open `<PROD-URL>/portfolio` in a browser.
2. Click the **↻ Refresh** button in the controls row (between "Show closed" and "Smart sort").

**Expected response:**
```json
{
  "ok": true,
  "legs":    { "total": N, "updated": N, "failed": 0, "failures": [] },
  "tickers": { "total": M, "updated": M },
  "timestamp": "2026-05-30T..."
}
```

`N` and `M` should match your open option-leg count and held-ticker count.
If `failed > 0`, the `failures` array (up to 10) lists the OCC symbol +
reason — usually a typo in the trade row or an expired contract that
Polygon no longer indexes. Either way, the rest of the legs still wrote.

---

## 5. Verify rows landed (~30 s)

**SQL Editor:**
```sql
select count(*) as legs, max(captured_at) as latest_capture
from option_greeks;

select count(*) as tickers, max(captured_at) as latest_capture
from ticker_quotes;
```

Both counts should be > 0; `latest_capture` should be within the last
minute. Spot-check a few rows:

```sql
select og.option_trade_id, ot.ticker, ot.option_type, ot.strike, ot.expiry,
       og.delta, og.iv, og.open_interest, og.captured_at
from option_greeks og
join option_trades ot on ot.id = og.option_trade_id
order by og.captured_at desc
limit 5;

select * from ticker_quotes order by captured_at desc limit 5;
```

Sanity checks:
- `delta` is between −1 and 1 (per-share).
- `iv` is a decimal (0.42 = 42%, not 42).
- `open_interest` is a plausible integer (hundreds to tens of thousands).
- `spot` for AAPL/META/NVDA matches a quick Yahoo Finance check (Polygon
  is 15-min delayed — close, not exact).

---

## 6. Check the UI shows the new data (~1 min)

### /portfolio
- **Greeks bar** at the top should show non-zero values for Net delta,
  Beta-weighted delta, Net theta, Net vega, Net gamma. Open P&L should
  match what you see on /positions.
- **Table view** — each option leg row should show real Δ / Γ / Θ / V
  numbers and an IV%. The OI · Vol column should show the contract's
  open interest and volume; hover → 4-day flow popover.
- **"↻ Refresh"** button: shows "Refreshing…" while in-flight, then
  numbers may twitch as fresh data lands (within 1 polling cycle of
  React Query — usually <1 s after the call returns).
- Header right side: should show "UPDATED 14:32 PT" (or whatever clock,
  in your local TZ) instead of "—".

### /dashboard
- **Portfolio block**: under the sparkline, a new compact row should
  appear: `Δ +3,708 · β·Δ +4,656 · Θ/d +584 · V/1% −450` (real numbers
  for your book, not these placeholders). The values should match what
  /portfolio's Greeks bar shows.

If both pages show identical numbers — the SOT wiring is working.

---

## 7. Activate the cron (~2 min, one-time)

Until you do this, the only way data refreshes is via the manual
button. To get the 15-min auto-refresh:

1. Open Supabase → SQL Editor.
2. Open `supabase/migrations/20260530000100_mp_refresh_cron.sql` from the
   repo.
3. Uncomment the `SELECT cron.schedule(...)` block at the bottom (lines
   ~36–51).
4. Replace `<PROJECT-REF>` and `<SERVICE-ROLE-KEY>` with your values.
5. Paste into the SQL Editor and Run.

**Verify the cron is registered:**
```sql
select jobname, schedule, active from cron.job where jobname = 'mp-refresh-15min';
```
Should return one row with `schedule = '*/15 13-19 * * 1-5'` and `active = t`.

**Verify it actually ran** (after waiting up to 15 min):
```sql
select max(captured_at) as latest, count(*) as runs_today
from option_greeks
where captured_at > current_date::timestamptz;
```
`latest` should be within the last 15 min during market hours;
`runs_today` should be growing through the day.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `mp-refresh` returns `{ error: "POLYGON_API_KEY is not set as a Supabase secret" }` | Step 2 was skipped | `supabase secrets set POLYGON_API_KEY=...` then redeploy is NOT needed (secrets are read live) |
| `failed: N` with reason "HTTP 404" on every leg | OCC symbol mismatch (e.g. wrong expiry format) | Check the leg's `expiry` in `option_trades` is `YYYY-MM-DD` |
| `failed: N` with reason "HTTP 429" | Polygon rate limit | The function fetches sequentially per leg — should not happen on a normal-sized book. If it does, your plan tier is too low; upgrade or add a small sleep between calls |
| Tables exist, function returns ok, but UI still shows zeros | RLS blocking the read | Open Supabase → Authentication → Policies → confirm `option_greeks readable to authenticated` + `ticker_quotes readable to authenticated` exist. Re-run the migration if not |
| Cron job registered but `latest` not advancing | `pg_net` extension not installed | Supabase → Database → Extensions → enable `pg_net` |
| Numbers on /portfolio and /dashboard disagree | React Query cache stale | Hard-refresh the browser (Cmd+Shift+R). React Query's `staleTime` is 60 s for Greeks, 30 s for quotes |

---

## Day-2 ops

- **Manual refresh anytime**: the ↻ button on /portfolio. Useful right
  after entering a new trade so the Greeks land before the next 15-min cron.
- **What "fresh" looks like**: `option_greeks.captured_at` within 15 min
  during market hours, or within ~25 min on the latest Friday close
  (last cron of the week fires at 19:45 UTC).
- **Outside market hours**: data is stale by design — Polygon doesn't
  push Greeks after-hours on the delayed feed.

If something looks off in production, the function logs are at:
Supabase → Edge Functions → `mp-refresh` → Logs.
