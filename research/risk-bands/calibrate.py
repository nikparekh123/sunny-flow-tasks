# -*- coding: utf-8 -*-
"""Calibrate the weekly option price to REAL marks.

call-split/lows_bt.py priced the same 52-week-low episodes with real Polygon
closes and logged, per episode, the 26 weeks of call P&L as % of stock value
(run_lows.log). Here the model writes the same calls (all ATM; all at 1 SD)
priced at k x 21-day realised vol, for several k, and we pick the k whose
results match the real ones. Only episodes lows_bt priced for all 26 weeks.

Usage: python3 calibrate.py
"""
import os, re, statistics as st
import sim
from common import episodes, RES

log = open(os.path.join(RES, "call-split", "run_lows.log")).read().split("per entry")[1]
real = {}
for ln in log.splitlines():
    m = re.match(r"\s+([A-Z]+)\s+(\d{4}-\d\d-\d\d)\s+[+-]\d+%\s+\w+\s+(\d+)\s+(.*)", ln)
    if not m: continue
    v = [float(x.rstrip("%")) for x in m.group(4).split()]
    if int(m.group(3)) == 26: real[(m.group(1), m.group(2))] = (v[0], v[6])   # All ATM, All @ 1 SD
EP = [e for e in episodes() if (e["t"], e["d"]) in real]
print("episodes lows_bt priced for all 26 weeks: %d" % len(EP))
ra = st.mean(real[(e["t"], e["d"])][0] for e in EP); r1 = st.mean(real[(e["t"], e["d"])][1] for e in EP)
print("real marks:   all ATM %+.2f%%   all 1 SD %+.2f%%  (calls' 26-week P&L, %% of stock value)" % (ra, r1))
for k in (0.9, 1.0, 1.05, 1.07, 1.1, 1.15, 1.2, 1.3):
    sim.K_W = k
    out = {}
    for arm in (("mix", 1.0, 0), ("mix", 0.0, 1.0)):
        xs = []; err = []
        for e in EP:
            P = sim.prep(e, 26); s = sim.summary(P, sim.run(P, arm))
            v = 100 * s["call"] / s["lev"]; xs.append(v)
            err.append(v - real[(e["t"], e["d"])][0 if arm[1] == 1.0 else 1])
        out[arm] = (st.mean(xs), st.mean(abs(x) for x in err))
    print("k=%.2f  model: all ATM %+.2f%% (mean abs err %.1f)   all 1 SD %+.2f%% (mean abs err %.1f)"
          % (k, out[("mix", 1.0, 0)][0], out[("mix", 1.0, 0)][1], out[("mix", 0.0, 1.0)][0], out[("mix", 0.0, 1.0)][1]))
