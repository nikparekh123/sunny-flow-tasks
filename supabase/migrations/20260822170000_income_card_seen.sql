-- What the Income card has already shown you.
--
-- The situational block used to lead with a 120-day aggregate, which never
-- changes, so the first line Nik read every morning was the stalest thing on
-- the card. Worse, it counted one event many times: NKE's "27 analyst actions"
-- were 14 firms reacting to a single earnings report on 1 July.
--
-- The fix is to show what changed SINCE HIS LAST VISIT. That needs a marker.
--
-- Two dates, not one. `visit_on` is the last day the card was opened;
-- `since_on` is the cutoff the card reads against. The cutoff only moves
-- forward on the FIRST open of a new day, and it moves to the PREVIOUS visit
-- day, never to today. Without that split, opening the app twice in one
-- morning would empty the card the second time.
create table if not exists income_card_seen (
  ticker      text primary key,
  since_on    date,                      -- null on a first-ever visit: bootstrap to 14 days
  visit_on    date not null,
  updated_at  timestamptz not null default now()
);

comment on column income_card_seen.since_on is
  'Cutoff the card reads against. Advances only on the first open of a new day, to the previous visit day.';
comment on column income_card_seen.visit_on is
  'Last calendar day (New York) the card was opened for this ticker.';

alter table income_card_seen enable row level security;

drop policy if exists income_card_seen_service on income_card_seen;
create policy income_card_seen_service on income_card_seen
  for all to service_role using (true) with check (true);
