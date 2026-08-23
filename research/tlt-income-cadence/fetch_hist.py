import json,urllib.request
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/stock-history"
rq=urllib.request.Request(U,data=json.dumps({"ticker":"TLT","from":"2024-06-01","to":"2026-08-21"}).encode(),
    headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
r=json.load(urllib.request.urlopen(rq,timeout=300))
json.dump(r,open("tlt_hist.json","w"))
b=r["bars"]
print("bars",len(b),b[0]["d"],"->",b[-1]["d"])
print("close range %.2f - %.2f"%(min(x["c"] for x in b),max(x["c"] for x in b)))
