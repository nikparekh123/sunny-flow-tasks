/* ============================================================
   Benzinga intel: guidance, analyst actions, consensus, news

   Guidance is the only one that changes a decision. It becomes a GATE, because
   a company guiding down while Nik grinds his average lower is the value trap,
   and it is the only signal in the whole system that speaks to the BUSINESS
   rather than to the stock or its options.

   The rest is background for the live card on names he holds.

   ⚠ CONSENSUS TARGETS ARE ALL-TIME AND UNUSABLE AS A PRICE SIGNAL. The feed
   aggregates every analyst who has ever covered the name. On 22 Aug it gave
   NKE a target of 91.56 against a spot of 40.91 (+124%) with a low of 12.12,
   and NFLX 324.05 against 79.69 (+307%) with a low of 1.22 and a high of 1514.
   Only the RATING MIX is used from it. The usable target is the rolling
   120-day median of analyst_actions, which gave NKE 47.00 and NFLX 87.50.

   ⚠ GUIDANCE DIRECTION NEEDS CARE. NKE reaffirmed on 23 Jun without restating
   EPS, so the payload reads 0.00-0.00 against a prior of 0.00-0.00. Compared
   naively that is a cut. Direction is derived from whichever of EPS or revenue
   actually carries numbers, and reaffirmations are labelled as such.
   ============================================================ */

create table if not exists public.guidance_events (
  benzinga_id text primary key,
  ticker text not null, date date not null,
  fiscal_period text, fiscal_year int, release_type text, importance int,
  min_eps numeric, max_eps numeric, prev_min_eps numeric, prev_max_eps numeric,
  min_rev numeric, max_rev numeric, prev_min_rev numeric, prev_max_rev numeric,
  direction text,            -- raised | cut | reaffirmed | initiated | unknown
  notes text, updated_at timestamptz default now()
);
create index if not exists guidance_ticker_date_idx on public.guidance_events (ticker, date desc);

create table if not exists public.analyst_actions (
  benzinga_id text primary key,
  ticker text not null, date date not null,
  firm text, analyst text,
  rating text, previous_rating text, rating_action text,
  price_target numeric, previous_price_target numeric, price_target_action text,
  importance int, updated_at timestamptz default now()
);
create index if not exists analyst_actions_ticker_date_idx on public.analyst_actions (ticker, date desc);

create table if not exists public.analyst_consensus (
  ticker text primary key,
  rating text, rating_value numeric,
  target numeric, high numeric, low numeric, contributors int,
  strong_buy int, buy int, hold int, sell int, strong_sell int,
  as_of timestamptz default now()
);

create table if not exists public.name_news (
  id text primary key,
  ticker text not null, published timestamptz,
  title text, publisher text, url text,
  updated_at timestamptz default now()
);
create index if not exists name_news_ticker_pub_idx on public.name_news (ticker, published desc);

comment on table public.guidance_events is
  'Company guidance. direction is derived on ingest from whichever of EPS or '
  'revenue carries numbers; a reaffirmation restates nothing and must not read '
  'as a cut.';
comment on column public.analyst_consensus.target is
  'ALL-TIME aggregate and NOT usable against spot. Use the 120-day median of '
  'analyst_actions instead. Only the rating mix here is sound.';

do $$ declare t text; begin
  foreach t in array array['guidance_events','analyst_actions','analyst_consensus','name_news'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t) then
      execute format($p$create policy %I on public.%I for select to authenticated using (true)$p$, t||'_read', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
