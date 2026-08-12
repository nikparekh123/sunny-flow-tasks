import json,urllib.request
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/stock-history"
r=urllib.request.Request(U,data=json.dumps({"ticker":"NVDA","from":"2018-01-01","to":"2026-08-12"}).encode(),
  headers={"apikey":K,"Authorization":"Bearer "+K,"content-type":"application/json"})
d=json.loads(urllib.request.urlopen(r,timeout=180).read())
json.dump(d,open("nvda_long.json","w"))
b=d.get("bars") or []
print("bars",len(b),b[0]["d"],"->",b[-1]["d"])
import datetime
cl={x["d"]:x["c"] for x in b}; days=sorted(cl)
FRI=[x for x in days if datetime.date.fromisoformat(x).weekday()==4]
print("\n72-week window drift, every 8th start:")
for i in range(0,len(FRI)-72,8):
    a,z=FRI[i],FRI[i+71]
    print("  %s -> %s  %+7.0f%%"%(a,z,100*(cl[z]/cl[a]-1)))
