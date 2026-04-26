-- ─────────────────────────────────────────────────────────────────────────
-- Research Hub redesign — tag-driven, no sectors/types.
-- Reshape the existing `reports` table and add a `tags` metadata table.
-- All actions guarded with IF EXISTS / IF NOT EXISTS so this is safe to
-- re-run.
-- ─────────────────────────────────────────────────────────────────────────

-- 1) Reshape `reports`: drop sector/type/visibility columns, add the
--    fields the new card system needs.

-- Drop columns we no longer surface anywhere.
ALTER TABLE public.reports DROP COLUMN IF EXISTS report_type;
ALTER TABLE public.reports DROP COLUMN IF EXISTS primary_sector;
ALTER TABLE public.reports DROP COLUMN IF EXISTS sectors;
ALTER TABLE public.reports DROP COLUMN IF EXISTS tickers;       -- merged into tags
ALTER TABLE public.reports DROP COLUMN IF EXISTS author;        -- replaced by author_id
ALTER TABLE public.reports DROP COLUMN IF EXISTS published_at;  -- created_at is the date
ALTER TABLE public.reports DROP COLUMN IF EXISTS read_minutes;
ALTER TABLE public.reports DROP COLUMN IF EXISTS visibility;    -- members-only access via RLS

-- Rename summary → description for naming consistency with the new design.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='reports' AND column_name='summary')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='reports' AND column_name='description')
  THEN
    ALTER TABLE public.reports RENAME COLUMN summary TO description;
  END IF;
END $$;

-- Rename file_path → file_url for the same reason.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='reports' AND column_name='file_path')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='reports' AND column_name='file_url')
  THEN
    ALTER TABLE public.reports RENAME COLUMN file_path TO file_url;
  END IF;
END $$;

-- New columns for the redesign.
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS featured  BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pinned    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS size      TEXT
    CHECK (size IS NULL OR size IN ('xl','l','wide','m','s')),
  ADD COLUMN IF NOT EXISTS author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS description TEXT;

-- Belt-and-suspenders: the existing `tags TEXT[] DEFAULT '{}'` column stays.
-- Make sure the default and not-null guards are present.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='reports' AND column_name='tags') THEN
    ALTER TABLE public.reports ADD COLUMN tags TEXT[] NOT NULL DEFAULT '{}';
  END IF;
END $$;

-- GIN index for fast tag membership queries.
CREATE INDEX IF NOT EXISTS idx_reports_tags ON public.reports USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON public.reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_featured ON public.reports(featured) WHERE featured;
CREATE INDEX IF NOT EXISTS idx_reports_pinned ON public.reports(pinned) WHERE pinned;

-- Tighten RLS: only members can do anything. Drop the old open policies
-- and replace with member-gated ones.
DROP POLICY IF EXISTS "Public can view reports"   ON public.reports;
DROP POLICY IF EXISTS "Public can insert reports" ON public.reports;
DROP POLICY IF EXISTS "Public can update reports" ON public.reports;
DROP POLICY IF EXISTS "Public can delete reports" ON public.reports;

-- Helper: is the current authed user in the members allowlist?
-- Uses the existing public.is_member(text) function.
DROP POLICY IF EXISTS "Members can read reports"   ON public.reports;
DROP POLICY IF EXISTS "Members can insert reports" ON public.reports;
DROP POLICY IF EXISTS "Members can update reports" ON public.reports;
DROP POLICY IF EXISTS "Members can delete reports" ON public.reports;

CREATE POLICY "Members can read reports"
  ON public.reports FOR SELECT
  USING ( public.is_member((auth.jwt() ->> 'email')::text) );

CREATE POLICY "Members can insert reports"
  ON public.reports FOR INSERT
  WITH CHECK ( public.is_member((auth.jwt() ->> 'email')::text) );

CREATE POLICY "Members can update reports"
  ON public.reports FOR UPDATE
  USING ( public.is_member((auth.jwt() ->> 'email')::text) );

CREATE POLICY "Members can delete reports"
  ON public.reports FOR DELETE
  USING ( public.is_member((auth.jwt() ->> 'email')::text) );


-- 2) New `tags` metadata table — canonical name + pin/description.
--    Defensive: an older `tags` table may already exist from a prior
--    research-hub schema, so we add columns one-by-one with IF NOT EXISTS.
CREATE TABLE IF NOT EXISTS public.tags (
  name TEXT PRIMARY KEY
);

ALTER TABLE public.tags
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS pinned      BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can read tags"   ON public.tags;
DROP POLICY IF EXISTS "Members can insert tags" ON public.tags;
DROP POLICY IF EXISTS "Members can update tags" ON public.tags;
DROP POLICY IF EXISTS "Members can delete tags" ON public.tags;

CREATE POLICY "Members can read tags"
  ON public.tags FOR SELECT
  USING ( public.is_member((auth.jwt() ->> 'email')::text) );

CREATE POLICY "Members can insert tags"
  ON public.tags FOR INSERT
  WITH CHECK ( public.is_member((auth.jwt() ->> 'email')::text) );

CREATE POLICY "Members can update tags"
  ON public.tags FOR UPDATE
  USING ( public.is_member((auth.jwt() ->> 'email')::text) );

CREATE POLICY "Members can delete tags"
  ON public.tags FOR DELETE
  USING ( public.is_member((auth.jwt() ->> 'email')::text) );


-- 3) Trigger: when a report is inserted with a new tag, auto-create the
--    tag metadata row. This is what makes "tagging with #foo creates the
--    /tags/foo area page" promise true.
CREATE OR REPLACE FUNCTION public.ensure_tags_exist()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t TEXT;
BEGIN
  IF NEW.tags IS NOT NULL THEN
    FOREACH t IN ARRAY NEW.tags LOOP
      INSERT INTO public.tags (name) VALUES (t)
      ON CONFLICT (name) DO NOTHING;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reports_ensure_tags ON public.reports;
CREATE TRIGGER reports_ensure_tags
AFTER INSERT OR UPDATE OF tags ON public.reports
FOR EACH ROW EXECUTE FUNCTION public.ensure_tags_exist();


-- 4) View: tag rollups (count, last_updated) — used by the rail and search.
--    Group classification (TICKER / THEME / CUSTOM) is derived in the app
--    layer from the tag name; PINNED comes from tags.pinned.
CREATE OR REPLACE VIEW public.tag_stats AS
SELECT
  t.name,
  t.pinned,
  t.description,
  COALESCE(c.count, 0)::INT     AS count,
  COALESCE(c.last_updated, t.created_at) AS last_updated
FROM public.tags t
LEFT JOIN (
  SELECT
    UNNEST(tags)        AS name,
    COUNT(*)::INT       AS count,
    MAX(created_at)     AS last_updated
  FROM public.reports
  GROUP BY UNNEST(tags)
) c ON c.name = t.name;

GRANT SELECT ON public.tag_stats TO authenticated, anon;


-- 5) Convenience: "often appears with" — for each tag, the top co-occurring
--    tags. Cheap enough to compute on demand for now.
CREATE OR REPLACE FUNCTION public.related_tags(p_tag TEXT, p_limit INT DEFAULT 8)
RETURNS TABLE(name TEXT, count INT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT other AS name, COUNT(*)::INT AS count
  FROM public.reports r,
       UNNEST(r.tags) AS other
  WHERE p_tag = ANY(r.tags) AND other <> p_tag
  GROUP BY other
  ORDER BY count DESC, other ASC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.related_tags(TEXT, INT) TO authenticated, anon;
