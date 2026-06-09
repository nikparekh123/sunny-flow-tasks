/* ============================================================
   option_iv_daily_change — view
   ============================================================
   Powers the "IV jumped today" bucket on the Today landing tab.

   For every option_trade_id with at least one prior-day IV capture,
   returns:
     • iv_now       — latest IV (from option_greeks)
     • iv_prev      — last IV captured on a strictly prior date
     • iv_change_pts — (iv_now − iv_prev) in decimal IV points
                      (e.g. 0.03 = +3 IV percentage points)
     • iv_change_pct — relative change ((now − prev) / prev)

   "Prior date" is bucketed by captured_at::date in UTC. mp-refresh
   captures intraday during market hours, so this view compares the
   latest capture against the last capture from yesterday (or
   day-before-yesterday if today hasn't ticked yet).

   Append-only data source: option_greeks (90-day retention). No new
   cron — this is a pure view, recomputed at query time.
   ============================================================ */

CREATE OR REPLACE VIEW public.option_iv_daily_change AS
WITH latest AS (
  SELECT DISTINCT ON (option_trade_id)
    option_trade_id,
    iv          AS iv_now,
    captured_at AS now_at,
    captured_at::date AS d_now
  FROM public.option_greeks
  WHERE iv IS NOT NULL
  ORDER BY option_trade_id, captured_at DESC
),
prior AS (
  SELECT DISTINCT ON (og.option_trade_id)
    og.option_trade_id,
    og.iv          AS iv_prev,
    og.captured_at AS prev_at
  FROM public.option_greeks og
  JOIN latest l USING (option_trade_id)
  WHERE og.iv IS NOT NULL
    AND og.captured_at::date < l.d_now
  ORDER BY og.option_trade_id, og.captured_at DESC
)
SELECT
  l.option_trade_id,
  l.iv_now,
  p.iv_prev,
  (l.iv_now - p.iv_prev) AS iv_change_pts,
  CASE
    WHEN p.iv_prev IS NOT NULL AND p.iv_prev > 0
      THEN (l.iv_now - p.iv_prev) / p.iv_prev
    ELSE NULL
  END AS iv_change_pct,
  l.now_at  AS captured_at,
  p.prev_at AS prev_captured_at
FROM latest l
LEFT JOIN prior p USING (option_trade_id);

-- The view inherits RLS from option_greeks (which is row-secured at
-- the source). PostgREST will see only what the calling role can read.
COMMENT ON VIEW public.option_iv_daily_change IS
  'Day-over-day IV change per option_trade_id. Latest capture vs the last capture from a strictly prior date. iv_change_pts is in decimal IV points (0.03 = +3 IV pts).';
