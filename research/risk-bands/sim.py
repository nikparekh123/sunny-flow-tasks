# -*- coding: utf-8 -*-
"""The engine: one LEAP bought at a 52-week low, a call written every Friday.

Per episode (call-split/episodes.json):
  LEAP   bought at the low's Friday close, 16 months to expiry, struck for
         0.90 delta (STRATEGIES.md). Priced at 1.15 x 252-day realised vol,
         refreshed weekly (live book: LEAP IV / 252-day vol = 1.02-1.31,
         median ~1.15, research/risk-bands/live_check.log + calibration).
  Calls  every Friday close to next Friday. Roll sheet strikes: first
         strike at/above spot (ATM) and 0.6 SD out (1 SD after a 15%+ up
         month); 1/3 ATM, 2/3 out. No earnings tilt (no earnings calendar for
         2018-2026 here). Priced Black-Scholes at K_W x 21-day realised vol,
         flat (no skew). K_W = 1.07 is CALIBRATED to real marks: calibrate.py
         runs lows_bt.py's arms on the 31 episodes it priced with real Polygon
         closes for all 26 weeks; k=1.05 matches all-ATM (-10.6% of stock
         value), k=1.10 matches all-1-SD (-5.0%). 1 cent a share slippage on
         every call sold. Settled at expiry intrinsic (bought back, never
         assigned).

Arms (how many calls):
  ("cov", c)   calls sized so sold call delta = c x LEAP delta at the write,
               roll-sheet mix held (above ~40% this means more calls than LEAPs)
  ("rule",)    the roll sheet as written: one call per LEAP contract
  ("cap", c)   the roll sheet, but fewer calls whenever that would put sold
               delta above c x LEAP delta (never more than one per LEAP)
  ("mix", a, out) one call per LEAP, a share ATM, the rest at `out` SD

Greeks are worked out the app's way (theta per calendar day, carry in).
Gauges replicate sunny-home: daily ratio, then the mean of the last ten.
"""
import math, os, statistics as st
from common import (episodes, bars, week_ends, rv, bs, strike_for_delta, step_of, D)

LEAP_DAYS = 487
LEAP_VOL_X = 1.15
SLIP = 0.01

K_W = float(os.environ.get("IV_K", "1.07"))     # weekly IV = K_W x 21-day realised vol
_cache = {}


def _bars(t):
    if t not in _cache: _cache[t] = bars(t)
    return _cache[t]


def prep(e, H, min_weeks=None):
    """Market path for one episode: trading days, write days, weekly vols."""
    t = e["t"]; close, days = _bars(t); W = week_ends(days)
    if e["d"] not in W: return None
    j = W.index(e["d"]); Hh = min(H, len(W) - 1 - j)
    if Hh < (min_weeks or H): return None
    writes = W[j:j + Hh]; end = W[j + Hh]
    i0, i1 = days.index(e["d"]), days.index(end)
    wk = {}
    for d in writes:
        i = days.index(d); S = close[d]
        r21 = rv(close, days, i, 21); r252 = rv(close, days, i, 252)
        wk[d] = {"S": S, "iv": max(0.08, K_W * r21), "earn": False,
                 "m": S / close[days[i - 21]] - 1,
                 "ivL": min(1.5, max(0.15, LEAP_VOL_X * r252))}
    return {"t": t, "e": e, "days": days[i0:i1 + 1], "close": close, "writes": writes, "end": end,
            "W": W[j:j + Hh + 1], "wk": wk, "H": Hh}


def legs_for(arm, w, T, dL):
    S, iv = w["S"], w["iv"]
    step = step_of(S)
    katm = math.ceil(S / step - 1e-9) * step
    sd = S * iv * math.sqrt(T)
    k_out = lambda out: max(katm + step, round((S + out * sd) / step) * step)
    a = 0.2 if w["earn"] else 1 / 3
    out = 1.0 if w["m"] >= 0.15 else 0.6
    if arm[0] == "rule":
        return [(katm, a), (k_out(out), 1 - a)]
    if arm[0] in ("cov", "cap"):
        c = arm[1]
        if c <= 0: return []
        mix = [(katm, a), (k_out(out), 1 - a)]
        dmix = sum(n * bs(S, K, T, iv)[1] for K, n in mix)
        n = min(5.0 if arm[0] == "cov" else 1.0, c * dL / dmix)
        return [(K, x * n) for K, x in mix]
    if arm[0] == "mix":
        _, aa, o = arm
        return [(katm, aa), (k_out(o), 1 - aa)] if aa < 1 else [(katm, 1.0)]
    raise ValueError(arm)


