import json,urllib.request,datetime,time
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
dayset=set(days)

# Candidate expiries: every Mon/Wed/Fri that is a trading day.
cands=[d for d in days if datetime.date.fromisoformat(d).weekday() in (0,2,4)]
def occ(exp,cp,k):
    return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(k*1000)))
# probe an ATM CALL at whole-dollar strike (most reliably listed)
need=[occ(e,"C",round(close[e])) for e in cands]
bars={}
for i in range(0,len(need),60):
    b=need[i:i+60]
    rq=urllib.request.Request(U,data=json.dumps({"contracts":b,"from":"2024-06-01","to":"2026-08-21"}).encode(),
        headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=300))
    bars.update(r.get("bars") or {})
    print("  batch %d/%d"%(i//60+1,(len(need)+59)//60),flush=True)
    time.sleep(0.5)
live=[]
for e,c in zip(cands,need):
    if bars.get(c): live.append(e)
json.dump({"listed":live},open("expiries.json","w"))
from collections import Counter
wd=Counter(datetime.date.fromisoformat(e).weekday() for e in live)
print("probed",len(cands),"listed",len(live))
print("by weekday  Mon",wd[0]," Wed",wd[2]," Fri",wd[4])
# when did Mon/Wed start?
for w,nm in ((0,"Mon"),(2,"Wed")):
    xs=[e for e in live if datetime.date.fromisoformat(e).weekday()==w]
    print(nm,"first",xs[0] if xs else None,"count",len(xs))
