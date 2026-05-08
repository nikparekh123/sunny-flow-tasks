-- Snowball: per-stock tags.
-- Free-form text labels users attach to companies (e.g. "compounder",
-- "AI infra", "watch earnings"). The Snowball UI also exposes a tag
-- filter in the toolbar, so we add a GIN index for cheap @> / && lookups.

ALTER TABLE public.snowball
  ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE INDEX IF NOT EXISTS snowball_tags_gin
  ON public.snowball
  USING GIN (tags);

COMMENT ON COLUMN public.snowball.tags IS
  'User-defined free-form labels. Lower-cased, unique per stock. Edited from the per-stock drawer.';
