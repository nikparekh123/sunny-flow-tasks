# -*- coding: utf-8 -*-
"""Question 2: where should the Theta ratio's warning line sit?

Runs the roll sheet (one call per LEAP, 1/3 ATM + 2/3 at 0.6 SD, 1 SD after a
15%+ month; no earnings tilt, no calendar) on every episode for up to 52 weeks
(at least 26). Builds the app's gauge: daily short theta / long theta (calls
only here; the app also counts puts), then the mean of the last ten days.

Each Friday the gauge is read, and the next 4 weeks are scored, as % of the
stock's value that Friday (one LEAP = 100 shares' worth, so this is % of
notional; % of the position's own value explodes when a LEAP is nearly worthless):
  total   P&L of LEAP + calls
  carry   everything except the LEAP's intrinsic move = call P&L + change in
          the LEAP's time value. Negative = the LEAP lost time value faster
          than the calls brought premium in (net of buybacks).
Medians and % negative are reported; means are winsorised at the 1st/99th
percentile. Readings overlap (4-week windows, weekly) and cluster by episode,
so treat the t figures as optimistic.
Then: does a low reading predict a bad next month, and which line (2x, 3x,
4x, 5x) separates bad from normal?

Usage: python3 theta_bands.py             (LEAP bought at 0.90 delta, as STRATEGIES.md)
       ENTRY=0.75 python3 theta_bands.py  (closer to the live LEAPs, 0.61-0.73 today)
       IV_K=1.0 python3 theta_bands.py
"""
import os, math, statistics as st
from common import episodes
from sim import prep, run, avg10, K_W

ENTRY = float(os.environ.get("ENTRY", "0.90"))
FWD = 4
P_all = [p for p in (prep(e, 52, min_weeks=26) for e in episodes()) if p]
print("episodes %d (26-52 weeks each) | LEAP entry delta %.2f | weekly IV %.2f x realised" % (len(P_all), ENTRY, K_W))

obs = []; gauges = []; daily = []
for P in P_all:
    o = run(P, ("rule",), entry_delta=ENTRY)
    g = [avg10(o["tr"], i) for i in range(len(o["tr"]))]
    daily += [x for x in o["tr"] if x is not None]
    idx = [o["d"].index(w) for w in o["writes"]] + [len(o["d"]) - 1]
    for n, i in enumerate(idx[:-1]):
        if g[i] is None: continue
        gauges.append(g[i])
        if n < 2 or n + FWD >= len(idx): continue        # need two weeks of history and four ahead
        j = idx[n + FWD]
        E = o["S"][i]
        call = o["call"][j] - o["call"][i]
        dtv = o["TV"][j] - o["TV"][i]
        wk = P["wk"][o["d"][i]]
        obs.append({"g": g[i], "tot": (o["pnl"][j] - o["pnl"][i]) / E, "carry": (call + dtv) / E,
                    "call": call / E, "tvlost": -dtv / E, "dL": o["dL"][i], "ivw": wk["iv"], "ivL": wk["ivL"],
                    "mv": o["S"][j] / o["S"][i] - 1, "dr": avg10(o["dr"], i)})

def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(p / 100 * len(xs)))]
print("\nTHE GAUGE UNDER THE ROLL SHEET (calls only), %d Friday readings" % len(gauges))
print("  " + "  ".join("p%d %.1fx" % (p, pct(gauges, p)) for p in (1, 5, 10, 25, 50, 75, 90, 99)))
print("  daily (before the 2-week average): " + "  ".join("p%d %.1fx" % (p, pct(daily, p)) for p in (1, 5, 10, 50, 90)))
for L in (2, 3, 4, 5, 6):
    print("  share of Fridays below %dx: %4.1f%%" % (L, 100 * sum(x < L for x in gauges) / len(gauges)))

BINS = [(0, 3), (3, 4), (4, 5), (5, 6), (6, 8), (8, 10), (10, 14), (14, 999)]
def wins(xs):
    lo, hi = pct([x for x in xs], 1), pct([x for x in xs], 99)
    return [min(hi, max(lo, x)) for x in xs]
