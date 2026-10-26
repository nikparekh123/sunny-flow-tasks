# -*- coding: utf-8 -*-
"""Put bars for the same three-line roll plan (Nik: 'what if I just sell weekly ATM puts')."""
import json,urllib.request,datetime,time,os
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
plan=json.load(open("plan.json"))
def occ(exp,k): return "O:TLT%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(k*1000)))
need=sorted({occ(r["exp"],k) for v in plan.values() for r in v for k in r["ks"]})
cache={k:v for k,v in json.load(open("../tlt-income-cadence/opt_bars.json")).items() if v and "P" in k[10:12]}
todo=[c for c in need if c not in cache or c[6:12]>="260821"]
print("need",len(need),"fetch",len(todo))
for i in range(0,len(todo),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-08-25","to":"2026-10-07"}).encode(),
        headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=300)); cache.update({k:v for k,v in (r.get("bars") or {}).items() if v}); time.sleep(0.5)
json.dump({c:cache[c] for c in need if c in cache},open("put_bars.json","w"))
print("with bars",sum(1 for c in need if c in cache),"of",len(need))
r=json.load(urllib.request.urlopen(urllib.request.Request(U,data=json.dumps({"contracts":[occ("2026-10-14",k) for k in (74,74.5,75,75.5,76,76.5,77)],"from":"2026-10-07","to":"2026-10-07"}).encode(),
    headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"}),timeout=300))
print({k[-8:]:v[-1]["c"] for k,v in (r.get("bars") or {}).items() if v})
