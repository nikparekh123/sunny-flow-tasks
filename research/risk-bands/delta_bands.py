# -*- coding: utf-8 -*-
"""Question 1: what Delta ratio (sold call delta / LEAP delta) suits a LEAP
book bought at 52-week lows?

Fixed coverage arms: every Friday the calls are sized so sold delta = c x LEAP
delta at the write, roll-sheet mix held. Plus the roll sheet itself (one call
per LEAP) and one-call-per-LEAP mixes (what can be done without writing more
calls than LEAPs). Each episode runs H weeks (default 26) from the low.

Returns are on capital = what the LEAP cost. Regime is the stock's move over
the H weeks: fell < -10%, recovered > +15%, sideways between.

Usage: python3 delta_bands.py            (H=26, weekly IV 1.07 x realised)
       H=52 python3 delta_bands.py       (episodes with 52 weeks of data)
       IV_K=1.0 python3 delta_bands.py   (weekly IV multiple; 1.07 is calibrated)
"""
import os, math, statistics as st
from common import episodes
from sim import prep, run, summary, regime, avg10, K_W

H = int(os.environ.get("H", 26))
COV = [0, .2, .3, .4, .5, .6, .8, 1.0]
ARMS = [("cov", c) for c in COV] + [("rule",), ("cap", 0.5), ("cap", 0.4)]
ONE = [("mix", 0.0, 1.0), ("mix", 0.0, 0.6), ("rule",), ("mix", 2 / 3, 0.6), ("mix", 1.0, 0)]
NAME = {("rule",): "roll sheet (1/LEAP)", ("mix", 0.0, 1.0): "all 1 SD", ("mix", 0.0, 0.6): "all 0.6 SD",
        ("mix", 2 / 3, 0.6): "2/3 ATM + 1/3 0.6SD", ("mix", 1.0, 0): "all ATM"}
for c in COV: NAME[("cov", c)] = "%d%% coverage" % round(c * 100)
NAME[("cap", 0.5)] = "roll sheet, cap 50%"; NAME[("cap", 0.4)] = "roll sheet, cap 40%"

P_all = [p for p in (prep(e, H) for e in episodes()) if p]
print("H=%d weeks | episodes %d | weekly IV = %.2f x 21-day realised vol" % (H, len(P_all), K_W))
print("regimes:", {g: sum(regime(p["close"][p["end"]] / p["close"][p["days"][0]] - 1) == g for p in P_all)
                   for g in ("fell", "sideways", "recovered")})

R = {}; WR = {}
for arm in ARMS + ONE:
    if arm in R: continue
    R[arm] = []; WR[arm] = []
    for P in P_all:
        o = run(P, arm); R[arm].append(summary(P, o))
        WR[arm] += [o["dr"][o["d"].index(w)] for w in o["writes"]]
base = R[("cov", 0)]

def line(arm):
    s = R[arm]; ret = [x["ret"] for x in s]; dd = [x["dd"] for x in s]
    by = lambda g, f: [f(x) for x in s if regime(x["move"]) == g]
    rec0 = [b["ret"] for b, x in zip(base, s) if regime(x["move"]) == "recovered"]
    recc = by("recovered", lambda x: x["ret"])
    strong0 = [b["ret"] for b, x in zip(base, s) if x["move"] > 0.30]
    strongc = [x["ret"] for x in s if x["move"] > 0.30]
    give = 1 - sum(recc) / sum(rec0); gives = 1 - sum(strongc) / sum(strong0) if strong0 else float("nan")
    m, sd = st.mean(ret), st.stdev(ret)
    return {"write": st.mean(WR[arm]), "gauge": st.mean(x["gauge_delta"] for x in s), "ret": m, "med": st.median(ret),
            "sharpe": m / sd, "dd": st.mean(dd), "ddw": max(dd), "calmar": m / st.mean(dd),
            "fell": st.mean(by("fell", lambda x: x["ret"])), "side": st.mean(by("sideways", lambda x: x["ret"])),
            "rec": st.mean(recc), "give": give, "gives": gives,
            "inc_fell": st.mean(by("fell", lambda x: x["call"])), "inc_side": st.mean(by("sideways", lambda x: x["call"])),
            "inc_rec": st.mean(by("recovered", lambda x: x["call"])), "worst": min(ret),
            "neg": sum(r < 0 for r in ret) / len(ret)}

