"""Every time a stock made a new 52-week low after falling 40%+ from its
2-year high: the entry Nik buys. One per stock per year; the next 26 weeks must
be in the data."""
import json, glob, datetime
ETF = {"spy", "smh", "gdx", "jets", "slv", "ura", "xle", "tlt", "spcx"}
eps = []
for f in sorted(glob.glob("*_long.json")):
    t = f.split("_")[0]
    if t in ETF: continue
    b = json.load(open(f))["bars"]; d = [x["d"] for x in b]; c = [x["c"] for x in b]
    last = -10**9
    for i in range(504, len(c)):
        if c[i] > min(c[i-252:i]): continue          # not a new 52-week low
        if c[i] > 0.6 * max(c[i-504:i]): continue    # not 40% off the 2-year high
        if i - last < 252: continue                  # one entry a year
        if datetime.date.fromisoformat(d[i]).weekday() != 4: continue   # a Friday close, like the weekly sale
        if i + 130 >= len(c): continue               # the next 26 weeks must exist
        last = i
        eps.append({"t": t.upper(), "d": d[i], "S": c[i], "S26": c[i+130],
                    "move": c[i+130]/c[i]-1, "off_high": c[i]/max(c[i-504:i])-1})
for e in eps:
    tag = "fell" if e["move"] < -0.10 else ("recovered" if e["move"] > 0.15 else "sideways")
    e["tag"] = tag
    print("%-5s %s  %8.2f  off 2y high %4.0f%%  next 6m %+5.0f%%  %s" % (e["t"], e["d"], e["S"], e["off_high"]*100, e["move"]*100, tag))
print("\n%d episodes: %s" % (len(eps), {k: sum(e["tag"] == k for e in eps) for k in ("fell", "sideways", "recovered")}))
json.dump(eps, open("episodes.json", "w"))
