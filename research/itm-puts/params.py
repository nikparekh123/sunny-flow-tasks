"""Per-name inputs for block.py, all from today's live quotes + 3y closes. Writes data/params.json."""
import json, math, datetime, numpy as np
from common import bs, iv, D, TODAY
L1 = json.load(open('data/live_chains.json')); L2 = json.load(open('data/live_chains2.json'))
LIVE = {**L1, **L2}
def chain(t, e, cp): return {float(k): v for k, v in LIVE[t][e].get(cp, {}).items()}
def T(e): return (D(e) - TODAY).days / 365
HELD = {'NKE': (60, 30.0), 'LULU': (7, 100.0), 'BABA': (15, 100.0), 'NFLX': (17, 70.0)}
OLD_SPOT = {'NKE': 37.225, 'LULU': 98.90, 'BABA': 110.53, 'NFLX': 72.625}
EARN = {'NKE': ['2026-12-17', '2027-03-30', '2027-06-29', '2027-09-28'], 'LULU': ['2026-12-10', '2027-03-16', '2027-06-03', '2027-09-02'],
        'BABA': ['2026-11-24', '2027-03-18', '2027-05-12', '2027-08-19'], 'NFLX': ['2026-10-20', '2027-01-19', '2027-04-15', '2027-07-15'],
        'ADBE': ['2026-12-09', '2027-03-11', '2027-06-10', '2027-09-09'], 'INTU': ['2026-11-19', '2027-02-25', '2027-05-19', '2027-08-24'],
        'SPCX': ['2026-11-17', '2027-02-17', '2027-05-17', '2027-08-03'], 'TSLA': ['2026-10-21', '2027-01-27', '2027-04-21', '2027-07-21'],
        'PYPL': ['2026-10-27', '2027-02-02', '2027-05-04', '2027-07-27'], 'APP': ['2026-11-04', '2027-02-10', '2027-05-05', '2027-08-04']}
LAST_EARN = {'ADBE': '2026-09-10', 'INTU': '2026-08-25', 'SPCX': '2026-08-04', 'TSLA': '2026-07-22', 'PYPL': '2026-07-28', 'APP': '2026-08-05',
             'NKE': '2026-09-29', 'LULU': '2026-09-03', 'BABA': '2026-08-20', 'NFLX': '2026-07-16'}
Q = {'NKE': 0.044, 'LULU': 0.0, 'BABA': 0.010, 'NFLX': 0.0, 'ADBE': 0.0, 'INTU': 0.015, 'SPCX': 0.0, 'TSLA': 0.0, 'PYPL': 0.010, 'APP': 0.0}
def closes(t):
    c = json.load(open(f'data/{t.lower()}_closes.json'))['bars']; ks = sorted(c); return ks, np.array([c[k] for k in ks])
def spot_parity(t):
    e = sorted(LIVE[t])[1]; C = chain(t, e, 'C'); P = chain(t, e, 'P'); tt = T(e)
    ks, px = closes(t); s0 = px[-1]
    best = min((k for k in C if k in P), key=lambda k: abs(k - s0))
    c = sum(C[best]) / 2; p = sum(P[best]) / 2
    return round(c - p + best * math.exp(-0.04 * tt), 3)
def step_near(ch, S):
    ks = sorted(k for k in ch if 0.85 * S < k < 1.15 * S); g = np.diff(ks)
    return float(np.median(g)) if len(g) else 1.0
def earn_move(t):
    """median absolute 1-day move around past report dates (the last known one, stepped back ~91 days)"""
    ks, px = closes(t); r = np.diff(np.log(px)); idx = {k: i for i, k in enumerate(ks[1:])}
    d0 = D(LAST_EARN[t]); out = []
    for q_ in range(12):
        d = d0 - datetime.timedelta(days=round(91.3 * q_))
        win = [idx[x] for x in ks[1:] if abs((D(x) - d).days) <= 4]
        if len(win) >= 3: out.append(max(abs(r[i]) for i in win))
    return float(np.median(out)) if out else 0.08, len(out)
def rv(t, w):
    ks, px = closes(t); r = np.diff(np.log(px)); return float(r[-w:].std() * math.sqrt(252))
P = {}
for t in ['NKE', 'LULU', 'BABA', 'NFLX', 'ADBE', 'INTU', 'SPCX', 'TSLA', 'PYPL', 'APP']:
    S = OLD_SPOT.get(t) or spot_parity(t); q = Q[t]
    ex = sorted(LIVE[t]); fri = [e for e in ex if D(e).weekday() == 4]
    wk = next(e for e in fri if e >= '2026-10-23')
    em, nem = earn_move(t)
    # weekly ATM IV (avg of call+put at the strike nearest spot), earnings stripped if inside
    C = chain(t, wk, 'C'); Pp = chain(t, wk, 'P'); k = min((k for k in C if k in Pp), key=lambda k: abs(k - S))
    v = np.mean([iv(sum(C[k]) / 2, S, k, T(wk), q, 'C') or 0, iv(sum(Pp[k]) / 2, S, k, T(wk), q, 'P') or 0])
    has = any(TODAY < D(e) <= D(wk) for e in EARN[t])
    vx = math.sqrt(max(0.01, v * v - (em ** 2 / T(wk) if has else 0)))
    rv20 = rv(t, 20) if t != 'SPCX' else rv(t, 20)
    term = {}
    for ten, e in ((3, '2027-01-15'), (5, '2027-03-19'), (8, '2027-06-17')):
        ch = chain(t, e, 'P'); kk = min(ch, key=lambda x: abs(x - S * 1.08)); m = sum(ch[kk]) / 2
        term[ten] = round(iv(m, S, kk, T(e), q, 'P') or v, 3)
    longstep = step_near(chain(t, '2027-03-19', 'P'), S)
    if t in HELD: nL, KL = HELD[t]
    else:
        ch = chain(t, '2028-01-21', 'C'); target = 0.85 if t == 'SPCX' else 0.80
        from common import delta
        cand = [(k, iv(sum(vv) / 2, S, k, T('2028-01-21'), q, 'C')) for k, vv in ch.items() if 0.4 * S < k < S]
        cand = [(k, x) for k, x in cand if x]
        KL = min(cand, key=lambda kx: abs(delta(S, kx[0], T('2028-01-21'), kx[1], q, 'C') - target))[0]
        nL = round(150000 / (100 * S)) or 1
    chL = chain(t, '2028-01-21', 'C'); mL = sum(chL[KL]) / 2; ivL = iv(mL, S, KL, T('2028-01-21'), q, 'C') or term[8]
    P[t] = dict(spot=S, q=q, step=step_near(C, S), long_step=longstep, leap=[nL, KL], leap_mid=mL, iv_leap=round(ivL, 3),
                earn=EARN[t], earn_move=round(em, 3), earn_n=nem, wk=wk, iv_wk=round(v, 3), iv_wk_ex=round(vx, 3), rv20=round(rv20, 3), rv60=round(rv(t, 60), 3),
                rho0=round(min(1.4, max(0.9, vx / rv20)), 3), iv_term=term, held=t in HELD)
    print(t, P[t], flush=True)
json.dump(P, open('data/params.json', 'w'), indent=1)
