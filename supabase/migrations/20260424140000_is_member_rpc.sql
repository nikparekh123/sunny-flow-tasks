-- Public RPC the landing uses to validate an email before sending the
-- magic link. Returns just a boolean — never exposes the member list.

CREATE OR REPLACE FUNCTION public.is_member(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.members WHERE lower(email) = lower(p_email)
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_member(TEXT) TO anon, authenticated;
