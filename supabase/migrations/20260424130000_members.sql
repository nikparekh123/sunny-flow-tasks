-- Allowed users for the Sunnyfi tool hub.
-- Anyone signing in via magic link must have their email here, otherwise the
-- app signs them out client-side after the auth round-trip.

-- Clean up the now-unused passcode rate-limit table from the previous flow.
DROP TABLE IF EXISTS public.passcode_attempts;

CREATE TABLE public.members (
  email        TEXT PRIMARY KEY,
  display_name TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;

-- Each authenticated user can read their own row (used to gate access).
-- We compare lowercased email to handle Supabase's email casing.
CREATE POLICY "members_self_read"
  ON public.members FOR SELECT
  TO authenticated
  USING (lower(email) = lower(auth.jwt() ->> 'email'));

-- Seed the team. (Lower-cased — magic link sign-in normalizes to lowercase.)
INSERT INTO public.members (email, display_name) VALUES
  ('nik@sunnyfi.co',    'Nik'),
  ('ary@sunnyfi.co',    'Ary'),
  ('kushal@sunnyfi.co', 'Kushal'),
  ('rads@sunnyfi.co',   'Rads');

-- Tighten existing tables: remove the wide-open policies and require the
-- caller to be a member. This means: signing in via magic link is necessary
-- to read/write reports; passcode flow no longer applies.
DROP POLICY IF EXISTS "Public can view reports"   ON public.reports;
DROP POLICY IF EXISTS "Public can insert reports" ON public.reports;
DROP POLICY IF EXISTS "Public can update reports" ON public.reports;
DROP POLICY IF EXISTS "Public can delete reports" ON public.reports;

CREATE POLICY "members_view_reports"   ON public.reports FOR SELECT
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

CREATE POLICY "members_insert_reports" ON public.reports FOR INSERT
  TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

CREATE POLICY "members_update_reports" ON public.reports FOR UPDATE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

CREATE POLICY "members_delete_reports" ON public.reports FOR DELETE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

-- Storage bucket: same tightening for HTML files.
DROP POLICY IF EXISTS "Public can view report files"   ON storage.objects;
DROP POLICY IF EXISTS "Public can upload report files" ON storage.objects;
DROP POLICY IF EXISTS "Public can update report files" ON storage.objects;
DROP POLICY IF EXISTS "Public can delete report files" ON storage.objects;

CREATE POLICY "members_view_report_files"   ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'reports' AND EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

CREATE POLICY "members_upload_report_files" ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'reports' AND EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

CREATE POLICY "members_update_report_files" ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'reports' AND EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));

CREATE POLICY "members_delete_report_files" ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'reports' AND EXISTS (SELECT 1 FROM public.members m WHERE lower(m.email) = lower(auth.jwt() ->> 'email')));