def run(P, arm, entry_delta=0.90):
    days, close, wk = P["days"], P["close"], P["wk"]
    d0 = days[0]; S0 = close[d0]
    expL = D(d0).toordinal() + LEAP_DAYS
    TL = lambda d: (expL - D(d).toordinal()) / 365
    ivL = wk[d0]["ivL"]
    KL = strike_for_delta(S0, TL(d0), ivL, entry_delta)
    VL0 = bs(S0, KL, TL(d0), ivL)[0]
    cash = 0.0; open_legs = []; exp = None; iv_w = None
    out = {"d": [], "S": [], "pnl": [], "call": [], "VL": [], "TV": [], "dL": [], "dr": [], "tr": [],
           "thS": [], "thL": [], "writes": []}
    for d in days:
        S = close[d]
        if d in wk: ivL = wk[d]["ivL"]
        VL, dL, thL = bs(S, KL, TL(d), ivL)
        # settle expiring calls
        if exp == d:
            for K, n in open_legs: cash -= n * max(0.0, S - K)
            open_legs = []
        # write the week's calls (not on the horizon's last day)
        if d in wk and d != P["end"]:
            nxt = P["W"][P["W"].index(d) + 1]; T = max(1, (D(nxt) - D(d)).days) / 365
            iv_w = wk[d]["iv"]
            open_legs = legs_for(arm, wk[d], T, dL)
            for K, n in open_legs: cash += n * (bs(S, K, T, iv_w)[0] - SLIP)
            exp = nxt
            out["writes"].append(d)
        sv = sd_ = sth = 0.0
        if open_legs and exp:
            T = (D(exp) - D(d)).days / 365
            for K, n in open_legs:
                v, dl, th = bs(S, K, T, iv_w)
                sv += n * v; sd_ += n * dl; sth += n * abs(th)
        out["d"].append(d); out["S"].append(S)
        out["pnl"].append(VL - VL0 + cash - sv); out["call"].append(cash - sv)
        out["VL"].append(VL); out["TV"].append(VL - max(0.0, S - KL)); out["dL"].append(dL)
        out["thS"].append(sth); out["thL"].append(abs(thL))
        last = d == P["end"]
        out["dr"].append(None if last else sd_ / dL * 100)
        out["tr"].append(None if last or not abs(thL) else sth / abs(thL))
    out["C0"] = VL0; out["KL"] = KL
    return out


def avg10(xs, i):
    w = [x for x in xs[max(0, i - 9):i + 1] if x is not None]
    return sum(w) / len(w) if w else None


def summary(P, o):
    C0 = o["C0"]; eq = [C0 + p for p in o["pnl"]]
    pk, dd = eq[0], 0.0
    for x in eq:
        pk = max(pk, x); dd = max(dd, (pk - x) / pk)
    move = o["S"][-1] / o["S"][0] - 1
    g = [avg10(o["dr"], i) for i in range(len(o["dr"]))]
    g = [x for x in g if x is not None]
    th = [avg10(o["tr"], i) for i in range(len(o["tr"]))]
    th = [x for x in th if x is not None]
    return {"t": P["t"], "d": P["e"]["d"], "move": move, "ret": o["pnl"][-1] / C0, "call": o["call"][-1] / C0,
            "dd": dd, "gauge_delta": st.mean(g) if g else 0, "gauge_theta": st.median(th) if th else 0,
            "lev": o["S"][0] / C0}


def regime(move):
    return "fell" if move < -0.10 else ("recovered" if move > 0.15 else "sideways")
