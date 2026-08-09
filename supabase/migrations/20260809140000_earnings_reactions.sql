/* ============================================================
   earnings_reactions — what the tape actually did after each print
   ============================================================
   One row per ticker per report. The reaction-day move decides the
   band; the 5/10/30-session paths afterwards are what the planner
   reads to answer "how long does it stay down".

   Pooled peers (AVGO, AMD, TSM, MU) live here too, tagged by ticker,
   so NVDA's own record and the wider semis sample stay separable —
   a keep-percentage driven by six observations should never read
   with the confidence of one driven by sixty.

   Percentages are stored as plain numbers: -9.59 means -9.59%.
   ============================================================ */

create table if not exists public.earnings_reactions (
  id            uuid primary key default gen_random_uuid(),
  ticker        text not null,
  report_date   date not null,          -- the print
  reaction_date date,                   -- the session that repriced it
  close_before  numeric,
  close_after   numeric,
  move_pct      numeric,                -- reaction day, close-to-close
  d5_pct        numeric,                -- from close_after, 5 sessions on
  d10_pct       numeric,
  d30_pct       numeric,
  band          text check (band in ('bad','flat','good')),
  source        text not null default 'polygon',
  created_at    timestamptz not null default now(),
  unique (ticker, report_date)
);

create index if not exists earnings_reactions_band_idx
  on public.earnings_reactions (ticker, band, report_date desc);

alter table public.earnings_reactions enable row level security;

drop policy if exists earnings_reactions_read on public.earnings_reactions;
create policy earnings_reactions_read on public.earnings_reactions
  for select to authenticated using (true);

drop policy if exists earnings_reactions_write on public.earnings_reactions;
create policy earnings_reactions_write on public.earnings_reactions
  for all to service_role using (true) with check (true);
