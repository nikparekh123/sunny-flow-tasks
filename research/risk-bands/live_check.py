# -*- coding: utf-8 -*-
"""Live book sanity check for the two gauges (read-only SQL).

Rebuilds the app's daily Delta and Theta ratios from option_trades +
leg_marks_daily the way sunny-home does (legs open at the close of d, greeks
from that day or the latest before), then the 10-day average. Also splits the
Theta ratio into calls only (what the backtest models) and the app's version
(every bought leg vs every sold leg, puts included), and prints each LEAP's
delta so we can see why the Delta ratio reads high.

Usage: python3 live_check.py /path/to/q.sh
"""
import json, subprocess, sys, datetime, statistics as st

Q = sys.argv[1]
def q(sql):
    out = subprocess.run([Q, sql], capture_output=True, text=True, timeout=120).stdout.strip()
    return json.loads(out)

trades = q("select id, upper(ticker) ticker, trade_date, action, option_type, direction, contracts, strike, expiry "
           "from option_trades where voided_at is null and expiry >= '2026-08-25'")
marks = q("select option_trade_id id, day, delta, theta, iv, underlying, mark from leg_marks_daily where day >= '2026-08-20'")
M = {}
for m in marks: M.setdefault(m["day"], {})[m["id"]] = m
groups = {}
for t in trades:
    k = (t["ticker"], t["option_type"], t["direction"], float(t["strike"]), t["expiry"])
    groups.setdefault(k, []).append(t)

def D(s): return datetime.date.fromisoformat(s)
def legs_at(d):
    out = []
    for k, rows in groups.items():
        if k[4] < d: continue
        n = 0; ids = []
        for t in rows:
            if t["trade_date"] > d: continue
            if t["action"] == "open": n += float(t["contracts"]); ids.append(t["id"])
            else: n -= float(t["contracts"])
        if n > 1e-4: out.append((k, n, ids))
    return out
def greek(ids, d):
    for b in range(6):
        dd = str(D(d) - datetime.timedelta(days=b))
        for i in ids:
            r = M.get(dd, {}).get(i)
            if r: return r
    return None

days = sorted(d for d in M if d >= "2026-09-01")
rows = []
for d in days:
    thS = thL = thSc = thLc = dS = dL = 0.0
    for (tk, typ, dirn, K, exp), n, ids in legs_at(d):
        g = greek(ids, d)
        if not g: continue
        th = abs(float(g["theta"] or 0)) * n * 100
        short = dirn == "short"
        if short: thS += th
        else: thL += th
        if typ == "call":
            if short: thSc += th
            else: thLc += th
            if g["delta"] is not None:
                dl = abs(float(g["delta"])) * n * 100
                if short: dS += dl
                else: dL += dl
    rows.append((d, thS / thL if thL else None, thSc / thLc if thLc else None, dS / dL * 100 if dL else None))

def avg10(xs, i):
    w = [x for x in xs[max(0, i - 9):i + 1] if x is not None]
    return sum(w) / len(w) if w else None
th_app = [r[1] for r in rows]; th_c = [r[2] for r in rows]; de = [r[3] for r in rows]
print("%-11s %9s %9s %9s %9s %8s %8s" % ("day", "th app", "th 2w", "th calls", "calls 2w", "delta", "delta 2w"))
for i, r in enumerate(rows):
    f = lambda x, p="%9.2f": (p % x) if x is not None else "%9s" % "-"
    print("%-11s %s %s %s %s %s %s" % (r[0], f(r[1]), f(avg10(th_app, i)), f(r[2]), f(avg10(th_c, i)),
          f(r[3], "%7.0f%%"), f(avg10(de, i), "%7.0f%%")))
c2 = [avg10(th_c, i) for i in range(len(rows)) if avg10(th_c, i)]
a2 = [avg10(th_app, i) for i in range(len(rows)) if avg10(th_app, i)]
print("\ncalls-only theta 2w: min %.1f median %.1f max %.1f | app (puts in): min %.1f median %.1f max %.1f"
      % (min(c2), st.median(c2), max(c2), min(a2), st.median(a2), max(a2)))

last = days[-1]
print("\nLEAPs on %s (the Delta ratio's denominator):" % last)
for (tk, typ, dirn, K, exp), n, ids in sorted(legs_at(last)):
    if typ != "call" or dirn != "long": continue
    g = greek(ids, last)
    if g: print("  %-5s %6.1f %s x%3d  delta %.2f  iv %.2f  spot %.2f  (strike/spot %.2f)"
                % (tk, K, exp, n, float(g["delta"]), float(g["iv"]), float(g["underlying"]), K / float(g["underlying"])))
