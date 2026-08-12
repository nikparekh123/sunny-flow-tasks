import json,urllib.request,time
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
need=json.load(open("plan.json"))["need"]
bars={};missing=[]
for i in range(0,len(need),60):
    b=need[i:i+60]
    rq=urllib.request.Request(U,data=json.dumps({"contracts":b,"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=300))
    bars.update(r.get("bars") or {}); missing+=r.get("missing") or []
    print("  batch %d/%d  +%d  missing %d"%(i//60+1,(len(need)+59)//60,len(r.get("bars") or {}),len(r.get("missing") or [])),flush=True)
    time.sleep(1)
json.dump(bars,open("opt_bars.json","w"))
print("with bars:",sum(1 for v in bars.values() if v),"of",len(need),"  missing",len(missing))
