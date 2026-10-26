# -*- coding: utf-8 -*-
"""Nik's TLT covered-call plan (meeting 7 Oct 2026), the roll schedule.

Three lines of 50 calls, each expiring on its own weekday (Mon, Wed, Fri) and
re-written at its expiry for the same weekday a week out. On any Monday the book
holds a 2-day (Wed), a 4-day (Fri) and a 7-day (next Mon) line, which is how he
described it. Fetches a strike ladder near spot for every write so the sim can
pick ATM or one strike up from real bars.
"""
import json,urllib.request,datetime,time,os
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
L=json.load(open("expiries.json"))["listed"]
def D(s): return datetime.date.fromisoformat(s)
def occ(exp,k): return "O:TLT%sC%08d"%(D(exp).strftime("%y%m%d"),int(round(k*1000)))
START="2024-09-09"
plan={}
for wd,nm in ((0,"MON"),(2,"WED"),(4,"FRI")):
    cur=min(e for e in L if e>=START and D(e).weekday()==wd)
    rolls=[]
    while True:
        fwd=[e for e in L if 5<=(D(e)-D(cur)).days<=9]
        if not fwd: break
        same=[e for e in fwd if D(e).weekday()==wd]
        exp=same[0] if same else min(fwd,key=lambda e:abs((D(e)-D(cur)).days-7))
        S=close[cur]; base=round(S*2)/2
        rolls.append({"d":cur,"exp":exp,"S":S,"ks":[base+o for o in (-1,-0.5,0,0.5,1,1.5)]})
        cur=exp
    plan[nm]=rolls
    print(nm,len(rolls),rolls[0]["d"],"->",rolls[-1]["exp"])
need=sorted({occ(r["exp"],k) for v in plan.values() for r in v for k in r["ks"]})
cache={}
for f in ("../tlt-income-cadence/opt_bars.json","opt_bars.json"):
    if os.path.exists(f): cache.update({k:v for k,v in json.load(open(f)).items() if v})
# old cache stops 2026-08-21: refetch anything expiring after it
todo=[c for c in need if c not in cache or c[6:12]>="260821"]
print("need",len(need),"fetch",len(todo))
for i in range(0,len(todo),60):
    b=todo[i:i+60]
    rq=urllib.request.Request(U,data=json.dumps({"contracts":b,"from":"2024-08-25","to":"2026-10-07"}).encode(),
        headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=300))
    cache.update({k:v for k,v in (r.get("bars") or {}).items() if v})
    time.sleep(0.5)
json.dump({c:cache[c] for c in need if c in cache},open("opt_bars.json","w"))
json.dump(plan,open("plan.json","w"))
print("with bars",sum(1 for c in need if c in cache),"of",len(need))
