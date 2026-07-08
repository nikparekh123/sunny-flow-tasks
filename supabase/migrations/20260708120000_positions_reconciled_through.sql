/* ============================================================
   positions.reconciled_through — intraday share accuracy (#17)
   ============================================================
   The nightly reconcile (ibkr-flex-sync) sets positions.quantity to
   IBKR's OpenPositions as of the report's latest trading day. That's
   the "overnight baseline" — correct as of last close, T+1 for
   today's trades.

   To show today's share trades within ~15 min (instead of waiting
   for tomorrow's reconcile), the app layers today's captured trades
   on top of that baseline:

     displayed shares = positions.quantity
                      + Σ share_lots buys  (acquired_date > reconciled_through)
                      − Σ share_sells sells (trade_date    > reconciled_through)

   For that the app needs to know WHICH date the baseline is current
   as-of. This column stores it — the reportDate the reconcile used.
   Nullable: rows never reconciled (legacy / manual) fall back to the
   raw quantity with no intraday layering (safe default).
   ============================================================ */

alter table public.positions
  add column if not exists reconciled_through date;

comment on column public.positions.reconciled_through is
  'The IBKR report date that positions.quantity is current as-of. '
  'Set by ibkr-flex-sync reconcilePositions. The app adds share '
  'trades dated AFTER this to show intraday activity before the next '
  'overnight reconcile folds them into the baseline.';
