
-- 1. Fix role escalation: replace the permissive own-update policy
-- Drop the old policy that allows updating ANY column
DROP POLICY IF EXISTS "team_members: own update" ON public.team_members;

-- Create a restricted own-update policy that prevents role/status changes
-- Users can only update safe fields on their own row
CREATE POLICY "team_members: own update safe"
ON public.team_members
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (
  auth.uid() = user_id
  AND role = (SELECT tm.role FROM public.team_members tm WHERE tm.user_id = auth.uid())
  AND status = (SELECT tm.status FROM public.team_members tm WHERE tm.user_id = auth.uid())
);

-- 2. Fix avatar storage policies with ownership checks
-- Drop existing overly-permissive policies
DROP POLICY IF EXISTS "avatars: own delete" ON storage.objects;
DROP POLICY IF EXISTS "avatars: own update" ON storage.objects;
DROP POLICY IF EXISTS "avatars: authenticated upload" ON storage.objects;

-- Recreate with path-based ownership
CREATE POLICY "avatars: own upload"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars: own update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "avatars: own delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
