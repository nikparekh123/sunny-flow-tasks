# -*- coding: utf-8 -*-
"""The split test, started where Nik actually buys: a new 52-week low after a
40%+ fall from the 2-year high. 60 real entries 2020-2026, the next 26 weeks of
weekly calls on each, 10 contracts, real Polygon closes. Every arm holds the same
LEAPs, so the comparison is the short calls' P&L, as a % of the stock's value."""
import json, math, datetime, statistics, urllib.request, time
from statistics import NormalDist
N = NormalDist(); R = 0.045
EPS = json.load(open("episodes.json"))
SPLITS = {"NFLX": [("2025-11-17", 10)], "NVDA": [("2021-07-20", 4), ("2024-06-10", 10)],
          "TSLA": [("2020-08-31", 5), ("2022-08-25", 3)], "SHOP": [("2022-06-29", 10)],
          "NOW": [("2025-12-18", 5)]}
def factor(t, d):
    f = 1
    for sd, r in SPLITS.get(t, []):
        if d < sd: f *= r
    return f

close, days = {}, {}
for t in {e["t"] for e in EPS}:
    b = json.load(open(t.lower() + "_long.json"))["bars"]
    close[t] = {x["d"]: x["c"] for x in b}; days[t] = sorted(close[t])

def rv(t, d):
    ds = days[t]; i = ds.index(d)
    w = ds[i-21:i+1]
    lr = [math.log(close[t][w[j+1]]/close[t][w[j]]) for j in range(21)]
    return statistics.stdev(lr) * math.sqrt(252)
def wends(t):
    wk = {}
    for d in days[t]:
        y, w, _ = datetime.date.fromisoformat(d).isocalendar(); wk[(y, w)] = d
    return sorted(wk.values())
def occ(t, exp, K, f):
    return "O:%s%sC%08d" % (t, datetime.date.fromisoformat(exp).strftime("%y%m%d"), int(round(K*f*1000)))
def grid(x):
    out = set()
    for inc in (0.5, 1, 2.5, 5):
        for k in (math.floor(x/inc)*inc, math.ceil(x/inc)*inc):
            if k > 0: out.add(round(k, 2))
    return sorted(out)
def kdelta(S, v, T, dl):
    return S * math.exp((R + v*v/2)*T - N.inv_cdf(dl)*v*math.sqrt(T))

plan, need = [], {}
for ei, e in enumerate(EPS):
    t = e["t"]; W = wends(t)
    j = W.index(e["d"]) if e["d"] in W else None
    if j is None: continue
    for d, exp in zip(W[j:j+26], W[j+1:j+27]):
        T = max(1, (datetime.date.fromisoformat(exp) - datetime.date.fromisoformat(d)).days) / 365
        S = close[t][d]; v = rv(t, d); f = factor(t, d)
        tg = {"atm": S, "sd": S + S*v*math.sqrt(T), "d30": kdelta(S, v, T, 0.30)}
        cands = {k: grid(x) for k, x in tg.items()}
        i = days[t].index(d)
        plan.append({"ep": ei, "t": t, "d": d, "exp": exp, "S": S, "f": f, "tg": tg, "c": cands,
                     "m": S / close[t][days[t][i-21]] - 1})
        for ks in cands.values():
            for K in ks: need.setdefault(d, set()).add(occ(t, exp, K, f))

try: OB = json.load(open("optc.json"))
except Exception: OB = {}
todo = {}
for d, cs in need.items():
    for c in cs:
        if c not in OB: todo.setdefault(d, []).append(c)
print("sales", len(plan), "| to fetch", sum(len(v) for v in todo.values()), flush=True)
K_ = "sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U = "https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
n = 0
for d, cs in sorted(todo.items()):
    for i in range(0, len(cs), 60):
        rq = urllib.request.Request(U, data=json.dumps({"contracts": cs[i:i+60], "from": d, "to": d}).encode(),
            headers={"Authorization": "Bearer " + K_, "apikey": K_, "Content-Type": "application/json"})
        for a in range(3):
            try:
                got = json.load(urllib.request.urlopen(rq, timeout=120)).get("bars") or {}
                for c in cs[i:i+60]: OB[c] = got.get(c) or []
                break
            except Exception as ex:
                print("  retry", d, a, ex, flush=True); time.sleep(2)
        n += 1; time.sleep(0.12)
    if n % 25 == 0: json.dump(OB, open("optc.json", "w")); print("  through", d, flush=True)
json.dump(OB, open("optc.json", "w"))

mark = {}
for c, bl in OB.items():
    for b in bl or []: mark[(c, b["d"])] = b["c"]
