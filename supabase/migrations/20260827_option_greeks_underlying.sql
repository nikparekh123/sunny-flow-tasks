-- Applied to prod 2026-08-27 via the Management API.
--
-- Stamp the underlying price ALONGSIDE the mark. Polygon's option snapshot
-- carries its own underlying_asset.price; without it, intrinsic value was
-- computed from ticker_quotes_latest, which mp-refresh writes in a SECOND call
-- on its own clock and skips entirely when the stock snapshot returns null.
-- On a deep-ITM leg whose extrinsic is a few cents, that drift made intrinsic
-- exceed the mark and time value go negative: CEG 272.5 −$14, NKE 40.5 −$110,
-- PEP 144 −$140, and the book's time value came out $264 light.

alter table option_greeks add column if not exists underlying numeric;

comment on column option_greeks.underlying is
 'The underlying price Polygon quoted alongside this mark, from the option snapshot''s own underlying_asset.price. Stamped so intrinsic is computed against the spot that was live when the mark was taken. Null before 2026-08-27 and whenever Polygon omits it; read paths fall back to ticker_quotes_latest.';

-- A new column cannot be inserted mid-list into an existing view, so the view is
-- dropped and rebuilt rather than replaced. It is a plain read view.
drop view if exists option_greeks_latest;
create view option_greeks_latest as
 select distinct on (option_trade_id)
   option_trade_id, delta, gamma, theta, vega, iv,
   open_interest, volume, last_mark, underlying, captured_at, id
 from option_greeks
 order by option_trade_id, captured_at desc;
grant select on option_greeks_latest to anon, authenticated, service_role;
