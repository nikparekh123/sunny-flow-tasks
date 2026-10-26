import json, os, sys, urllib.request, datetime, concurrent.futures as cf
TK=os.environ['TK']; B="https://sunnyfi-theta.fly.dev"
def tj(path):
    for k in range(3):
        try:
            r=urllib.request.Request(B+path+"&format=json", headers={"x-proxy-key":TK})
            return json.loads(urllib.request.urlopen(r, timeout=180).read()).get("response",[])
        except Exception as e:
            err=e
    print("FAIL", path, err, flush=True); return []
def D(s): return datetime.date.fromisoformat(s)
def ymd(s): return s.replace("-","")
def closes(t):
    return {b["d"]: b["c"] for b in json.load(open(t.lower()+".json"))["bars"]}
def chain(t, exp, start, end, lo, hi):
    rows=tj(f"/v3/option/history/eod?symbol={t}&expiration={ymd(exp)}&right=call&start_date={ymd(start)}&end_date={ymd(end)}")
    out={}
    for x in rows:
        k=float(x["contract"]["strike"])
        if not (lo<=k<=hi): continue
        for d in x["data"]:
            day=(d.get("created") or d.get("last_trade") or "")[:10]
            if not day: continue
            b,a=d.get("bid"),d.get("ask")
            if b is None or a is None or a<=0: continue
            out.setdefault(day,{})[str(k)]=[b,a]
    return out
def run(t, fr, to):
    cl=closes(t); days=sorted(cl); ex=json.load(open(f"{t.lower()}_exps.json"))
    win=[e for e in ex if fr<e<=to and e in cl]   # expiries that are trading days in the window
    # weekly expiry = last expiry in each ISO week
    wk={}
    for e in win: y,w,_=D(e).isocalendar(); wk[(y,w)]=e
    weekly=sorted(wk.values())
    jobs=[]
    allx=sorted(set(win))
    for e in allx:
        prev_any=max([x for x in allx if x<e] or [None]) if any(x<e for x in allx) else None
        prev_wk=max([x for x in weekly if x<e] or [None]) if any(x<e for x in weekly) else None
        starts=[s for s in (prev_any, prev_wk) if s]
        if not starts: continue
        s=min(starts); spot=cl[s]
        jobs.append((e, s, e, spot*0.6, spot*1.6))
    print(t, len(allx), "expiries,", len(weekly), "weekly", flush=True)
    res={}
    with cf.ThreadPoolExecutor(2) as pool:
        futs={pool.submit(chain, t, e, s, en, lo, hi): e for (e,s,en,lo,hi) in jobs}
        for f in cf.as_completed(futs): res[futs[f]]=f.result()
    json.dump({"weekly": weekly, "all": allx, "chains": res}, open(f"{t.lower()}_chains.json","w"))
    print(t, "saved", sum(len(v) for v in res.values()), "day-chains", flush=True)
if __name__=="__main__":
    run(sys.argv[1], sys.argv[2], sys.argv[3])
