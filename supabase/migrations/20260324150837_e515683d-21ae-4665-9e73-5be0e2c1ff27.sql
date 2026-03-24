ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS preferences jsonb NOT NULL DEFAULT '{}';

CREATE POLICY "team_members: admin update any"
ON public.team_members
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.team_members tm
    WHERE tm.user_id = auth.uid() AND tm.role = 'admin'::member_role
  )
);

CREATE TABLE public.user_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  content text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_notes: own select"
ON public.user_notes FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "user_notes: own insert"
ON public.user_notes FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_notes: own update"
ON public.user_notes FOR UPDATE TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "user_notes: own delete"
ON public.user_notes FOR DELETE TO authenticated
USING (user_id = auth.uid());

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "avatars: authenticated upload"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "avatars: public read"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'avatars');

CREATE POLICY "avatars: own update"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'avatars');

CREATE POLICY "avatars: own delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'avatars');