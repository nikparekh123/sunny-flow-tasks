-- Support and resistance, first real rows. Nik sent classic daily pivots per
-- name on 2026-09-11.
--
-- The kind CHECK only allowed 'support' and 'resistance', and payoff-book uses
-- `kind` AS THE LABEL on the chart. Seven levels all reading "SUPPORT" or
-- "RESISTANCE" says nothing, and a pivot is neither, so the vocabulary widens
-- to carry the names he actually uses. The old two stay valid.
alter table public.ticker_levels drop constraint if exists ticker_levels_kind_check;
alter table public.ticker_levels add constraint ticker_levels_kind_check
  check (kind in ('support','resistance','pivot','S1','S2','S3','R1','R2','R3','Pivot'));

insert into public.ticker_levels (ticker, kind, price) values
  ('NKE','S3',36.30),('NKE','S2',36.45),('NKE','S1',36.53),('NKE','Pivot',36.68),
  ('NKE','R1',36.76),('NKE','R2',36.91),('NKE','R3',36.99),
  ('NFLX','S3',75.46),('NFLX','S2',75.64),('NFLX','S1',75.73),('NFLX','Pivot',75.91),
  ('NFLX','R1',76.00),('NFLX','R2',76.18),('NFLX','R3',76.27),
  ('BABA','S3',108.32),('BABA','S2',108.51),('BABA','S1',108.68),('BABA','Pivot',108.87),
  ('BABA','R1',109.04),('BABA','R2',109.23),('BABA','R3',109.40),
  ('LULU','S3',94.07),('LULU','S2',94.94),('LULU','S1',95.39),('LULU','Pivot',96.25),
  ('LULU','R1',96.70),('LULU','R2',97.56),('LULU','R3',98.01),
  ('FIS','S3',38.01),('FIS','S2',38.13),('FIS','S1',38.20),('FIS','Pivot',38.32),
  ('FIS','R1',38.40),('FIS','R2',38.51),('FIS','R3',38.59),
  ('KR','S3',56.09),('KR','S2',56.32),('KR','S1',56.45),('KR','Pivot',56.68),
  ('KR','R1',56.81),('KR','R2',57.04),('KR','R3',57.17),
  ('PEP','S3',136.58),('PEP','S2',136.71),('PEP','S1',136.82),('PEP','Pivot',136.95),
  ('PEP','R1',137.06),('PEP','R2',137.19),('PEP','R3',137.30)
on conflict (ticker, kind, price) do nothing;

-- ⚠ THESE ARE DAILY PIVOTS AND THE CHART CANNOT SEPARATE THEM. Measured at the
-- default range, spot +/- 27%, as pixels between adjacent levels on a 1362px
-- plot. The label band clusters anything under 34px into one "N LEVELS" chip:
--
--   PEP 2   BABA 4   NFLX 4   FIS 6   KR 8   NKE 8   LULU 17
--
-- Every one of them clusters. The range slider bottoms out at +/- 10%, and even
-- there only LULU separates (46px); NKE reaches 21px and PEP 6px. This is a
-- scale mismatch, not a drawing bug: a daily pivot set spans well under 3% of
-- the price while the chart is drawn to hold a 54% move. Weekly or monthly
-- pivots span far enough to be worth drawing at this scale.
