# -*- coding: utf-8 -*-
"""How many calls at the money, how many out? Real marks, 8 names, 2 years.

Each week, on the week's last close, sell 10 next-Friday calls a name. Every arm
holds the same LEAPs, so only the short calls differ, and the comparison is the
short calls' P&L: credit taken, less what they are worth at expiry (bought back,
never assigned). Reported as a yield on the 1,000 shares' worth of stock, so
LULU at 500 and KR at 50 count the same.

Real option closes from Polygon (opt-history). A week is only counted when every
strike every arm needs actually printed that day, so all arms see the same weeks.
1 SD and the 0.30-delta strike use 21-day realised vol (no historical IV here).
"""
import json, math, datetime, statistics, urllib.request, time, sys
from statistics import NormalDist
N = NormalDist(); R = 0.045
NAMES = ["NKE", "BABA", "NFLX", "LULU", "FIS", "PEP", "UBER", "KR"]
SPLIT = {"NFLX": ("2025-11-17", 10)}      # before this date, strikes are 10x

close, days = {}, {}
for t in NAMES:
    b = json.load(open(t.lower() + ".json"))["bars"]
    close[t] = {x["d"]: x["c"] for x in b}; days[t] = sorted(close[t])
ALL = sorted(set(days["NKE"]))

def rv(t, d):
    ds = days[t]; i = ds.index(d)
    if i < 21: return None
    w = ds[i-21:i+1]
    lr = [math.log(close[t][w[j+1]]/close[t][w[j]]) for j in range(21)]
    return statistics.stdev(lr) * math.sqrt(252)

# the week's last trading day, and next week's last trading day as expiry
weeks = {}
for d in ALL:
    y, w, _ = datetime.date.fromisoformat(d).isocalendar(); weeks[(y, w)] = d
WEND = sorted(weeks.values())
FROM, TO = sys.argv[1], sys.argv[2]
SCHED = [(WEND[i], WEND[i+1]) for i in range(len(WEND)-1) if FROM <= WEND[i] <= TO]

def factor(t, d):
    s = SPLIT.get(t); return s[1] if s and d < s[0] else 1
def occ(t, exp, K, f):
    return "O:%s%sC%08d" % (t, datetime.date.fromisoformat(exp).strftime("%y%m%d"), int(round(K*f*1000)))
def grid(x, up=None):
    out = set()
    for inc in (0.5, 1, 2.5, 5):
        for k in (math.floor(x/inc)*inc, math.ceil(x/inc)*inc):
            if k > 0: out.add(round(k, 2))
    return sorted(out)
def kdelta(S, v, T, dl):
    return S * math.exp((R + v*v/2)*T - N.inv_cdf(dl)*v*math.sqrt(T))

plan, need = [], {}
for d, exp in SCHED:
    T = max(1, (datetime.date.fromisoformat(exp) - datetime.date.fromisoformat(d)).days) / 365
    for t in NAMES:
        if d not in close[t] or exp not in close[t]: continue
        v = rv(t, d)
        if not v: continue
        S = close[t][d]; f = factor(t, d)
        sd = S * v * math.sqrt(T)
        tg = {"atm": S, "sd": S + sd, "d30": kdelta(S, v, T, 0.30)}
        cands = {k: grid(x) for k, x in tg.items()}
        plan.append({"t": t, "d": d, "exp": exp, "S": S, "f": f, "tg": tg, "c": cands})
        for ks in cands.values():
            for K in ks: need.setdefault(d, set()).add((occ(t, exp, K, f)))

try: OB = json.load(open("optc.json"))
except Exception: OB = {}
todo = [(d, c) for d, cs in sorted(need.items()) for c in sorted(cs) if c not in OB]
print("name-weeks", len(plan), "| contracts", sum(len(v) for v in need.values()), "| to fetch", len(todo), flush=True)
K_ = "sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U = "https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
byd = {}
for d, c in todo: byd.setdefault(d, []).append(c)
n = 0
for d, cs in sorted(byd.items()):
    for i in range(0, len(cs), 60):
        rq = urllib.request.Request(U, data=json.dumps({"contracts": cs[i:i+60], "from": d, "to": d}).encode(),
            headers={"Authorization": "Bearer " + K_, "apikey": K_, "Content-Type": "application/json"})
        for attempt in range(3):
            try:
                got = json.load(urllib.request.urlopen(rq, timeout=120)).get("bars") or {}
                for c in cs[i:i+60]: OB[c] = got.get(c) or []
                break
            except Exception as e:
                print("  retry", d, attempt, e, flush=True); time.sleep(2)
        n += 1; time.sleep(0.15)
    if n % 20 == 0:
        json.dump(OB, open("optc.json", "w")); print("  fetched through", d, flush=True)
json.dump(OB, open("optc.json", "w"))

mark = {}
for c, bl in OB.items():
    for b in bl or []: mark[(c, b["d"])] = b["c"]

def pick(p, key):
    """The priced strike for a target: the lowest at or above spot for ATM, the
    nearest to the target otherwise. Returns (K per share, premium per share)."""
    t, d, exp, f = p["t"], p["d"], p["exp"], p["f"]
    priced = [(K, mark[(occ(t, exp, K, f), d)] / f) for K in p["c"][key]
              if mark.get((occ(t, exp, K, f), d), 0) > 0]
    if not priced: return None
    if key == "atm":
        up = [x for x in priced if x[0] >= p["S"]]
        return min(up) if up else None
    return min(priced, key=lambda x: abs(x[0] - p["tg"][key]))

