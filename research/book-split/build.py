# -*- coding: utf-8 -*-
"""Book names: Friday-to-Friday call strikes at ATM, +1%, 0.6 SD and 1 SD (8 Oct 2026)."""
import json,urllib.request,datetime,time,math,statistics as st,sys
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
H="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/"
def call(fn,body):
    rq=urllib.request.Request(H+fn,data=json.dumps(body).encode(),headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(rq,timeout=300))
def D(s): return datetime.date.fromisoformat(s)
for t in (sys.argv[1:] or ["NKE","BABA","NFLX","LULU","FIS","PEP","KR"]):
    h=call("stock-history",{"ticker":t,"from":"2024-06-01","to":"2026-10-08","dividends":True}); json.dump(h,open(f"{t}_hist.json","w"))
    close={x["d"]:x["c"] for x in h["bars"]}; days=sorted(close)
    fr=[d for d in days if d>="2024-09-06" and D(d).weekday()==4]
    rolls=[]
    for i,d in enumerate(fr[:-1]):
        e=fr[i+1]
        if (D(e)-D(d)).days>9: continue
        j=days.index(d); S=close[d]
        lr=[math.log(close[days[k+1]]/close[days[k]]) for k in range(j-21,j)]
        sd=st.stdev(lr)*math.sqrt(252); w=sd*math.sqrt(7/365)
        tg={"atm":S,"p1":S*1.01,"sd6":S*(1+0.6*w),"sd":S*(1+w)}
        step=0.5 if S<100 else 1.0 if S<300 else 5.0
        ks=set()
        for v in tg.values():
            for stp in ({step,1.0,2.5} if S>=100 else {0.5,1.0}):
                b=round(v/stp)*stp; ks|={b-stp,b,b+stp}
        rolls.append({"d":d,"exp":e,"S":S,"m":S/close[days[j-21]]-1,"tg":tg,"kc":sorted(k for k in ks if k>0)})
    # NFLX split 10:1 on 2025-11-17: closes are split-adjusted, older contracts are not
    f=lambda e: 10 if (t=="NFLX" and e<"2025-11-17") else 1
    occ=lambda e,k:"O:%s%sC%08d"%(t,D(e).strftime("%y%m%d"),int(round(k*f(e)*1000)))
    need=sorted({occ(r["exp"],k) for r in rolls for k in r["kc"]}); bars={}
    for i in range(0,len(need),60):
        bars.update({k:v for k,v in (call("opt-history",{"contracts":need[i:i+60],"from":"2024-09-01","to":"2026-10-08"}).get("bars") or {}).items() if v}); time.sleep(0.2)
    json.dump({"rolls":rolls,"bars":bars},open(f"{t}_split.json","w"))
    print(t,"rolls",len(rolls),"contracts",len(need),"with bars",len(bars))
