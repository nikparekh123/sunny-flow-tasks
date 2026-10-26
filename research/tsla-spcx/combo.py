"""LEAP + calls, combined. Per 10 LEAP contracts.

total = LEAP P&L (bought at mid on the first day, rolled at mid, marked at mid
on the last) + every short call's P&L. Capital = what the LEAPs cost on day
one. Drawdown = deepest fall of (LEAP mark + calls banked so far) from its
running high, measured at each expiry close. Stock = 1,000 shares, for scale.
"""
import json, sys, os
from bt import load, run_calls, events, D
LEAPS = os.environ.get("LEAPS")

def leap_track(t, target):
    segs = json.load(open(LEAPS or f"{t.lower()}_leaps.json"))[target]
    marks = {}; value = {}; pl_done = 0.0; cost0 = None
    for i, sg in enumerate(segs):
        ser = sg["series"]; days = sorted(ser)
        buy = ser.get(sg["buy"]) or ser[days[0]]
        if cost0 is None: cost0 = buy * 1000
        for d in days: marks[d] = pl_done + (ser[d] - buy) * 1000; value[d] = ser[d] * 1000
        pl_done = marks[days[-1]]
    leap_track.value = value
    return marks, cost0, segs

def mark_on(marks, d):
    ks = [k for k in marks if k <= d]
    return marks[max(ks)] if ks else 0.0

def score(t, target, freq, rule, cov, fr, to):
    cl, ch = load(t)
    marks, cost, segs = leap_track(t, target)
    rows = run_calls(cl, ch, freq, rule, cov, fr, to) if cov > 0 else []
    end = max(d for d in marks if d <= to)
    start = min(d for d in marks if d >= fr)
    leap_pl = mark_on(marks, end) - mark_on(marks, start)
    calls = sum(r["pl"] for r in rows)
    # equity path at each expiry
    eq, banked, peak, dd = [], 0.0, None, 0.0
    for r in rows:
        banked += r["pl"]; v = mark_on(marks, r["e"]) - mark_on(marks, start) + banked
        peak = v if peak is None else max(peak, v); dd = min(dd, v - peak)
    stock = (cl[max(d for d in cl if d <= to)] - cl[min(d for d in cl if d >= fr)]) * 1000
    # Capital: what the LEAPs were worth when the window opened (day one: their cost).
    cap = leap_track.value.get(start) or cost
    return {"leap": leap_pl, "calls": calls, "total": leap_pl + calls, "cost": cap,
            "ret": (leap_pl + calls) / cap * 100, "dd": dd, "worst": min([r["pl"] for r in rows] or [0]),
            "n": len(rows), "stock": stock}

if __name__ == "__main__":
    t, fr, to = sys.argv[1], sys.argv[2], sys.argv[3]
    freq = sys.argv[4] if len(sys.argv) > 4 else "weekly"
    rules = ["atm", "otm2", "otm3", "otm5", "d30", "sd1", "split_sd1", "split_otm3"]
    for target in ("atm", "d75", "d90"):
        base = score(t, target, freq, "atm", 0, fr, to)
        print(f"\n{t} LEAP {target}  cost ${base['cost']:,.0f}  LEAP alone {base['leap']:+,.0f} ({base['ret']:+.0f}%)  1,000 shares {base['stock']:+,.0f}")
        for cov in (0.3, 0.4, 0.5, 0.6, 0.7):
            line = []
            for rule in rules:
                if rule.startswith("split_") and cov <= 0.3: line.append(f"{'':>15}"); continue
                s = score(t, target, freq, rule, cov, fr, to)
                line.append(f"{s['ret']:+6.0f}% {s['dd']/1000:+5.0f}K")
            print(f"  cov {int(cov*100)}%  " + " | ".join(line))
        print("           " + " | ".join(f"{r:>15}" for r in rules))
