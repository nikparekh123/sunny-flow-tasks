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
  ('LULU','R1',96.70),('LULU','R2',97.56),('LULU','R3',98.01)
on conflict (ticker, kind, price) do nothing;

-- ⚠ THESE ARE DAILY PIVOTS AND THEY ARE NARROW. NKE's seven span $0.69 on a
-- $36.62 stock. The chart's default range is the spot +/- 27%, so all seven
-- land inside about 48px of a 1362px plot and the label band collapses them
-- into one "7 LEVELS" chip. Narrowing the range slider spreads them. If the
-- chart is meant to read them at a glance at full range, weekly or monthly
-- pivots are the ones that span far enough to be worth drawing.