def table(arms, title):
    print("\n" + title)
    print("  %-22s %6s %6s | %7s %7s %6s | %6s %6s %6s | %7s %7s %7s | %6s %6s | %6s %6s %6s"
          % ("arm", "write", "gauge", "mean", "median", "m/sd", "avgDD", "maxDD", "m/DD",
             "fell", "flat", "rebnd", "gaveUp", ">30%", "inc.fl", "inc.sw", "inc.rb"))
    for a in arms:
        L = line(a)
        print("  %-22s %5.0f%% %5.0f%% | %+6.0f%% %+6.0f%% %6.2f | %5.0f%% %5.0f%% %6.2f | %+6.0f%% %+6.0f%% %+6.0f%% | %5.0f%% %5.0f%% | %+5.0f%% %+5.0f%% %+5.0f%%"
              % (NAME[a], L["write"], L["gauge"], L["ret"] * 100, L["med"] * 100, L["sharpe"], L["dd"] * 100, L["ddw"] * 100,
                 L["calmar"], L["fell"] * 100, L["side"] * 100, L["rec"] * 100, L["give"] * 100, L["gives"] * 100,
                 L["inc_fell"] * 100, L["inc_side"] * 100, L["inc_rec"] * 100))

table(ARMS, "FIXED COVERAGE (calls sized to c x LEAP delta at each write; %% of LEAP cost over %d weeks)" % H)
table(ONE, "ONE CALL PER LEAP, different strike mixes")
print("""
  write = sold/long delta at the Friday write; gauge = the app's 2-week average over the hold.
  mean/median = return on the LEAP's cost; m/sd = mean / st.dev across episodes; avgDD/maxDD =
  peak-to-trough on the position; m/DD = mean return / average drawdown.
  fell/flat/rebnd = mean return by what the stock did; gaveUp = share of the uncovered LEAP's
  gain given up in rebounds (>+15%); >30% = same in strong rebounds; inc.* = call P&L alone.""")

# paired: each coverage vs the roll sheet, episode by episode
print("\npaired vs roll sheet, mean difference in return (t):")
rs = [x["ret"] for x in R[("rule",)]]
for a in ARMS:
    if a == ("rule",): continue
    df = [x["ret"] - y for x, y in zip(R[a], rs)]
    t = st.mean(df) / (st.stdev(df) / math.sqrt(len(df))) if st.stdev(df) > 0 else 0
    print("  %-14s %+6.1f pts  t=%+5.1f" % (NAME[a], st.mean(df) * 100, t))

# where the roll sheet sits, by LEAP delta at the write
print("\nroll sheet: sold/long delta at the write, by how far the LEAP delta has drifted")
bins = [(0, .6), (.6, .7), (.7, .8), (.8, .9), (.9, 1.01)]
acc = {b: [] for b in bins}
for P in P_all:
    o = run(P, ("rule",))
    for w in o["writes"]:
        i = o["d"].index(w); dl = o["dL"][i]
        for b in bins:
            if b[0] <= dl < b[1]: acc[b].append(o["dr"][i])
for b in bins:
    if acc[b]: print("  LEAP delta %.1f-%.1f: %4d writes, ratio median %3.0f%%" % (b[0], min(b[1], 1), len(acc[b]), st.median(acc[b])))

# sanity check against call-split/lows_bt.py (REAL option closes, same episodes): all-ATM
# calls lost 9.8% of stock value over 26 weeks (n=39), all at 1 SD lost 4.75%.
if H == 26:
    for arm, real in ((("mix", 1.0, 0), -9.80), (("mix", 0.0, 1.0), -4.75)):
        v = [x["call"] / x["lev"] for x in R[arm]]
        print("sanity, %-9s calls' 26-week P&L as %% of stock value: model %+.1f%% (all 60) | lows_bt real marks %+.1f%% (39)"
              % (NAME[arm], 100 * st.mean(v), real))