def pick(p, key):
    t, d, exp, f = p["t"], p["d"], p["exp"], p["f"]
    pr = [(K, mark[(occ(t, exp, K, f), d)] / f) for K in p["c"][key] if mark.get((occ(t, exp, K, f), d), 0) > 0]
    if not pr: return None
    if key == "atm":
        up = [x for x in pr if x[0] >= p["S"]]
        return min(up) if up else None
    return min(pr, key=lambda x: abs(x[0] - p["tg"][key]))
def dyn(m):
    if m <= -0.10: return 0.2
    if m < 0.05: return 0.3
    if m < 0.15: return 0.5
    return 0.6
ARMS = [("All ATM",            lambda m: (1.0, "d30")),
        ("70/30 @ 0.30 delta", lambda m: (0.7, "d30")),
        ("50/50 @ 0.30 delta", lambda m: (0.5, "d30")),
        ("30/70 @ 0.30 delta", lambda m: (0.3, "d30")),
        ("30/70 @ 1 SD",       lambda m: (0.3, "sd")),
        ("All @ 0.30 delta",   lambda m: (0.0, "d30")),
        ("All @ 1 SD",         lambda m: (0.0, "sd")),
        ("Dynamic @ 0.30 dl",  lambda m: (dyn(m), "d30")),
        ("Dynamic @ 1 SD",     lambda m: (dyn(m), "sd"))]

ep = {}
for p in plan:
    a, s1, d3 = pick(p, "atm"), pick(p, "sd"), pick(p, "d30")
    rec = ep.setdefault(p["ep"], {"weeks": 0, "tot": {k: 0.0 for k, _ in ARMS}, "wk": {k: [] for k, _ in ARMS}})
    if not (a and s1 and d3): continue
    Sx = close[p["t"]][p["exp"]]; note = p["S"] * 1000; leg = {"sd": s1, "d30": d3}
    rec["weeks"] += 1
    for k, rule in ARMS:
        sh, o = rule(p["m"]); na = round(sh*10); no = 10 - na
        pl = (na*(a[1] - max(0, Sx-a[0])) + no*(leg[o][1] - max(0, Sx-leg[o][0]))) * 100
        rec["tot"][k] += pl / note * 100; rec["wk"][k].append(pl / note * 100)

good = [(i, EPS[i], r) for i, r in ep.items() if r["weeks"] >= 13]
print("\nepisodes with >= 13 of 26 weeks priced: %d of %d" % (len(good), len(EPS)))
drop = [EPS[i]["t"] + " " + EPS[i]["d"] + " (%d wk)" % r["weeks"] for i, r in ep.items() if r["weeks"] < 13]
if drop: print("  dropped:", ", ".join(drop))
def per26(r, k): return r["tot"][k] / r["weeks"] * 26     # scale to a full 26 weeks

def table(title, sel):
    if not sel: return
    print("\n%s  (n=%d)" % (title, len(sel)))
    print("  %-20s %10s %10s %10s %10s" % ("arm", "6m calls", "median", "lose wks", "worst 6m"))
    for k, _ in ARMS:
        v = [per26(r, k) for _, _, r in sel]
        wk = [x for _, _, r in sel for x in r["wk"][k]]
        print("  %-20s %+9.2f%% %+9.2f%% %9.0f%% %+9.2f%%" % (k, statistics.mean(v), statistics.median(v),
              100*sum(x < 0 for x in wk)/len(wk), min(v)))
table("ALL ENTRIES", good)
for tag in ("fell", "sideways", "recovered"):
    table("NEXT 6 MONTHS: " + tag.upper(), [g for g in good if g[1]["tag"] == tag])
table("YOUR THESIS: sideways or recovered", [g for g in good if g[1]["tag"] != "fell"])

print("\npaired vs All ATM, 6-month total, mean diff and t (all entries / thesis only):")
for k, _ in ARMS[1:]:
    out = []
    for sel in (good, [g for g in good if g[1]["tag"] != "fell"]):
        df = [per26(r, k) - per26(r, "All ATM") for _, _, r in sel]
        out.append("%+6.2f pts t=%+4.1f" % (statistics.mean(df), statistics.mean(df)/(statistics.stdev(df)/math.sqrt(len(df)))))
    print("  %-20s %s   |   %s" % (k, out[0], out[1]))

print("\nper entry, 6-month call P&L as %% of stock value:")
print("  %-18s %-10s %6s " % ("", "", "wks") + "".join("%9s" % k.split(" @")[0][:8] for k, _ in ARMS))
for i, e, r in sorted(good, key=lambda g: g[1]["move"]):
    print("  %-5s %s %+5.0f%% %-9s %3d " % (e["t"], e["d"], e["move"]*100, e["tag"], r["weeks"]) +
          "".join("%+8.1f%%" % per26(r, k) for k, _ in ARMS))
