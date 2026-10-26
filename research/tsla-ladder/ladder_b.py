"""Nik's three-expiry ladder, option B, as agreed on the sample week (18 Oct 2026).
Model research, not advice.
- 1,000 shares; 10 calls on each of the next three Mon/Wed/Fri expiries, three always open.
- Each expiry day at the close: the expiring 10 settle (assigned shares bought back at that
  close, $0.005 a share) and 10 are sold on the next expiry. Sales rotate: every third AT the
  money (nearest strike), the other two OTM% out (first strike at or above).
- Long calls ~3 months at the money (one contract at a time). On each expiry day, if 'could be'
  (the lower net delta after an instant 5% move either way) is outside 0..+300, the count is
  set so it lands near +150. Rolled into a new ~3-month at-the-money call with 30 days left.
- Real Theta end-of-day quotes; deltas from each option's own implied volatility that day.
  Fills at mid, or 'worse' (sell at the bid, buy at the ask). $0.65 a contract.
Long-call versions (Nik, 18 Oct 2026): 3 months, 6 months, 1 year; at the money, in the money
(about 80 delta) or out (about 35 delta); rolled with a third of their life left. TSLA sells on
Mon/Wed/Fri expiries; SPY, QQQ, IWM every trading day, three trading days out.
Usage: TICKERS=TSLA python3 ladder_b.py"""
import json, math, os
from concurrent.futures import ThreadPoolExecutor
from sim import theta, bs, iv_of, yrs, D, DATA
TICKERS = os.environ.get('TICKERS', 'TSLA').split(',')
START = {'TSLA': '2026-02-02', 'SPY': '2024-10-07', 'QQQ': '2024-10-07', 'IWM': '2024-10-07'}
END = '2026-10-16'
TENOR = {'3m': (91, 60, 30), '6m': (182, 120, 60), '1y': (365, 240, 120)}   # target days, at least, roll at days left
STRIKE = {'atm': None, 'itm80': 0.80, 'otm35': 0.35}

