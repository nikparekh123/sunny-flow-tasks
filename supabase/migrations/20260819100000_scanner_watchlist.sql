/* ============================================================
   income_scanner_universe.watch, the watchlist

   A name Nik likes that does not clear yet. BIDU is the first: edge +13.7,
   20,241 open interest, correlation 0.05 to the book, sitting 5% up its
   52-week range. It fails on two things only, and both are yesterday's
   earnings: down 29% over three months against a 15% gate, and 50% realised
   vol against a 45% ceiling. Neither is permanent. As the drop ages out of the
   three-month window it clears on its own.

   Watched names are already scanned, they are in the universe, so this stores
   no new facts. It only says which rejections Nik wants reported back instead
   of silently dropped. The Income screen reads it and says what each watched
   name is still waiting on, and when one clears it also appears as a card in
   'Clear to add' by the normal route.

   NOT wired to push. Every category in alert_dispatch reads delivered = 0
   across 2,581 rows, so a notification here would join a backlog that is not
   being sent. That is its own bug and its own fix.
   ============================================================ */

alter table public.income_scanner_universe
  add column if not exists watch boolean not null default false;

comment on column public.income_scanner_universe.watch is
  'Report this name on the Income screen even when it fails, with the gates it '
  'is still waiting on. For names worth having but not yet eligible.';

insert into public.income_scanner_universe (ticker, watch, note)
values ('BIDU', true, 'watch: waiting out the 18 Aug earnings drop')
on conflict (ticker) do update
   set watch = true, active = true;

notify pgrst, 'reload schema';

select u.ticker, u.watch, r.passes, r.fails
  from public.income_scanner_universe u
  left join public.income_scanner_results r
         on r.ticker = u.ticker
        and r.asof = (select max(asof) from public.income_scanner_results)
 where u.watch
 order by u.ticker;
