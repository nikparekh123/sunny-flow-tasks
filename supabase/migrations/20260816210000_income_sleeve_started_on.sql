/* ============================================================
   income_sleeve_names.started_on — the date the sleeve began.

   The sleeve reads the LEGACY option_trades / share_lots / share_sells filtered
   by ticker, and those tables hold positions Nik USED to have. On 2026-08-16 the
   screen showed 200 INTU, 48 NKE and 500 LULU that he no longer holds, with
   averages (254.93, 27.97, 100.36) computed off them. All real history, none of
   it this strategy.

   Voiding those rows would have been wrong: they belong to the ledger. So the
   sleeve simply does not look before its own start date, and everything earlier
   stays where it is.

   The original table migration (20260815090000) never created this column —
   index.ts read n.started_on against a column that did not exist, which is why
   two attempts to set it appeared to do nothing. add column if not exists is the
   whole fix.
   ============================================================ */

alter table public.income_sleeve_names
  add column if not exists started_on date;

comment on column public.income_sleeve_names.started_on is
  'First day this name counts toward the sleeve. Trades and lots dated before it '
  'are ignored here (they remain in the ledger). Null means count everything.';

update public.income_sleeve_names
   set started_on = '2026-08-17'
 where ticker in ('INTU', 'NKE', 'LULU')
   and started_on is null;

select ticker, active, sort, target_shares, started_on
  from public.income_sleeve_names order by sort;
