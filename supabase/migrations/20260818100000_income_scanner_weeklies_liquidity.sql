/* ============================================================
   income_scanner_results, the two columns the scanner already writes

   The table was created on 2026-08-17. The weeklies gate (the one Nik caught:
   "ZTS fails it doesnt have weekly options") and the liquidity word were added
   to the function AFTER it, and nothing ever added their columns.

   So every write since has been a PostgREST 400, "column weeklies does not
   exist", and the shared db().upsert helper only catches THROWN errors:

       try { await fetch(...) } catch { }

   A 400 is a perfectly good Response, so it fell straight through the catch and
   the run reported "passed: 12" while writing nothing at all. The Income
   screen's scanner block reads this table, found it empty, and emitted
   scanner: null, which is why the card never appeared.

   Same failure family as the earnings_events column-name bug documented in
   income-sleeve: a swallowed PostgREST error that fails silently instead of
   loudly. The helper is fixed alongside this to report the write.
   ============================================================ */

alter table public.income_scanner_results
  add column if not exists weeklies  int,
  add column if not exists liquidity text;

comment on column public.income_scanner_results.weeklies is
  'Distinct expiries in the next five weeks. A weekly name has 4-5, a monthly '
  'has 1. Gated at 3+, it cannot be inferred from the coming Friday alone, '
  'because on a third Friday every optionable name has contracts.';

comment on column public.income_scanner_results.liquidity is
  'thin | fine | deep, from open interest across ±5% of spot. Reported, never '
  'gated: the floor is 50 and everything above it passes.';

notify pgrst, 'reload schema';

select ticker, asof, passes, weeklies, liquidity
  from public.income_scanner_results
 order by asof desc, passes desc, ticker
 limit 20;