def share_dyn(m, trend=False):
    if trend and m >= 0.25: return 0.40
    if m <= -0.10: return 0.20
    if m < 0.05: return 0.30
    if m < 0.15: return 0.50
    return 0.60

def quiet(m):
    """The inverse: most at the money in a flat month, least after a big move
    either way (fitted AFTER seeing the regime table, so in-sample)."""
    if -0.05 < m < 0.05: return 0.60
    if -0.10 < m < 0.15: return 0.30
    return 0.20

ARMS = {
    "All ATM (today)":          lambda m: (1.0, "sd"),
    "30/70, OTM at 1 SD":       lambda m: (0.3, "sd"),
    "30/70, OTM at 0.30 delta": lambda m: (0.3, "d30"),
    "Dynamic, OTM at 1 SD":     lambda m: (share_dyn(m), "sd"),
    "Dynamic, OTM at 0.30 dl":  lambda m: (share_dyn(m), "d30"),
    "Dynamic+trend, 1 SD":      lambda m: (share_dyn(m, True), "sd"),
    "All at 1 SD":              lambda m: (0.0, "sd"),
    "Calm=ATM, moves=OTM 1SD":  lambda m: (quiet(m), "sd"),
    "Calm=ATM, moves=OTM 0.30": lambda m: (quiet(m), "d30"),
    "70% ATM, 30% at 0.30 dl":  lambda m: (0.7, "d30"),
    "70% ATM, 30% at 1 SD":     lambda m: (0.7, "sd"),
}
rows = []
for p in plan:
    t, d, exp, S = p["t"], p["d"], p["exp"], p["S"]
    a, s1, d3 = pick(p, "atm"), pick(p, "sd"), pick(p, "d30")
    if not (a and s1 and d3): continue
    ds = days[t]; i = ds.index(d)
    m = S / close[t][ds[i-21]] - 1 if i >= 21 else 0.0
    Sx = close[t][exp]
    leg = {"atm": a, "sd": s1, "d30": d3}
    r = {"t": t, "d": d, "m": m, "move": Sx/S - 1, "note": S * 1000}
    for name, rule in ARMS.items():
        sh, otm = rule(m); na = round(sh * 10); no = 10 - na
        cr = na * a[1] * 100 + no * leg[otm][1] * 100
        paid = na * max(0, Sx - a[0]) * 100 + no * max(0, Sx - leg[otm][0]) * 100
        r[name] = (cr, paid)
    rows.append(r)

print("\npriced name-weeks: %d of %d" % (len(rows), len(plan)))
cov = {}
for r in rows: cov[r["t"]] = cov.get(r["t"], 0) + 1
print("by name:", ", ".join("%s %d" % (t, cov.get(t, 0)) for t in NAMES))

def yld(r, a): cr, pd = r[a]; return (cr - pd) / r["note"] * 100
print("\n%-26s %9s %9s %9s %8s %9s" % ("arm", "wk yield", "credit", "paid back", "lose wks", "worst wk"))
for a in ARMS:
    ys = [yld(r, a) for r in rows]
    cr = statistics.mean(r[a][0] / r["note"] * 100 for r in rows)
    pd = statistics.mean(r[a][1] / r["note"] * 100 for r in rows)
    print("%-26s %8.3f%% %8.3f%% %8.3f%% %7.0f%% %8.2f%%" % (a, statistics.mean(ys), cr, pd,
          100 * sum(y < 0 for y in ys) / len(ys), min(ys)))

print("\npaired against 'All ATM (today)' and '30/70, OTM at 1 SD' (mean weekly diff, points, and t):")
for base in ("All ATM (today)", "30/70, OTM at 1 SD"):
    for a in ARMS:
        if a == base: continue
        df = [yld(r, a) - yld(r, base) for r in rows]
        se = statistics.stdev(df) / math.sqrt(len(df))
        print("  %-26s vs %-22s %+7.3f  t=%+5.1f" % (a, base, statistics.mean(df), statistics.mean(df) / se))

print("\nby regime (1-month move before the sale):")
bands = [("fell >10%", -9, -0.10), ("-10..+5%", -0.10, 0.05), ("+5..+15%", 0.05, 0.15), ("rose >15%", 0.15, 9)]
for lab, lo, hi in bands:
    sub = [r for r in rows if lo < r["m"] <= hi]
    if not sub: continue
    print("  %-10s n=%3d  " % (lab, len(sub)) + "  ".join("%s %+.3f" % (a.split(",")[0][:13], statistics.mean(yld(r, a) for r in sub)) for a in ARMS))

print("\nby name, weekly yield:")
print("  %-5s" % "" + "".join("%11s" % a[:10] for a in ARMS))
for t in NAMES:
    sub = [r for r in rows if r["t"] == t]
    if sub: print("  %-5s" % t + "".join("%10.3f%%" % statistics.mean(yld(r, a) for r in sub) for a in ARMS))
json.dump(rows, open("rows_%s.json" % FROM, "w"))