for key in ("tot", "carry"):
    w = wins([x[key] for x in obs])
    for x, v in zip(obs, w): x[key + "_w"] = v
print("\nNEXT 4 WEEKS BY GAUGE READING (n=%d Friday readings with 4 weeks ahead), %% of stock value" % len(obs))
print("  %-9s %5s %6s | %7s %7s %5s | %7s %7s %5s | %6s %6s %5s" % ("gauge", "n", "share", "total", "median", "neg",
                                                                 "carry", "median", "neg", "move", "LEAPd", "wkIV"))
for a, b in BINS:
    s_ = [x for x in obs if a <= x["g"] < b]
    if not s_: continue
    print("  %4.0f-%-4.0f %5d %5.1f%% | %+6.2f%% %+6.2f%% %4.0f%% | %+6.2f%% %+6.2f%% %4.0f%% | %+5.1f%% %6.2f %6.2f"
          % (a, b if b < 999 else 99, len(s_), 100 * len(s_) / len(obs),
             100 * st.mean(x["tot_w"] for x in s_), 100 * st.median(x["tot"] for x in s_), 100 * sum(x["tot"] < 0 for x in s_) / len(s_),
             100 * st.mean(x["carry_w"] for x in s_), 100 * st.median(x["carry"] for x in s_), 100 * sum(x["carry"] < 0 for x in s_) / len(s_),
             100 * st.median(x["mv"] for x in s_), st.median(x["dL"] for x in s_), st.median(x["ivw"] for x in s_)))

print("\nCANDIDATE LINES: readings below vs at-or-above, next 4 weeks' carry (%% of stock value)")
print("  %-5s %6s | %9s %9s | %8s %8s | %6s" % ("line", "below", "med below", "med above", "neg b", "neg a", "z neg"))
for L in (2, 3, 4, 5, 6, 8, 10):
    b = [x for x in obs if x["g"] < L]; a = [x for x in obs if x["g"] >= L]
    if len(b) < 5:
        print("  %-5s %5.1f%% | too few readings below the line (%d)" % ("%dx" % L, 100 * len(b) / len(obs), len(b))); continue
    pb = sum(x["carry"] < 0 for x in b) / len(b); pa = sum(x["carry"] < 0 for x in a) / len(a)
    p = (pb * len(b) + pa * len(a)) / len(obs); z = (pb - pa) / math.sqrt(p * (1 - p) * (1 / len(b) + 1 / len(a)))
    print("  %-5s %5.1f%% | %+8.2f%% %+8.2f%% | %7.0f%% %7.0f%% | %+5.1f"
          % ("%dx" % L, 100 * len(b) / len(obs), 100 * st.median(x["carry"] for x in b), 100 * st.median(x["carry"] for x in a),
             100 * pb, 100 * pa, z))

# rank correlation of the gauge with next-month carry and total
def rank(v):
    o = sorted(range(len(v)), key=lambda i: v[i]); r = [0] * len(v)
    for n, i in enumerate(o): r[i] = n
    return r
def spear(x, y):
    rx, ry = rank(x), rank(y); mx, my = st.mean(rx), st.mean(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    return num / math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
G = [x["g"] for x in obs]
print("\nrank correlation, gauge vs next 4 weeks: carry %+.2f, total %+.2f, stock move %+.2f, call P&L %+.2f"
      % (spear(G, [x["carry"] for x in obs]), spear(G, [x["tot"] for x in obs]), spear(G, [x["mv"] for x in obs]),
         spear(G, [x["call"] for x in obs])))
print("rank correlation, gauge vs LEAP delta %+.2f, weekly IV / LEAP IV %+.2f, delta gauge %+.2f"
      % (spear(G, [x["dL"] for x in obs]), spear(G, [x["ivw"] / x["ivL"] for x in obs]), spear(G, [x["dr"] for x in obs])))
