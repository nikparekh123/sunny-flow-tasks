import json,urllib.request
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/stock-history"
r=urllib.request.Request(U,data=json.dumps({"ticker":"NVDA","from":"2024-01-01","to":"2026-08-12"}).encode(),
  headers={"apikey":K,"Authorization":"Bearer "+K,"content-type":"application/json"})
d=json.loads(urllib.request.urlopen(r,timeout=120).read())
json.dump(d,open("nvda_hist.json","w"))
print("bars",len(d.get("bars") or []),"| first",(d.get("bars") or [{}])[0],"| last",(d.get("bars") or [{}])[-1])
