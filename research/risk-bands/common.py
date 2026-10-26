# -*- coding: utf-8 -*-
"""Shared loaders and Black-Scholes for the risk-band tests.

Data is the call-split framework's: research/call-split/episodes.json (60 new
52-week lows after a 40%+ fall, one a name a year) and the daily closes in
research/nvda-tenor/<t>_long.json (stock-history, 2018 to 12 Aug 2026).
Theta is worked out exactly the way mp-refresh does it for the app (carry
term in, per calendar day), at the app's 4% rate.
"""
import json, math, os, datetime, statistics as st
from statistics import NormalDist

HERE = os.path.dirname(os.path.abspath(__file__))
# RB_DATA: optional local mirror of research/ (call-split/episodes.json and
# nvda-tenor/*_long.json). The repo sits in iCloud Drive, which evicts these
# files and stalls reads; a copy outside iCloud avoids that.
RES = os.environ.get("RB_DATA") or os.path.dirname(HERE)
R = 0.04                                    # the app's RATE (mp-refresh)
_N = NormalDist()
NC, ND = _N.cdf, _N.pdf

SPLITS = {"NFLX": [("2025-11-17", 10)], "NVDA": [("2021-07-20", 4), ("2024-06-10", 10)],
          "TSLA": [("2020-08-31", 5), ("2022-08-25", 3)], "SHOP": [("2022-06-29", 10)],
          "NOW": [("2025-12-18", 5)]}          # from lows_bt.py: older contracts carry unadjusted strikes


def D(s): return datetime.date.fromisoformat(s)


def episodes():
    return json.load(open(os.path.join(RES, "call-split", "episodes.json")))


def bars(t):
    b = json.load(open(os.path.join(RES, "nvda-tenor", t.lower() + "_long.json")))["bars"]
    close = {x["d"]: x["c"] for x in b}
    return close, sorted(close)


def week_ends(days):
    wk = {}
    for d in days:
        y, w, _ = D(d).isocalendar(); wk[(y, w)] = d
    return sorted(wk.values())


def rv(close, days, i, n):
    """Annualised close-to-close vol over the n sessions ending at index i."""
    if i < n: return None
    lr = [math.log(close[days[k + 1]] / close[days[k]]) for k in range(i - n, i)]
    return st.stdev(lr) * math.sqrt(252)


def factor(t, d):
    f = 1
    for sd, r in SPLITS.get(t, []):
        if d < sd: f *= r
    return f


def occ(t, exp, K, f=1):
    return "O:%s%sC%08d" % (t, D(exp).strftime("%y%m%d"), int(round(K * f * 1000)))


def bs(S, K, T, v):
    """Call value, delta, theta per calendar day (app convention, carry in)."""
    if T <= 0:
        return max(0.0, S - K), (1.0 if S > K else 0.0), 0.0
    sq = v * math.sqrt(T)
    d1 = (math.log(S / K) + (R + v * v / 2) * T) / sq; d2 = d1 - sq
    er = math.exp(-R * T)
    val = S * NC(d1) - K * er * NC(d2)
    theta = (-S * ND(d1) * v / (2 * math.sqrt(T)) - R * K * er * NC(d2)) / 365
    return val, NC(d1), theta


def implied(price, S, K, T):
    floor = max(0.0, S - K * math.exp(-R * T))
    if not (price > floor + 0.005) or T <= 0: return None
    lo, hi = 0.01, 4.0
    for _ in range(60):
        m = (lo + hi) / 2
        if bs(S, K, T, m)[0] < price: lo = m
        else: hi = m
    v = (lo + hi) / 2
    return v if 0.03 < v < 3.9 else None


def strike_for_delta(S, T, v, dl):
    """The strike whose call delta is dl (minus sign: see nvda-tenor README bug note)."""
    return S * math.exp((R + v * v / 2) * T - _N.inv_cdf(dl) * v * math.sqrt(T))


def step_of(S):
    """Strike step: book-split/build.py's listed steps (0.5 under 100, 1 under
    300, else 5), but never coarser than ~1.5% of spot, so a $1 stock (MARA in
    2020) does not get an 'at the money' strike 60% out of the money."""
    for s in (5.0, 2.5, 1.0, 0.5, 0.25, 0.1, 0.05):
        if s <= 0.015 * S and s <= (0.5 if S < 100 else 1.0 if S < 300 else 5.0): return s
    return 0.05
