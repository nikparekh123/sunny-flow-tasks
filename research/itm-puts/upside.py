"""Extra upside calls (Nik, 16 Oct 2026): which expiry to buy, 3, 6, 9 or 12 months.
Each name buys out-of-the-money calls on 1/3 of its LEAPs; 3- and 6-month calls are rolled
at expiry, 9- and 12-month ones replaced every 6 months (his cadence), plus 12 months held a
year. Same forward-test paths as block.py (12 months, 300 paths, fading richness). First buy
at today's quote (mid + 1/4 spread), later ones at that IV moved with the path's vol, 3%
spread, $0.65 a contract. What the calls ADD over 12 months (they don't touch the other legs)."""
import json, sys, math, numpy as np
from block import *
U = json.load(open('data/upside_chains.json'))
HELD = {'NKE': 60, 'LULU': 7, 'BABA': 15, 'NFLX': 17, 'UBER': 11}
SC = ['flat', 'up 15%', 'rip 25% in 3m', 'jump 30% in 1m', 'bull +40%', 'down 15%', 'crash 30% in 2m', 'V: -20% then back', 'no view']

def spot_now(t):
    ch = U[t]['chains']; e = min(x for x in ch if x >= '2026-10-23')
    C = {float(k): v for k, v in ch[e]['C'].items()}; P_ = {float(k): v for k, v in ch[e]['P'].items()}
    pairs = sorted((abs(sum(C[k]) / 2 - sum(P_[k]) / 2), sum(C[k]) / 2 - sum(P_[k]) / 2 + k) for k in C if k in P_)
    near = sorted(s for _, s in pairs[:3]); return near[len(near) // 2]

def leg(t, scen, months, otm, every, n_c, n=300):
    P, rv20, rv60 = paths(t, scen, n)
    S0 = SPOT[t]; q = Q[t]; step = LONG_STEP[t]
    e0 = U[t]['pick'][str(months)]; ch = {float(k): v for k, v in U[t]['chains'][e0]['C'].items()}
    K0 = min(ch, key=lambda k: abs(k - S0 * (1 + otm))); b, a = ch[K0]
    days0 = (D(e0) - TODAY).days
    iq = iv((b + a) / 2, S0, K0, days0 / 365, q, 'C') or 0.4
    out = np.zeros(n); spend = np.zeros(n)
    buy, K, T_days, px, v = 0, np.full(n, K0), days0, np.full(n, (b + a) / 2 + (a - b) / 4), np.full(n, iq)
    while True:
        exp_i = min(NDAYS, buy + int(round(T_days / 365 * 252)))
        end = exp_i if every is None else min(exp_i, buy + int(round(every * 21)), NDAYS)
        left = max(0.0, T_days / 365 - (end - buy) / 252)
        val = np.maximum(0, P[:, end] - K) if left <= 1e-6 else bsv(P[:, end], K, left, v, q, 'C') * 0.99
        out += n_c * (100 * (val - px) - 1.30); spend += n_c * 100 * px
        if end >= NDAYS: break
        buy = end; S = P[:, buy]; T_days = round(months * 30.44)
        K = np.round(S * (1 + otm) / step) * step
        v = iq * np.clip((rv60[:, buy] / rv60[:, 0]) ** 0.5, 0.7, 1.6)
        px = bsv(S, K, T_days / 365, v, q, 'C') * 1.03
    return out, spend, K0, (b, a), iq

PLANS = [('3 months, 15% out, roll at expiry', 3, 0.15, None),
         ('6 months, 21% out, roll at expiry', 6, 0.21, None),
         ('9 months, 26% out, replace every 6 months', 9, 0.26, 6),
         ('12 months, 30% out, replace every 6 months', 12, 0.30, 6),
         ('12 months, 30% out, hold the year', 12, 0.30, None),
         ('6 months, 15% out, roll at expiry', 6, 0.15, None),
         ('12 months, 15% out, replace every 6 months', 12, 0.15, 6)]
if __name__ == '__main__':
    for t in HELD: SPOT[t] = spot_now(t)
    res = {}
    for name, m, o, ev in PLANS:
        tot = {s: 0.0 for s in SC}; sp = 0.0; first = {}
        for t, nl in HELD.items():
            for s in SC:
                o_, spend, K0, ba, iq = leg(t, s, m, o, ev, nl / 3)
                tot[s] += float(np.mean(o_) if s == 'no view' else np.median(o_))
                if s == 'flat': sp += float(np.median(spend))
            first[t] = (U[t]['pick'][str(m)], K0, ba, round(iq, 3))
        res[name] = {'tot': tot, 'spend': sp, 'first': first}
        print(f"{name:44}" + ''.join(f"{tot[s]/1000:7.1f}" for s in SC) + f" | spend {sp/1000:5.1f}K", flush=True)
    json.dump(res, open('data/upside_results.json', 'w'))
    print({t: round(SPOT[t], 2) for t in HELD})
