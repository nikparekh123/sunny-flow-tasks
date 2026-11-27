-- Sundial's written review (Nik, 27 Nov 2026, part 3 of the inspection). sundial-review saves Claude's daily review on
-- the inspection it read: a verdict, a line per name, and anything worth a look.
alter table public.sundial_inspections add column if not exists review jsonb;
alter table public.sundial_inspections add column if not exists review_at timestamptz;
