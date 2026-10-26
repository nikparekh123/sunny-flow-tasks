"""ITM + OTM ladder test (Nik, 18 Oct 2026). Model research, not advice.
Position per name: 1,000 shares + 10 deep ITM LEAPs. Rolled every Friday, real Theta
end-of-day quotes, Oct 2024 to Oct 2026 (107 Fridays):
  SHARES leg: each Friday sell 10 calls on the coming Friday's expiry, in the money
    (1/2/3 strikes below the price, or the strike nearest 2/3/5% below), let them be
    assigned and buy the 1,000 shares back at that close ($0.005 a share).
    Compared with: shares alone, at the money, and 0.6 SD out (our usual).
  LEAP leg: calls on the expiry AFTER next (two weeks) at 0.8 SD, half the LEAPs each
    Friday so all ten stay covered; the LEAP itself is the same in every row and left out.
Fills at mid (and at the bid as a check), $0.65 a contract. Settled at the expiry close."""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TICKERS = ['TSLA', 'COIN', 'HOOD', 'URA']
FILL = os.environ.get('FILL', 'mid')

def ncdf(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))
def bs(S, K, T, v, r=0.04):
    sq = v * math.sqrt(T); d1 = (math.log(S / K) + (r + v * v / 2) * T) / sq
    return S * ncdf(d1) - K * math.exp(-r * T) * ncdf(d1 - sq)
def iv_of(px, S, K, T):
    if not px > max(0, S - K * math.exp(-0.04 * T)) + 0.001: return None
    lo, hi = 0.01, 5.0
    for _ in range(60):
        m = (lo + hi) / 2
        if bs(S, K, T, m) < px: lo = m
        else: hi = m
    return (lo + hi) / 2

def settle(closes, days, e):
    ks = [d for d in days if d <= e]; return closes[ks[-1]]

ARMS = ['shares alone', 'at the money', '1 strike in', '2 strikes in', '3 strikes in', '2% in', '3% in', '5% in', '0.6 SD out']
res = {}
for t in TICKERS:
    d = json.load(open(os.path.join(DATA, f'{t}.json')))
    closes = d['closes']; days = sorted(closes)
    sales = sorted(s for s, v in d['sales'].items() if v['c1'] and v['e1'] and v['e1'] <= days[-1])
    R = {a: [] for a in ARMS}; leap = []; detail = {a: dict(prem=0.0, back=0.0, assigned=0) for a in ARMS}
    S_first = closes[sales[0]]
    for sale in sales:
        v = d['sales'][sale]; S = closes[sale]; e = v['e1']; Se = settle(closes, days, e)
        T = max(1, (int(e.replace('-', '')) and (__import__('datetime').date.fromisoformat(e) - __import__('datetime').date.fromisoformat(sale)).days)) / 365
        Q = {float(k): ((b + a) / 2 if FILL == 'mid' else b) for k, (b, a) in v['c1'].items() if b > 0 and a > 0}
        if not Q: continue
        ks = sorted(Q); katm = min(ks, key=lambda k: abs(k - S))
        iv = iv_of((v['c1'][str(katm)][0] + v['c1'][str(katm)][1]) / 2, S, katm, T) or 0.5
        sig = S * iv * math.sqrt(T)
        below = sorted((k for k in ks if k < S), reverse=True)
        pick = {'at the money': katm,
                '1 strike in': below[0] if len(below) > 0 else None,
                '2 strikes in': below[1] if len(below) > 1 else None,
                '3 strikes in': below[2] if len(below) > 2 else None,
                '2% in': min(ks, key=lambda k: abs(k - S * 0.98)),
                '3% in': min(ks, key=lambda k: abs(k - S * 0.97)),
                '5% in': min(ks, key=lambda k: abs(k - S * 0.95)),
                '0.6 SD out': next((k for k in ks if k >= S + 0.6 * sig), ks[-1])}
        shares = (Se - S) * 1000
        R['shares alone'].append(shares)
        for a, K in pick.items():
            if K is None: R[a].append(shares); continue
            prem = Q[K] * 1000; back = max(0, Se - K) * 1000
            rebuy = 5.0 if Se > K else 0.0
            R[a].append(shares + prem - back - 6.5 - rebuy)
            detail[a]['prem'] += prem; detail[a]['back'] += back; detail[a]['assigned'] += Se > K
        # LEAP leg: 5 two-week calls at 0.8 SD each Friday (ladder: 10 always on)
        if v['c2'] and v['e2'] and v['e2'] <= days[-1]:
            e2 = v['e2']; T2 = (__import__('datetime').date.fromisoformat(e2) - __import__('datetime').date.fromisoformat(sale)).days / 365
            Q2 = {float(k): ((b + a) / 2 if FILL == 'mid' else b) for k, (b, a) in v['c2'].items() if b > 0 and a > 0}
            if Q2:
                k2s = sorted(Q2); k2 = next((k for k in k2s if k >= S + 0.8 * S * iv * math.sqrt(T2)), k2s[-1])
                leap.append(500 * (Q2[k2] - max(0, settle(closes, days, e2) - k2)) - 3.25)
    years = len(R['shares alone']) / 52
    res[t] = dict(S0=S_first, S1=closes[sales[-1]], weeks=len(R['shares alone']), years=years,
                  arms={a: dict(total=sum(x), per_yr_pct=sum(x) / years / (S_first * 1000) * 100, lose=sum(1 for y in x if y < 0),
                                worst=min(x), calls=sum(x) - sum(R['shares alone']), **{k: v for k, v in detail[a].items()}) for a, x in R.items()},
                  leap=dict(total=sum(leap), per_yr_pct=sum(leap) / years / (S_first * 1000) * 100, lose=sum(1 for y in leap if y < 0), worst=min(leap), weeks=len(leap)))
json.dump(res, open(os.path.join(DATA, f'result_{FILL}.json'), 'w'), indent=1)
for t, r in res.items():
    print(f"\n{t}: {r['S0']:.2f} -> {r['S1']:.2f} over {r['weeks']} weeks")
    for a, x in r['arms'].items():
        print(f"  {a:14s} total ${x['total']:>10,.0f}  {x['per_yr_pct']:6.1f}%/yr  calls add ${x['calls']:>10,.0f}  losing wks {x['lose']:3d}  worst ${x['worst']:>9,.0f}  assigned {x.get('assigned', 0)}")
    L = r['leap']; print(f"  LEAP calls 0.8 SD 2-wk ladder: ${L['total']:,.0f} ({L['per_yr_pct']:.1f}%/yr of share value)  losing {L['lose']}/{L['weeks']}  worst ${L['worst']:,.0f}")
