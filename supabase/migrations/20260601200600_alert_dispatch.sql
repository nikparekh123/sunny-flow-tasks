/* ============================================================
   alert_dispatch — outbound notification queue
   ============================================================
   The dispatcher writes rows here for every notification it
   wants to send. A separate worker (Apple push / email / etc.)
   drains the queue. Splitting "decide what to send" from
   "actually send it" means we can keep the dispatcher logic
   simple and idempotent — re-runs just dedupe via dedup_key.

   dedup_key is a stable per-event identifier, e.g.
     "theta_cliff:<trade_id>:<date>"
     "short_call_itm:<trade_id>:<date>"
     "earnings_day_before:<ticker>:<date>"
   so we never fire the same alert twice on the same day.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.alert_dispatch (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Category name — matches NotificationPrefs.Category.rawValue.
  category      text NOT NULL,
  -- Stable identifier for dedup. UNIQUE so re-runs are idempotent.
  dedup_key     text NOT NULL UNIQUE,
  ticker        text,
  title         text NOT NULL,
  body          text,
  -- Where the iOS app should land when tapped (deep link path).
  deep_link     text,
  meta          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- Set when the push worker successfully delivered.
  delivered_at  timestamptz
);

CREATE INDEX IF NOT EXISTS idx_alert_dispatch_undelivered
  ON public.alert_dispatch (created_at)
  WHERE delivered_at IS NULL;

ALTER TABLE public.alert_dispatch ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "alert_dispatch: authenticated read"
  ON public.alert_dispatch;
CREATE POLICY "alert_dispatch: authenticated read"
  ON public.alert_dispatch FOR SELECT TO authenticated USING (true);

-- Realtime so the in-app banner / notification center can react
-- without a manual fetch.
DO $$
BEGIN
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.alert_dispatch';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