class Q:
    def __init__(s, t):
        s.t = t; s.p = os.path.join(DATA, f'marks_{t}.json')
        s.c = json.load(open(s.p)) if os.path.exists(s.p) else {}
    def save(s): json.dump(s.c, open(s.p, 'w'))
    def chain(s, e, day):
        k = f'c|{e}|{day}'
        if k not in s.c:
            q = {}
            for c in theta(f"/v3/option/history/eod?symbol={s.t}&expiration={e.replace('-', '')}&right=call&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
                for x in c.get('data', []):
                    if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[str(float(c['contract']['strike']))] = [x['bid'], x['ask']]
            s.c[k] = q
        return {float(a): b for a, b in s.c[k].items()}
    def hist(s, e, K, a):
        k = f'h|{e}|{K}|{a}'
        if k not in s.c:
            q = {}; lo = D(a); hi = D(min(e, END))
            while lo <= hi:                                  # Theta: 365 days a request at most
                b = min(hi, lo + __import__('datetime').timedelta(days=360))
                for c in theta(f"/v3/option/history/eod?symbol={s.t}&expiration={e.replace('-', '')}&right=call&strike={K}&start_date={lo.isoformat().replace('-', '')}&end_date={b.isoformat().replace('-', '')}"):
                    for x in c.get('data', []):
                        if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[x['created'][:10]] = [x['bid'], x['ask']]
                lo = b + __import__('datetime').timedelta(days=1)
            s.c[k] = q
        return s.c[k]

def data(t):
    f = os.path.join(DATA, f'{t}_daily.json')
    return json.load(open(f if t != 'TSLA' and os.path.exists(f) else os.path.join(DATA, f'{t}.json')))

def run(t, otm, fill, tenor='3m', strike='atm', M=None, d=None):
    d = d or data(t); C = d['closes']; exps = d['exps']; M = M or Q(t)
    tgt_days, min_days, roll_days = TENOR[tenor]; tgt_delta = STRIKE[strike]
    sl = [s for s, _ in d['slots'] if s >= START[t]]
    SELL = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    BUY = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    cash = 0.0; shorts = {}; L = None; n_sold = 0; eq = []; prem = settle = 0.0
    long_cash = 0.0; long_trades = 0; cb_neg = 0; checks = 0; last = None
    sh_cash = lg_cash = 0.0; track = []; ltrades = []          # per-part cash, for the month-by-month split
    def mid(e, K, a, day):
        q = M.hist(e, K, a).get(day); return (q[0] + q[1]) / 2 if q else None
    def iv_now(e, K, a, day, S, fb):
        m = mid(e, K, a, day); return (iv_of(m, S, K, yrs(day, e)) if m else None) or fb
    for i, day in enumerate(sl):
        if day > END: break
        S = C[day]; last = day
        if i == 0: cash -= 1000 * S; sells = sl[1:4]
        else:
            if day in shorts:
                s = shorts.pop(day); x = max(0, S - s['K']) * 1000; cash -= x; settle += x; sh_cash -= x
                if x > 0: cash -= 5; sh_cash -= 5
            sells = sl[i + 3:i + 4]
        for e in sells:
            q = {float(k): v for k, v in d['q'].get(f'{day}|{e}', {}).items() if v[0] > 0} or M.chain(e, day)
            if not q: n_sold += 1; continue
            ks = sorted(q); atm = n_sold % 3 == 0
            K = min(ks, key=lambda k: abs(k - S)) if atm else next((k for k in ks if k >= S * (1 + otm)), ks[-1])
            p = SELL(*q[K]); cash += p * 1000 - 6.5; sh_cash += p * 1000 - 6.5; prem += p * 1000; n_sold += 1
            shorts[e] = dict(K=K, d=day, iv=iv_of((q[K][0] + q[K][1]) / 2, S, K, yrs(day, e)) or 0.4)
        # long calls: roll with 30 days left, then keep 'could be' in 0..+300
        if L and (D(L['e']) - D(day)).days <= roll_days:
            q = M.hist(L['e'], L['K'], L['d']).get(day)
            px = SELL(*q) if q else bs(S, L['K'], yrs(day, L['e']), L['iv'])[0]
            cash += px * 100 * L['n'] - 0.65 * L['n']; lg_cash += px * 100 * L['n'] - 0.65 * L['n']; long_cash += px * 100 * L['n']; long_trades += 1
            ltrades.append((day, 'roll out', -L['n'], L['e'], L['K'], px, S)); L = None
        def base(x):
            v = 1000.0
            for e, s in shorts.items():
                if e > day: v -= 1000 * bs(x, s['K'], yrs(day, e), iv_now(e, s['K'], s['d'], day, S, s['iv']))[1]
            return v
        if L is None:
            # Monthly expiries first (third Friday, or Thursday in a holiday week): far weeklies
            # in today's listing did not exist yet on `day`.
            monthly = lambda x: 15 <= D(x).day <= 21 and D(x).weekday() == 4 or 14 <= D(x).day <= 20 and D(x).weekday() == 3
            cands = sorted([x for x in exps if (D(x) - D(day)).days >= min_days], key=lambda x: (not monthly(x), abs((D(x) - D(day)).days - tgt_days)))
            for e in cands[:12]:
                ch = M.chain(e, day)
                if ch:
                    if tgt_delta is None: K = min(ch, key=lambda k: abs(k - S))
                    else:
                        T_ = yrs(day, e); dl = {}
                        for k, (b, a) in ch.items():
                            v = iv_of((b + a) / 2, S, k, T_)
                            if v: dl[k] = bs(S, k, T_, v)[1]
                        K = min(dl, key=lambda k: abs(dl[k] - tgt_delta)) if dl else min(ch, key=lambda k: abs(k - S))
                    L = dict(e=e, K=K, d=day, n=0, iv=iv_of(sum(ch[K]) / 2, S, K, yrs(day, e)) or 0.45, q0=ch[K]); break
        if L is None: raise RuntimeError(f'no long-call chain on {day}')
        lv_iv = iv_now(L['e'], L['K'], L['d'], day, S, L['iv'])
        cl = lambda x: 100 * bs(x, L['K'], yrs(day, L['e']), lv_iv)[1]
        b_dn, b_up, c_dn, c_up = base(S * 0.95), base(S * 1.05), cl(S * 0.95), cl(S * 1.05)
        cb = lambda n: min(b_dn + n * c_dn, b_up + n * c_up)
        checks += 1; cb_neg += cb(L['n']) < 0
        q_today = M.hist(L['e'], L['K'], L['d']).get(day) or (L['q0'] if day == L['d'] else None)
        if q_today: L['iv'] = iv_of(sum(q_today) / 2, S, L['K'], yrs(day, L['e'])) or L['iv']
        if q_today and (L['n'] == 0 or not (0 <= cb(L['n']) <= 300)):
            n = min(range(0, 400), key=lambda n: abs(cb(n) - 150)); dn = n - L['n']
            if dn:
                q = q_today
                px = BUY(*q) if dn > 0 else SELL(*q)
                cash -= dn * px * 100 + 0.65 * abs(dn); lg_cash -= dn * px * 100 + 0.65 * abs(dn); long_cash -= dn * px * 100; long_trades += 1; L['n'] = n
                ltrades.append((day, 'buy' if dn > 0 else 'sell', dn, L['e'], L['K'], px, S))
        lv = L['n'] * 100 * (mid(L['e'], L['K'], L['d'], day) or bs(S, L['K'], yrs(day, L['e']), L['iv'])[0]) if L else 0
        sv = sum(1000 * (mid(e, s['K'], s['d'], day) or bs(S, s['K'], yrs(day, e), s['iv'])[0]) for e, s in shorts.items() if e > day)
        eq.append((day, cash + 1000 * S + lv - sv))
        track.append((day, S, 1000 * (S - C[sl[0]]), sh_cash - sv, lg_cash + lv, L['n'] if L else 0, (L['e'], L['K']) if L else None, lv, base(S) + (L['n'] * cl(S) if L else 0)))
    peak, mdd = -1e18, 0.0
    for _, v in eq: peak = max(peak, v); mdd = min(mdd, v - peak)
    S0 = C[sl[0]]; years = yrs(sl[0], last); tot = eq[-1][1]
    lv_end = eq[-1][1] - (cash + 1000 * C[last]) + sum(1000 * (mid(e, s['K'], s['d'], last) or 0) for e, s in shorts.items() if e > last)
    steps = [b[1] - a[1] for a, b in zip(eq, eq[1:])]
    return dict(t=t, otm=otm, fill=fill, tenor=tenor, strike=strike, start=sl[0], end=last, S0=S0, S1=C[last], years=years, total=tot,
                pct_yr=tot / years / (1000 * S0) * 100, shares=(C[last] - S0) * 1000, calls_net=prem - settle,
                longs=long_cash + lv_end, long_trades=long_trades, mdd=mdd, mdd_pct=mdd / (1000 * S0) * 100,
                cb_neg_pct=cb_neg / checks * 100, worst_step=min(steps), expiry_days=len(eq), track=track, ltrades=ltrades)

def prefetch(t, d, M):
    """Every sold call's daily quotes, fetched three at a time (they do not depend on the long calls)."""
    C = d['closes']; sl = [s for s, _ in d['slots'] if s >= START[t]]; need = set()
    for otm in (0.02, 0.03, 0.05):
        n = 0
        for i, day in enumerate(sl):
            if day > END: break
            S = C[day]
            for e in (sl[1:4] if i == 0 else sl[i + 3:i + 4]):
                q = {float(k): v for k, v in d['q'].get(f'{day}|{e}', {}).items() if v[0] > 0}
                if not q: n += 1; continue
                ks = sorted(q); atm = n % 3 == 0; n += 1
                K = min(ks, key=lambda k: abs(k - S)) if atm else next((k for k in ks if k >= S * (1 + otm)), ks[-1])
                need.add((e, K, day))
    todo = [x for x in need if f'h|{x[0]}|{x[1]}|{x[2]}' not in M.c]
    with ThreadPoolExecutor(3) as ex: list(ex.map(lambda x: M.hist(*x), todo))
    M.save(); return len(need), len(todo)

if __name__ == '__main__':
    out = []
    for t in TICKERS:
        d = data(t); M = Q(t); print(t, 'prefetched (sold calls, fetched now)', prefetch(t, d, M), flush=True)
        for tenor in ('3m', '6m', '1y'):
          for strike in ('atm', 'itm80', 'otm35'):
            for otm in (0.02, 0.03, 0.05):
              for fill in ('mid', 'worse'):
                r = run(t, otm, fill, tenor, strike, M, d); out.append(r)
                print(f"{t} {tenor} {strike:5s} {int(otm * 100)}% {fill:5s} {r['start']}..{r['end']} total ${r['total']:>10,.0f} ({r['pct_yr']:6.1f}%/yr) shares ${r['shares']:>10,.0f} "
                      f"calls sold net ${r['calls_net']:>10,.0f} long calls ${r['longs']:>10,.0f} ({r['long_trades']} trades) maxDD {r['mdd_pct']:6.1f}% "
                      f"could-be<0 {r['cb_neg_pct']:4.1f}% worst step ${r['worst_step']:>9,.0f}", flush=True)
          M.save()
        json.dump([{k: v for k, v in r.items() if k not in ('track', 'ltrades')} for r in out], open(os.path.join(DATA, f"ladder_b2_{'_'.join(TICKERS)}.json"), 'w'), indent=1)
