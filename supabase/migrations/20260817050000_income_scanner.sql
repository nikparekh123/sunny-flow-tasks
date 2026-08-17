/* ============================================================
   The income scanner: which names are ELIGIBLE for the sleeve.

   Spec: docs/INCOME_SCANNER_SPEC.md

   A report, not a recommender. It applies gates, records facts, and sorts. Nik
   picks. Only then does a name become a row in income_sleeve_names.

   Two tables because the work and the reading happen at different times: a scan
   is ~270 Polygon calls across 134 names and cannot run inside a screen load.
   income-scanner writes results on a cron; the Income screen reads the last run.
   ============================================================ */

-- ── the universe ───────────────────────────────────────────────────────────
create table if not exists public.income_scanner_universe (
  ticker      text primary key,
  active      boolean not null default true,
  added_on    date    not null default current_date,
  note        text
);

comment on table public.income_scanner_universe is
  'The names the scanner checks each night. Nik''s list of the most liquid US '
  'options names; add or retire rows rather than editing the function.';

-- ── one row per name per run ───────────────────────────────────────────────
create table if not exists public.income_scanner_results (
  ticker           text not null,
  asof             date not null,

  spot             numeric,
  ret_12mo         numeric,          -- the fall, if there was one
  ret_3mo          numeric,          -- has it stopped falling
  vol_60d          numeric,          -- realised, annualised
  vol_20d          numeric,
  pos_52w          numeric,          -- 0 at the low, 100 at the high

  /* The worst single day that is NOT an earnings print and NOT a market-wide
     day. Isolating those two is the whole difficulty: the first version of this
     gate excluded NKE and LULU because both had their "worst day" during the
     April 2025 macro week, along with 79% of the universe. */
  own_gap          numeric,
  own_gap_on       date,

  atm_straddle_pct numeric,          -- what a week pays, as a % of spot
  implied_vol      numeric,
  edge             numeric,          -- implied minus 20-day realised
  option_oi        int,              -- at-the-money open interest
  option_volume    int,

  max_correlation  numeric,          -- to any name currently held
  bucket           text,             -- 'quiet' | 'broken' | null
  passes           boolean not null default false,
  fails            text[],           -- every gate it missed, for the audit trail

  created_at       timestamptz not null default now(),
  primary key (ticker, asof)
);

create index if not exists idx_income_scanner_results_asof
  on public.income_scanner_results (asof desc, passes desc);

alter table public.income_scanner_universe enable row level security;
alter table public.income_scanner_results  enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='income_scanner_universe' and policyname='isu_auth_read') then
    create policy isu_auth_read on public.income_scanner_universe
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='income_scanner_results' and policyname='isr_auth_read') then
    create policy isr_auth_read on public.income_scanner_results
      for select to authenticated using (true);
  end if;
end $$;

/* Nik's list of 2026-08-17, minus the ones with unusable history. SPCX, FIG and
   DJT are ticker-reuse or too-short cases; the scanner's own sanity gate would
   drop them anyway, but keeping them out of the universe saves 3 calls a night
   and stops them reappearing as "excluded" noise in every run. */
insert into public.income_scanner_universe (ticker) values
  ('NVDA'),('AAPL'),('TSLA'),('AMZN'),('MSFT'),('META'),('GOOGL'),('GOOG'),
  ('F'),('NFLX'),('AMD'),('PLTR'),('DIS'),('MU'),('AVGO'),('HOOD'),('KO'),
  ('COST'),('RIVN'),('TSM'),('WMT'),('INTC'),('SOFI'),('PFE'),('SNAP'),('CVX'),
  ('LLY'),('CRWD'),('BABA'),('BAC'),('JNJ'),('MRVL'),('AAL'),('NOW'),('V'),
  ('UBER'),('SBUX'),('CCL'),('XOM'),('RKLB'),('DAL'),('COIN'),('NKE'),('ORCL'),
  ('SHOP'),('T'),('VST'),('GE'),('NEE'),('QCOM'),('ABBV'),('JPM'),('BA'),
  ('PYPL'),('MRK'),('O'),('SNOW'),('SPOT'),('BIDU'),('INTU'),('CAT'),('WFC'),
  ('MA'),('DE'),('C'),('ACN'),('ADBE'),('WDAY'),('LULU'),('GS'),('CRM'),('UNH'),
  ('ARM'),('SMCI'),('MSTR'),('MS'),('AXP'),('IBM'),('CSCO'),('TXN'),('AMAT'),
  ('LRCX'),('ASML'),('DELL'),('VRT'),('MARA'),('RIOT'),('CVNA'),('ABNB'),
  ('DASH'),('RBLX'),('DKNG'),('AFRM'),('SE'),('MELI'),('NU'),('PDD'),('JD'),
  ('XPEV'),('LI'),('COP'),('OXY'),('SLB'),('FCX'),('NEM'),('LMT'),('RTX'),
  ('ABT'),('BMY'),('AMGN'),('GILD'),('MRNA'),('ACHR'),('JOBY'),('ASTS'),
  ('OKLO'),('SMR'),('IONQ'),('RGTI'),('QBTS'),('SOUN'),('PEP'),('VZ'),('MO'),
  ('KMB'),('GIS'),('CL'),('MCD'),('PG'),('CAG'),('HSY'),('SJM'),('CPB'),('ZTS'),
  ('EL'),('ULTA'),('CHWY'),('EBAY'),('MDT'),('FDX'),('TGT'),('LOW'),('HD')
on conflict (ticker) do nothing;

notify pgrst, 'reload schema';

select count(*) as universe from public.income_scanner_universe where active;
