# -*- coding: utf-8 -*-
"""TLT vs SLV vs URA: weekly Friday ATM calls on a share block (Nik, 8 Oct 2026).
One line, Friday to Friday, so all three are tested the same way (URA lists
Fridays only). Fetches a strike ladder near spot for every write."""
import json,urllib.request,datetime,time,sys
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
def D(s): return datetime.date.fromisoformat(s)
for t in (sys.argv[1:] or ["TLT","SLV","URA"]):
    close={x["d"]:x["c"] for x in json.load(open(f"{t}_hist.json"))["bars"]}
    L=[e for e in json.load(open(f"{t}_expiries.json"))["listed"] if D(e).weekday()==4]
    rolls=[]; cur=min(e for e in L if e>="2024-09-06")
    while True:
        nx=[e for e in L if 5<=(D(e)-D(cur)).days<=14]   # holiday weeks: skip to the next Friday
        if not nx: break
        S=close[cur]; ks=sorted({round(S*2)/2+o for o in (-1,-0.5,0,0.5,1,1.5,2)}|{float(round(S))+o for o in (-1,0,1,2)})
        rolls.append({"d":cur,"exp":nx[0],"S":S,"ks":ks}); cur=nx[0]
    occ=lambda e,k:"O:%s%sC%08d"%(t,D(e).strftime("%y%m%d"),int(round(k*1000)))
    need=sorted({occ(r["exp"],k) for r in rolls for k in r["ks"]})
    bars={}
    for i in range(0,len(need),60):
        rq=urllib.request.Request(U,data=json.dumps({"contracts":need[i:i+60],"from":"2024-09-01","to":"2026-10-08"}).encode(),
            headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
        bars.update({k:v for k,v in (json.load(urllib.request.urlopen(rq,timeout=300)).get("bars") or {}).items() if v}); time.sleep(0.3)
    json.dump({"rolls":rolls,"bars":bars},open(f"{t}_calls.json","w"))
    print(t,"rolls",len(rolls),rolls[0]["d"],"->",rolls[-1]["exp"],"contracts with bars",len(bars),"of",len(need))
