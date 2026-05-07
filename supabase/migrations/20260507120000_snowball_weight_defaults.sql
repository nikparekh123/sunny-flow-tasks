-- ─────────────────────────────────────────────────────────────────────────
-- Snowball — fix weight column defaults so newly-added stocks get the
-- correct 30/25/20/15/10 split. Earlier migrations only UPDATEd existing
-- rows; the column defaults still pointed at old values, so addStock()
-- inserts were ending up with weights summing to 135%.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.snowball
  alter column weight_dcf            set default 0.30,
  alter column weight_pe             set default 0.15,
  alter column weight_ev_ebitda      set default 0.20,
  alter column weight_epv            set default 0.25,
  alter column weight_earnings_yield set default 0.10;

-- Force every existing row to the correct split, regardless of what
-- they have now. This overwrites any per-stock weight customizations —
-- if you've tuned weights for individual stocks, those will be reset.
update public.snowball
set
  weight_dcf            = 0.30,
  weight_pe             = 0.15,
  weight_ev_ebitda      = 0.20,
  weight_epv            = 0.25,
  weight_earnings_yield = 0.10;
