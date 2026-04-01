
-- Create separate pincodes table
CREATE TABLE public.member_pincodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  pincode text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_pincodes ENABLE ROW LEVEL SECURITY;

-- Only own user can read their pincode
CREATE POLICY "own pincode select"
ON public.member_pincodes FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- Only own user can update their pincode
CREATE POLICY "own pincode update"
ON public.member_pincodes FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Migrate existing pincodes
INSERT INTO public.member_pincodes (user_id, pincode)
SELECT user_id, pincode FROM public.team_members WHERE pincode IS NOT NULL;

-- Drop pincode from team_members
ALTER TABLE public.team_members DROP COLUMN pincode;
