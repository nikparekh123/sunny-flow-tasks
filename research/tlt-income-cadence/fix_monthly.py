import json,urllib.request,datetime,time
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
D=json.load(open("plan.json")); plan=D["plan"]
def occ(e,cp,k): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(e).strftime("%y%m%d"),cp,int(round(k*1000)))
need=set()
for r in plan["MONTHLY"]+plan["BIWEEKLY"]:
    base=round(r["S"]*2)/2.0
    ks=sorted({base+o for o in [x*0.5 for x in range(-5,6)]})
    r["ks"]=sorted(set(r["ks"])|set(ks))
    for k in ks: need.add(occ(r["exp"],"C",k)); need.add(occ(r["exp"],"P",k))
need=sorted(need); print("extra contracts",len(need))
bars=json.load(open("opt_bars.json"))
for i in range(0,len(need),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":need[i:i+60],"from":"2024-09-01","to":"2026-08-21"}).encode(),
        headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    bars.update(json.load(urllib.request.urlopen(rq,timeout=300)).get("bars") or {}); time.sleep(0.4)
json.dump(bars,open("opt_bars.json","w")); json.dump(D,open("plan.json","w"))
print("bars now",sum(1 for v in bars.values() if v))
