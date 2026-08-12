# -*- coding: utf-8 -*-
"""NVDA accumulation: does expiry TENOR change the basis, at a constant delta budget?

Sized by DELTA, not by contract, so every arm accumulates at the same expected
rate and the only thing that varies is how long each option lives.
"""
import json, math, datetime, statistics, urllib.request, time, os
from statistics import NormalDist
H = json.load(open("nvda_hist.json")); bars = H["bars"]
close = {b["d"]: b["c"] for b in bars}; days = sorted(close)
R, N = 0.045, NormalDist()

rv = {}
for i in range(21, len(days)):
    w = days[i-21:i+1]
    lr = [math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]] = statistics.stdev(lr)*math.sqrt(252)

def strike_for(S, T, v, delta):
    d1 = -N.inv_cdf(delta)
    K = S*math.exp((R + v*v/2)*T - d1*v*math.sqrt(T))
    return round(K/2.5)*2.5                      # NVDA lists 2.5s in this range

def fridays():
    out = []
    for d in days:
        if datetime.date.fromisoformat(d).weekday() == 4: out.append(d)
    return out

FRI = fridays()
DELTA_TGT = 0.45
# 190 delta a week is the rate; each arm deploys the same rate per unit time.
WEEKLY_DELTA = 190
TENORS = {"weekly": 7, "biweekly": 14, "monthly": 28}

plan, need = {}, set()
for name, dte in TENORS.items():
    step = max(1, round(dte/7))
    rolls = [d for i, d in enumerate(FRI) if i % step == 0 and d in rv]
    plan[name] = []
    for d in rolls:
        exp = (datetime.date.fromisoformat(d) + datetime.timedelta(days=dte)).isoformat()
        # settle on the last close on or before expiry
        if exp > days[-1]: continue
        S, v, T = close[d], rv[d], dte/365
        K = strike_for(S, T, v, DELTA_TGT)
        plan[name].append({"d": d, "exp": exp, "S": S, "v": v, "K": K, "dte": dte})
        need.add("O:NVDA%sP%08d" % (datetime.date.fromisoformat(exp).strftime("%y%m%d"), int(round(K*1000))))

json.dump({"plan": plan, "need": sorted(need)}, open("nvda_plan.json", "w"))
for n in TENORS: print(f"  {n:9} {len(plan[n]):3} rolls")
print("contracts needed", len(need))
