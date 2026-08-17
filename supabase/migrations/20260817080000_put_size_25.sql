/* ============================================================
   Put size: 25 contracts a week, per name. Nik, 2026-08-17.

   Until now put_contracts was null, which means "one per 100 shares held" —
   the rule that doubles the block on every assignment. On NKE's own returns
   over ten weeks that compounding is the whole distance between a median
   average 13% below the market and a 70% loss in the worst 5%.

   25 is his number, from the margin he can see, and it matches the floor he
   priced: 125 contracts covers 10,000 shares plus 2,500 of short puts.

   ── The thing to watch ─────────────────────────────────────────────────────
   A FIXED CONTRACT COUNT IS A VERY DIFFERENT DOLLAR COMMITMENT PER NAME,
   because the share prices are not alike:

     NKE   25 x  39 x 100 = $ 97,500
     NFLX  25 x  76 x 100 = $190,000
     LULU  25 x 116 x 100 = $290,000
                             --------
                             $577,500 committed across three names

   That is not what "the same size on each" usually means. If the intent is
   equal money rather than equal contracts, the counts want to be roughly
   25 / 13 / 8. Left as asked; recorded so it is a choice and not a surprise.
   ============================================================ */

update public.income_sleeve_names
   set put_contracts = 25
 where active and ticker in ('NKE', 'NFLX', 'LULU');

select ticker, active, put_contracts, started_on
  from public.income_sleeve_names
 order by active desc, sort;
