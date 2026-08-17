/* ============================================================
   The income sleeve: several names, one rule.

   Spec: docs/INCOME_SLEEVE_SPEC.md

   Own a block, sell an ATM call and an ATM put weekly, and hold a long-dated
   out-of-the-money put as a floor that the weekly premium pays for.

   Deliberately ONE table. The positions themselves live in the existing
   option_trades / share_lots / share_sells, which already carry a ticker column
   and are already populated by ibkr-flex-sync for any symbol traded. NVDA and
   TLT needed their own mirrored stores; this does not.
   ============================================================ */

create table if not exists public.income_sleeve_names (
  ticker          text primary key,
  active          boolean not null default true,
  sort            int     not null default 0,

  -- the block this name is meant to hold. Puts refill toward it; calls are
  -- written against whatever is actually held, never against pending assignment.
  target_shares   int     not null default 0,

  -- the floor. Bought once, rolled before it expires. cost_total is what was
  -- actually paid, so "funded" can be measured against real money rather than
  -- a model price.
  floor_strike    numeric,
  floor_expiry    date,
  floor_contracts int,
  floor_cost      numeric,          -- total $ paid, not per share
  floor_bought_on date,

  -- premium counted since the floor was bought, for the funded calculation.
  -- Maintained by the function, not by hand.
  note            text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

comment on table public.income_sleeve_names is
  'One row per name in the income sleeve. Positions live in option_trades / '
  'share_lots / share_sells filtered by ticker; this table holds only what those '
  'cannot express: the intended block size and the protective floor.';

alter table public.income_sleeve_names enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies
                 where schemaname='public' and tablename='income_sleeve_names'
                   and policyname='income_sleeve_names_auth_read') then
    create policy income_sleeve_names_auth_read on public.income_sleeve_names
      for select to authenticated using (true);
  end if;
end $$;

-- The three chosen on 2026-08-15: near their 52-week lows, fairly priced, and
-- close to uncorrelated with NVDA, TLT and each other. AVGO was dropped at +0.51
-- correlation to NVDA; it duplicates the position rather than spreading it.
insert into public.income_sleeve_names (ticker, sort, target_shares, note) values
  ('INTU', 1, 0, '0.00 corr to NVDA, -0.07 to TLT. 20% up its 52w range. Earnings 25 Aug 2026.'),
  ('NKE',  2, 0, '1% up its 52w range, the lowest tested. 0.37 corr to LULU. Earnings 24 Sep 2026.'),
  ('LULU', 3, 0, '13% up its 52w range. 0.37 corr to NKE, so the two count as one and a half.')
on conflict (ticker) do nothing;

/* ── earnings, WITHOUT WHICH THE SKIP RULE CANNOT FIRE ──────────────────────
   The screen's only hard block is "a print lands inside this expiry". With
   earnings_events empty for these names it would cheerfully tell you to write
   straight through INTU on 25 Aug.

   Inferring the date from the volatility term structure was tested on 2026-08-14
   and scored 7 of 8, but called PYPL as imminent when the print was 74 days out.
   Fine as a cross-check, unusable as the source. These are Nik's own dates.
   ────────────────────────────────────────────────────────────────────────── */
insert into public.earnings_events (ticker, report_date, fiscal_period, scope_tag) values
  ('INTU', '2026-08-25', 'FY26 Q4', 'position'),
  ('NKE',  '2026-09-24', 'FY27 Q1', 'position'),
  -- NVDA's own print. nvda-accumulate's brake was querying a column that does not
  -- exist, so it had no dates at all and never fired. Writing to the third expiry
  -- out, the Friday 21 Aug write lands on 28 Aug and straddles this.
  ('NVDA', '2026-08-26', 'FY27 Q2', 'position')
on conflict (ticker, report_date) do nothing;

select ticker, active, target_shares, floor_strike, floor_expiry
from public.income_sleeve_names order by sort;

-- LULU's date is still missing and the sleeve is blind on it until it is added:
--   insert into public.earnings_events (ticker, report_date, scope_tag)
--   values ('LULU', 'YYYY-MM-DD', 'position') on conflict do nothing;
select ticker, report_date from public.earnings_events
where ticker in ('INTU','NKE','LULU','NVDA') and report_date >= current_date
order by report_date;
