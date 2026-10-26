"""Fetch put chains from Theta (EOD bid/ask) for the ITM-put research.
weekly: each weekly expiry, from the prior Friday to expiry (short puts)
monthly: each monthly expiry, the last ~210 days (long puts, daily marks)
Usage: TK=<proxy key> python3 fetch.py NKE 2024-09-01 2026-10-16"""
import json, os, sys, urllib.request, datetime, concurrent.futures as cf
TK = os.environ['TK']; B = "https://sunnyfi-theta.fly.dev"
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, "data")
def tj(path):
    err = None
    for _ in range(3):
        try:
            r = urllib.request.Request(B + path + "&format=json", headers={"x-proxy-key": TK})
            return json.loads(urllib.request.urlopen(r, timeout=240).read()).get("response", [])
        except Exception as e: err = e
    print("FAIL", path, err, flush=True); return []
D = datetime.date.fromisoformat
def ymd(s): return s.replace("-", "")
def chain(t, exp, start, end, lo, hi):
    rows = tj(f"/v3/option/history/eod?symbol={t}&expiration={ymd(exp)}&right=put&start_date={ymd(start)}&end_date={ymd(end)}")
    out = {}
    for x in rows:
        k = float(x["contract"]["strike"])
        if not (lo <= k <= hi): continue
        for d in x["data"]:
            day = (d.get("created") or d.get("last_trade") or "")[:10]
            b, a = d.get("bid"), d.get("ask")
            if not day or b is None or a is None or a <= 0: continue
            out.setdefault(day, {})[str(k)] = [b, a]
    return out
def main(t, fr, to):
    cl = json.load(open(os.path.join(DATA, f"{t.lower()}_closes.json")))["bars"]
    exps = [x["expiration"] for x in tj(f"/v3/option/list/expirations?symbol={t}")]
    exps = sorted(e for e in exps if fr < e <= to)
    json.dump(exps, open(os.path.join(DATA, f"{t.lower()}_exps.json"), "w"))
    days = sorted(cl)
    # weekly = last listed expiry of each ISO week that is a trading day
    wk = {}
    for e in exps:
        if e in cl: y, w, _ = D(e).isocalendar(); wk[(y, w)] = e
    weekly = sorted(wk.values())
    # monthly = third Friday (or the expiry closest to it) of each month
    mon = {}
    for e in exps:
        d = D(e)
        if d.weekday() == 4 and 15 <= d.day <= 21: mon[e[:7]] = e
    monthly = sorted(mon.values())
    jobs = []
    for i, e in enumerate(weekly):
        prev = [d for d in days if d < e][-6:]                  # a week of entry days before it
        if not prev: continue
        s = prev[0]; spot = cl[prev[-1]]
        jobs.append(("w", e, s, e, spot * 0.80, spot * 1.05))
    for e in monthly:
        s = (D(e) - datetime.timedelta(days=215)).isoformat()
        span = [cl[d] for d in days if s <= d <= e] or [cl[days[-1]]]
        jobs.append(("m", e, max(s, fr), e, min(span) * 0.75, max(span) * 1.25))
    print(t, len(weekly), "weekly,", len(monthly), "monthly", flush=True)
    res = {"w": {}, "m": {}}
    with cf.ThreadPoolExecutor(2) as pool:
        futs = {pool.submit(chain, t, e, s, en, lo, hi): (kind, e) for (kind, e, s, en, lo, hi) in jobs}
        for f in cf.as_completed(futs):
            kind, e = futs[f]; res[kind][e] = f.result()
    json.dump({"weekly": weekly, "monthly": monthly, "chains": res}, open(os.path.join(DATA, f"{t.lower()}_puts.json"), "w"))
    print(t, "saved", sum(len(v) for v in res["w"].values()), "weekly day-chains,", sum(len(v) for v in res["m"].values()), "monthly day-chains", flush=True)
if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
