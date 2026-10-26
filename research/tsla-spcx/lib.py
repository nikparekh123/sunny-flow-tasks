import json, os, math, urllib.request, datetime, statistics
from statistics import NormalDist
N = NormalDist(); R = 0.04
K = "sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U = "https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "optcache")
os.makedirs(CACHE, exist_ok=True)
def D(s): return datetime.date.fromisoformat(s)
def occ(t, exp, K_, cp="C"):
    return "O:%s%s%s%08d" % (t, D(exp).strftime("%y%m%d"), cp, int(round(K_*1000)))
def fetch(contracts, fr, to):
    """Daily bars for OCC contracts; cached per contract (whole life fetched once)."""
    out, need = {}, []
    for c in contracts:
        p = os.path.join(CACHE, c.replace(":", "_") + ".json")
        if os.path.exists(p): out[c] = json.load(open(p))
        else: need.append(c)
    for i in range(0, len(need), 60):
        chunk = need[i:i+60]
        r = urllib.request.Request(U, data=json.dumps({"contracts": chunk, "from": fr, "to": to}).encode(),
            headers={"apikey": K, "Authorization": "Bearer " + K, "content-type": "application/json"})
        d = json.loads(urllib.request.urlopen(r, timeout=300).read())
        for c in chunk:
            bars = {}
            for b in (d.get("bars") or {}).get(c, []) or []:
                day = datetime.datetime.utcfromtimestamp(b["t"]/1000).date().isoformat()
                bars[day] = b["c"]
            json.dump(bars, open(os.path.join(CACHE, c.replace(":", "_") + ".json"), "w"))
            out[c] = bars
    return out
def bs_call(S, Kk, T, v):
    if T <= 0 or v <= 0: return max(0.0, S-Kk)
    d1 = (math.log(S/Kk) + (R + v*v/2)*T)/(v*math.sqrt(T)); d2 = d1 - v*math.sqrt(T)
    return S*N.cdf(d1) - Kk*math.exp(-R*T)*N.cdf(d2)
def bs_delta(S, Kk, T, v):
    if T <= 0 or v <= 0: return 1.0 if S > Kk else 0.0
    return N.cdf((math.log(S/Kk) + (R + v*v/2)*T)/(v*math.sqrt(T)))
def iv_from(price, S, Kk, T):
    if price <= max(0, S - Kk*math.exp(-R*T)) + 1e-6 or T <= 0: return None
    lo, hi = 0.01, 5.0
    for _ in range(80):
        m = (lo+hi)/2
        if bs_call(S, Kk, T, m) > price: hi = m
        else: lo = m
    return (lo+hi)/2
