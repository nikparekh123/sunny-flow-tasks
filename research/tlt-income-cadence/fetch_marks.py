import json,urllib.request,time
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
need=json.load(open("plan.json"))["need"]
bars={};miss=0
for i in range(0,len(need),60):
    b=need[i:i+60]
    for attempt in range(3):
        try:
            rq=urllib.request.Request(U,data=json.dumps({"contracts":b,"from":"2024-09-01","to":"2026-08-21"}).encode(),
                headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
            r=json.load(urllib.request.urlopen(rq,timeout=300)); break
        except Exception as e:
            if attempt==2: raise
            time.sleep(3)
    bars.update(r.get("bars") or {}); miss+=len(r.get("missing") or [])
    if (i//60+1)%5==0: print("  batch %d/%d"%(i//60+1,(len(need)+59)//60),flush=True)
    time.sleep(0.4)
json.dump(bars,open("opt_bars.json","w"))
print("with bars:",sum(1 for v in bars.values() if v),"of",len(need),"missing",miss)
