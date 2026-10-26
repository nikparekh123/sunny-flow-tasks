"""LEAP legs on real end-of-day quotes: pick the strike on the buy date by
target (atm = nearest spot, d75 / d90 = delta nearest 0.75 / 0.90 from each
strike's IV), then the contract's daily mid. Saved to <t>_leaps.json."""
import json, os, sys, urllib.request
from lib import bs_delta, iv_from, D
TK = os.environ["TK"]; B = "https://sunnyfi-theta.fly.dev"
def tj(path):
    r = urllib.request.Request(B + path + "&format=json", headers={"x-proxy-key": TK})
    return json.loads(urllib.request.urlopen(r, timeout=300).read()).get("response", [])
ymd = lambda s: s.replace("-", "")
def chain_on(t, exp, day):
    out = {}
    for x in tj(f"/v3/option/history/eod?symbol={t}&expiration={ymd(exp)}&right=call&start_date={ymd(day)}&end_date={ymd(day)}"):
        for d in x["data"]:
            if d.get("ask") and d["ask"] > 0: out[float(x["contract"]["strike"])] = (d["bid"] + d["ask"]) / 2
    return out
def series(t, exp, k, fr, to):
    """Daily mids, asked in chunks of under a year (Theta's limit)."""
    import datetime
    out = {}; a = D(fr)
    while a <= D(to):
        z = min(D(to), a + datetime.timedelta(days=300))
        for x in tj(f"/v3/option/history/eod?symbol={t}&expiration={ymd(exp)}&strike={k:.3f}&right=call&start_date={ymd(a.isoformat())}&end_date={ymd(z.isoformat())}"):
            for d in x["data"]:
                day = (d.get("created") or d.get("last_trade") or "")[:10]
                if day and d.get("ask") and d["ask"] > 0: out[day] = (d["bid"] + d["ask"]) / 2
        a = z + datetime.timedelta(days=1)
    return out
def choose(ch, S, T, target):
    if target == "atm": return min(ch, key=lambda k: abs(k - S))
    want = {"d75": 0.75, "d90": 0.90}[target]
    best = None
    for k, m in ch.items():
        if k > S * 1.2: continue
        v = iv_from(m, S, k, T)
        if not v: continue
        dlt = bs_delta(S, k, T, v)
        if best is None or abs(dlt - want) < abs(best[0] - want): best = (dlt, k)
    return best[1]
def legs(t, plan, end, out=None):
    cl = {b["d"]: b["c"] for b in json.load(open(f"{t.lower()}.json"))["bars"]}
    res = {}
    for target in ("atm", "d75", "d90"):
        segs = []
        for i, (day, exp) in enumerate(plan):
            stop = plan[i + 1][0] if i + 1 < len(plan) else end
            S = cl[day]; T = (D(exp) - D(day)).days / 365
            ch = chain_on(t, exp, day)
            k = choose(ch, S, T, target)
            ser = series(t, exp, k, day, stop)
            segs.append({"buy": day, "exp": exp, "k": k, "spot": S, "series": ser})
            print(t, target, day, exp, "strike", k, "cost", round(ser.get(day, 0), 2), "days", len(ser), flush=True)
        res[target] = segs
    json.dump(res, open(out or f"{t.lower()}_leaps.json", "w"))
if __name__ == "__main__":
    if sys.argv[1] == "TSLA": legs("TSLA", [("2024-10-14", "2027-01-15"), ("2026-01-02", "2028-01-21")], "2026-10-13")
    elif len(sys.argv) > 2: legs(sys.argv[1], [(sys.argv[2], sys.argv[3])], "2026-10-13", sys.argv[4])
    else: legs("SPCX", [("2026-06-18", "2028-01-21")], "2026-10-13")
