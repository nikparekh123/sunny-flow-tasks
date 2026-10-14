-- LEAP model prices, logged beside the midpoint at every close (Nik, 14 Oct
-- 2026: "get closer to IBKR"). Shadow only: nothing reads these for the app.
-- Each night IBKR's own statement mark (account_positions_daily) arrives and
-- leap_model_vs_ibkr shows which price tracked it best.
create table if not exists public.leap_model_shadow (
  day date not null,
  ticker text not null,
  put_call text not null,              -- 'C' | 'P'
  strike numeric not null,
  expiry date not null,
  position numeric,
  spot numeric, bid numeric, ask numeric, mid numeric, iv_mid numeric,
  iv_smooth numeric, m_smooth numeric,       -- 5-session median IV of this contract
  iv_ibkr numeric, m_ibkr numeric, ibkr_from date,   -- IV implied by IBKR's last statement mark
  iv_smile numeric, m_smile numeric, smile_points int,  -- same-expiry smile at this strike
  captured_at timestamptz not null default now(),
  primary key (day, ticker, put_call, strike, expiry)
);
alter table public.leap_model_shadow enable row level security;

create or replace view public.leap_model_vs_ibkr with (security_invoker = true) as
select s.day, s.ticker, s.put_call, s.strike, s.expiry, p.position, p.mark_price as ibkr,
       s.bid, s.ask, s.mid, s.m_smooth, s.m_ibkr, s.m_smile,
       round((s.mid      - p.mark_price) * p.position * 100, 2) as err_mid,
       round((s.m_smooth - p.mark_price) * p.position * 100, 2) as err_smooth,
       round((s.m_ibkr   - p.mark_price) * p.position * 100, 2) as err_ibkr,
       round((s.m_smile  - p.mark_price) * p.position * 100, 2) as err_smile
from public.leap_model_shadow s
join public.account_positions_daily p
  on p.report_date = s.day and p.underlying = s.ticker and p.put_call = s.put_call
 and p.strike = s.strike and p.expiry = s.expiry and p.asset_category = 'OPT';
