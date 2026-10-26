-- 26 Oct 2026 (Nik: option B): a LEAPS under 0.70 delta rolls down, same expiry, to the strike nearest 0.75 delta.
-- sunny-home prices each roll from Theta's quotes at most once an hour and keeps it here.
create table if not exists public.leaps_roll (
  ticker text not null, expiry date not null, strike numeric not null,
  priced_at timestamptz not null default now(),
  data jsonb not null,
  primary key (ticker, expiry, strike)
);
alter table public.leaps_roll enable row level security;
