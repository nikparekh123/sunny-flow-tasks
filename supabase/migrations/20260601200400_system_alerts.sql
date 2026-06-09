/* ============================================================
   system_alerts — first-class "something is broken" channel
   ============================================================
   Written by the `health-monitor` cron when it detects:
   • mp-refresh-15min hasn't completed in > 20 min during market hours
   • daily-theta-snapshot didn't write a row last night
   • position-snapshot didn't write rows yesterday
   • polygon API errors are spiking

   The iOS client subscribes to this table via realtime and renders
   a non-dismissible top banner whenever an `active` alert exists.
   It also fans into a critical-tier push notification (added in
   Wave C).

   Each alert has a stable `code` so we can dedupe ("don't fire a
   new alert if one is already active for this code"). When the
   underlying issue clears we mark the row resolved with
   `resolved_at`; the banner disappears.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.system_alerts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL,                -- stable identifier, e.g. 'cron.mp_refresh_stale'
  severity     text NOT NULL DEFAULT 'warn' CHECK (severity IN ('info','warn','critical')),
  title        text NOT NULL,
  detail       text,
  -- Free-form context (e.g. last-seen-at, error snippet).
  meta         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz
);

-- One active alert per code at a time. A second alert with the
-- same code while the first is unresolved gets folded into the
-- existing row (helper RPC below).
CREATE UNIQUE INDEX IF NOT EXISTS idx_system_alerts_code_active
  ON public.system_alerts (code) WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_system_alerts_created_at
  ON public.system_alerts (created_at DESC);

ALTER TABLE public.system_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "system_alerts: authenticated read"
  ON public.system_alerts;
CREATE POLICY "system_alerts: authenticated read"
  ON public.system_alerts FOR SELECT TO authenticated USING (true);

-- Realtime so the banner appears immediately.
DO $$
BEGIN
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.system_alerts';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ─── Helper RPCs for the monitor ────────────────────────────────
-- Raise an alert: create a new row OR refresh the existing active
-- one (touches updated_at via meta merge).
CREATE OR REPLACE FUNCTION public.raise_system_alert(
  p_code text,
  p_severity text,
  p_title text,
  p_detail text,
  p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_id uuid;
BEGIN
  SELECT id INTO existing_id
  FROM public.system_alerts
  WHERE code = p_code AND resolved_at IS NULL
  LIMIT 1;

  IF existing_id IS NOT NULL THEN
    -- Refresh detail/meta on the existing active alert.
    UPDATE public.system_alerts
    SET title = p_title,
        detail = p_detail,
        severity = p_severity,
        meta = p_meta
    WHERE id = existing_id;
    RETURN existing_id;
  END IF;

  INSERT INTO public.system_alerts (code, severity, title, detail, meta)
  VALUES (p_code, p_severity, p_title, p_detail, p_meta)
  RETURNING id INTO existing_id;
  RETURN existing_id;
END $$;

-- Clear an alert: mark active row(s) with this code as resolved.
CREATE OR REPLACE FUNCTION public.clear_system_alert(p_code text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected integer;
BEGIN
  UPDATE public.system_alerts
  SET resolved_at = now()
  WHERE code = p_code AND resolved_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END $$;

REVOKE ALL ON FUNCTION public.raise_system_alert(text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_system_alert(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.raise_system_alert(text, text, text, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.clear_system_alert(text) TO service_role;
