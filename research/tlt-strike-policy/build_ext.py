import json,math,datetime,urllib.request,time,os
H=json.load(open("tlt_hist.json")); bars={b["d"]:b["c"] for b in H["bars"]}
plan=json.load(open("plan.json"))["plan"]
# the EXT arm must choose among a LADDER, not a single target strike, so it needs
# every candidate near spot on the roll date.
need=set()
for d,r in plan.items():
    S=r["S"]; exp=datetime.date.fromisoformat(r["exp"]).strftime("%y%m%d")
    base=round(S*2)/2
    for off in [x*0.5 for x in range(-4,4)]:
        K=base+off
        need.add("O:TLT%sP%08d"%(exp,int(round(K*1000))))
have=json.load(open("opt_bars.json")) if os.path.exists("opt_bars.json") else {}
todo=sorted(need-set(have))
print("ladder contracts",len(need),"| already have",len(need)-len(todo),"| to fetch",len(todo))
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
for i in range(0,len(todo),60):
    b=todo[i:i+60]
    rq=urllib.request.Request(U,data=json.dumps({"contracts":b,"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=400))
    have.update(r.get("bars") or {})
    print("  %d/%d  +%d"%(i//60+1,(len(todo)+59)//60,len(r.get("bars") or {})),flush=True)
    time.sleep(0.5)
json.dump(have,open("opt_bars.json","w"))
print("total contracts with bars:",sum(1 for v in have.values() if v))
