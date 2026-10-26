# -*- coding: utf-8 -*-
"""Strike targets for the split retest (Nik, 8 Oct 2026): for every Friday write,
ATM, +1% and 1 SD (21-day realised, one week), each with its neighbours."""
import json,urllib.request,datetime,time,math,statistics as st
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
def D(s): return datetime.date.fromisoformat(s)
OUT={}
for t in ("TLT","SLV","URA","SPY","QQQ","IWM"):
    close={x["d"]:x["c"] for x in json.load(open(f"{t}_hist.json"))["bars"]}; days=sorted(close)
    rolls=json.load(open(f"{t}_calls.json"))["rolls"]
    occ=lambda e,k:"O:%s%sC%08d"%(t,D(e).strftime("%y%m%d"),int(round(k*1000)))
    need=set()
    for r in rolls:
        i=days.index(r["d"]); S=r["S"]
        lr=[math.log(close[days[j+1]]/close[days[j]]) for j in range(i-21,i)]
        sd=st.stdev(lr)*math.sqrt(252); r["rv"]=sd; r["m"]=S/close[days[i-21]]-1
        r["tg"]={"atm":S,"p1":S*1.01,"sd":S*(1+sd*math.sqrt(7/365))}
        steps=[0.5,1.0] if S<150 else [1.0]
        ks=set()
        for v in r["tg"].values():
            for stp in steps:
                b=round(v/stp)*stp; ks|={b-stp,b,b+stp}
        r["kc"]=sorted(ks); need|={occ(r["exp"],k) for k in ks}
    old=json.load(open(f"{t}_calls.json"))["bars"]
    todo=[c for c in sorted(need) if c not in old]
    bars=dict(old)
    for i in range(0,len(todo),60):
        rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-09-01","to":"2026-10-08"}).encode(),
            headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
        bars.update({k:v for k,v in (json.load(urllib.request.urlopen(rq,timeout=300)).get("bars") or {}).items() if v}); time.sleep(0.2)
    json.dump({"rolls":rolls,"bars":bars},open(f"{t}_split.json","w"))
    print(t,"rolls",len(rolls),"need",len(need),"fetched",len(todo),"have",sum(1 for c in need if c in bars))
