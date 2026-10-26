import json, math, datetime, statistics as st
from statistics import NormalDist
ND = NormalDist().cdf; R = 0.04
D = datetime.date.fromisoformat
TODAY = D('2026-10-15')
SPOT = {'NKE': 37.225, 'LULU': 98.90, 'BABA': 110.53, 'NFLX': 72.625}
Q = {'NKE': 0.044, 'LULU': 0.0, 'BABA': 0.010, 'NFLX': 0.0}
STEP = {'NKE': 0.5, 'LULU': 1.0, 'BABA': 1.0, 'NFLX': 1.0}           # listed strike spacing near the money
LEAP = {'NKE': (60, 30.0), 'LULU': (7, 100.0), 'BABA': (15, 100.0), 'NFLX': (17, 70.0)}   # (contracts, strike), Jan 2028
EARN = {'NKE': ['2026-12-17', '2027-03-30', '2027-06-29', '2027-09-28'],
        'LULU': ['2026-12-10', '2027-03-16', '2027-06-03', '2027-09-02'],
        'BABA': ['2026-11-24', '2027-03-18', '2027-05-12', '2027-08-19'],
        'NFLX': ['2026-10-20', '2027-01-19', '2027-04-15', '2027-07-15']}
def bs(S, K, T, v, q, cp):
    if T <= 1e-6: return max(0.0, (S - K) if cp == 'C' else (K - S))
    sq = v * math.sqrt(T); d1 = (math.log(S / K) + (R - q + v * v / 2) * T) / sq; d2 = d1 - sq
    if cp == 'C': return S * math.exp(-q * T) * ND(d1) - K * math.exp(-R * T) * ND(d2)
    return K * math.exp(-R * T) * ND(-d2) - S * math.exp(-q * T) * ND(-d1)
def delta(S, K, T, v, q, cp):
    if T <= 1e-6: return (1.0 if S > K else 0.0) if cp == 'C' else (-1.0 if S < K else 0.0)
    d1 = (math.log(S / K) + (R - q + v * v / 2) * T) / (v * math.sqrt(T))
    return math.exp(-q * T) * (ND(d1) if cp == 'C' else ND(d1) - 1)
def iv(p, S, K, T, q, cp):
    intr = max(0.0, (S * math.exp(-q * T) - K * math.exp(-R * T)) if cp == 'C' else (K * math.exp(-R * T) - S * math.exp(-q * T)))
    if p <= intr + 1e-4 or T <= 0: return None
    lo, hi = 0.01, 4.0
    for _ in range(80):
        m = (lo + hi) / 2
        if bs(S, K, T, m, q, cp) < p: lo = m
        else: hi = m
    return (lo + hi) / 2
def years(a, b): return max(1 / 365, (D(b) - D(a)).days / 365) if isinstance(a, str) else max(1 / 365, (D(b) - a).days / 365)
def closes(t):
    c = json.load(open(f'data/{t.lower()}_closes.json'))['bars']
    return c
def live_chains():
    raw = json.load(open('data/live_chains.json'))
    return {t: {e: {cp: {float(k): v for k, v in side.items()} for cp, side in q.items()} for e, q in ex.items()} for t, ex in raw.items()}
