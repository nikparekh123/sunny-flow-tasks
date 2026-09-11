-- Support and resistance: the vocabulary, not the rows.
--
-- The kind CHECK allowed only 'support' and 'resistance', and payoff-book uses
-- `kind` AS THE LABEL on the chart, so seven levels would all have read
-- "SUPPORT" or "RESISTANCE" and a pivot is neither. The vocabulary widens to
-- carry the names Nik actually uses. The old two stay valid.
alter table public.ticker_levels drop constraint if exists ticker_levels_kind_check;
alter table public.ticker_levels add constraint ticker_levels_kind_check
  check (kind in ('support','resistance','pivot','S1','S2','S3','R1','R2','R3','Pivot'));

-- ⚠ DAILY PIVOTS WERE LOADED HERE AND THEN REMOVED, 2026-09-11. Keep the
-- reason, because the next person with a pivot table will try the same thing.
--
-- A daily classic pivot set spans under 3% of the price; this chart is drawn to
-- hold a 54% move. Measured at the default range as pixels between adjacent
-- levels on a 1362px plot:
--
--   PEP 2   BABA 4   NFLX 4   FIS 6   KR 8   NKE 8   LULU 17
--
-- The label band clusters anything under 34px into one "N LEVELS" chip, so
-- every name collapsed to a single chip. The range slider bottoms out at
-- +/- 10% and even there only LULU separated. Nik: "Remove this let me send you
-- weekly this is very close."
--
-- Weekly or monthly pivots span far enough to be worth drawing. The table is
-- left empty and waiting for them.
