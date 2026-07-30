/* ============================================================
   nvda_iv_daily — columns the Seller Score IV feed (nvda-iv fn) needs.
   The original table was date-PK with atm_iv; the app reads `ticker`
   + `iv`. Make the shape explicit + idempotent so the feed's upsert
   (onConflict 'date', writing ticker/iv/source) always succeeds.
   ============================================================ */
alter table public.nvda_iv_daily add column if not exists ticker text default 'NVDA';
alter table public.nvda_iv_daily add column if not exists iv     numeric;
alter table public.nvda_iv_daily add column if not exists source text;

-- backfill ticker on any pre-existing rows
update public.nvda_iv_daily set ticker = 'NVDA' where ticker is null;

-- if older rows only carry atm_iv, mirror it into iv so the app sees them
update public.nvda_iv_daily set iv = atm_iv where iv is null and atm_iv is not null;
