/* ============================================================
   INTU out, NFLX in.

   ── Why INTU goes ──────────────────────────────────────────────────────────
   Its 7-day implied sits at 46 against 20-day realised of 49. You would be
   selling a week of volatility for less than the stock has actually been
   delivering, which is the one disqualifier this whole sleeve rests on.

   It never qualified. The +11.6 edge it was picked on was the clock bug fixed
   in income-sleeve on 2026-08-17: time to expiry was taken from the wall clock
   while Polygon served the previous close, so a Friday price for the coming
   Friday was divided by 5 days of life when it was bought with 7. Implied vol
   came out ~18% high on every name.

   Two lesser reasons, both real: INTU is 64% off its high with a -20% single
   session in May, so it is still being repriced rather than settled at a low;
   and at $346 one contract commits $34,600, so six contracts is the entire
   block and a single assignment is a third of the position.

   Deactivated, not deleted. The row carries real history and its started_on,
   and a later backfill should still be able to see it.

   ── Why NFLX ───────────────────────────────────────────────────────────────
   Chosen from 74 names screened on 2026-08-17. The only one clearing every
   gate at once:

     edge          +2.0, measured off the quote's own session
     52w range     18% up it
     correlation   -0.01 NVDA, -0.04 TLT, 0.10 NKE, 0.17 LULU, over 250 days,
                   which is the least correlated name in the entire screen
     liquidity     weekly expiries with tradeable strikes either side of spot

   Runner-up was ZTS: 2% up its 52-week range, the lowest of all 74, and a
   better yield. Rejected because its edge is +0.2. Selling volatility at fair
   value earns nothing from the sale itself, only from the direction, which is
   a different strategy than this one.

   Two names screened BETTER than everything else and were thrown out for it:
   EL at +53.1 and PYPL at +34.9. A 7-day option priced 50 vol points above
   realised is the market pricing an event inside that week which the screen
   cannot see. An enormous edge is a trap, not a find.

   ── The earnings date is real, not inferred ────────────────────────────────
   NFLX reports 2026-10-20 (supplied by Nik). Inferring dates from the tape was
   tested against the three known dates and came out 31, 29 and 120 days wrong,
   so the sleeve does not guess: a name with no future date on file now SKIPs
   and says so.
   ============================================================ */

update public.income_sleeve_names
   set active = false,
       note   = 'Removed 2026-08-17: 7-day implied 46 against 20-day realised 49, '
                'so the sale is underpaid. The original +11.6 edge was the weekend '
                'clock bug. Also 64% off its high with a -20% single day in May.'
 where ticker = 'INTU';

insert into public.income_sleeve_names (ticker, active, sort, target_shares, started_on, note)
values ('NFLX', true, 1, 0, '2026-08-17',
        'Replaced INTU 2026-08-17. Edge +2.0 correctly timed. 18% up the 52w range. '
        'Max correlation 0.17 across 250 days to NVDA/TLT/NKE/LULU.')
on conflict (ticker) do update
   set active = true, sort = 1, started_on = '2026-08-17', note = excluded.note;

insert into public.earnings_events (ticker, report_date, fiscal_period, scope_tag)
values ('NFLX', '2026-10-20', 'FY26 Q3', 'position')
on conflict (ticker, report_date) do nothing;

select ticker, active, sort, started_on from public.income_sleeve_names
 order by active desc, sort;

/* Each name goes to a permanent SKIP once its one date on file has passed, which
   is the guard working rather than a fault. LULU's runs out on 27 Aug 2026,
   NKE's on 24 Sep. Real dates for the next two quarters are still needed. */
select ticker, report_date from public.earnings_events
 where ticker in ('NFLX', 'NKE', 'LULU') and report_date >= current_date
 order by report_date;
