/* ============================================================
   push_devices — APNs device tokens
   ============================================================
   The iOS app registers its push token here on every launch (or
   when the system rotates the token). The `apns-deliver` worker
   uses this to fan out alert_dispatch rows to every active
   device.

   environment is needed because debug builds (Xcode → Run on
   simulator/device) get tokens from the APNs sandbox server and
   TestFlight/App Store builds get tokens from the production
   server. Same token format, different routing. Storing the env
   alongside each token lets the worker pick the right URL.
   ============================================================ */

CREATE TABLE IF NOT EXISTS public.push_devices (
  -- The 64-char hex token is itself the natural unique id.
  token         text PRIMARY KEY,
  environment   text NOT NULL CHECK (environment IN ('sandbox','production')),
  -- Bundle id — defensive, in case we ever ship multiple apps.
  bundle_id     text NOT NULL,
  -- Free-form OS/device info for debugging ("iPhone 17 Pro · iOS 26.5").
  device_label  text,
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_devices_bundle_env
  ON public.push_devices (bundle_id, environment);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;

-- Authenticated users can insert/update their own device row. We
-- don't tie devices to a Supabase user_id because the team account
-- is shared — every signed-in client should be able to register.
DROP POLICY IF EXISTS "push_devices: authenticated upsert" ON public.push_devices;
CREATE POLICY "push_devices: authenticated upsert"
  ON public.push_devices
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);
