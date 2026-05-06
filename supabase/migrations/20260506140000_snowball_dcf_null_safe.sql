-- Make snowball_dcf_intrinsic return null (not 0) when owner earnings is
-- missing. Treating null as 0 gave misleading "$0 intrinsic" rows for any
-- ticker where Polygon hadn't returned financials yet.
create or replace function public.snowball_dcf_intrinsic(
  oe       numeric,
  shares   numeric,
  g        numeric,
  d        numeric,
  tg       numeric
)
returns numeric
language sql
immutable
as $$
  select case
    when oe is null                         then null
    when coalesce(shares, 0) <= 0           then null
    when coalesce(d, 0) <= coalesce(tg, 0)  then null
    else (
      (select coalesce(sum(
        oe * power(1 + g, y) / power(1 + d, y)
      ), 0) from generate_series(1, 10) as y)
      + (oe * power(1 + g, 10) * (1 + tg) / (d - tg))
        / power(1 + d, 10)
    ) / shares
  end;
$$;
