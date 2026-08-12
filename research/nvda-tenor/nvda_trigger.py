# -*- coding: utf-8 -*-
"""Cadence: every Friday, or only when NVDA drops?

Strike held at 1% OTM in every arm, and the same total delta deployed, so the only
variable is WHEN. Each entry writes to the next Friday at least two sessions out.
"""
import json, math, datetime, statistics, urllib.request, time
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist(); OB=json.load(open("nvda_opt.json"))
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)
mv={days[i]:100*(close[days[i]]/close[days[i-1]]-1) for i in range(1,len(days))}
def nextFri(d):
    i=days.index(d)
    for x in days[i+2:]:
        if datetime.date.fromisoformat(x).weekday()==4: return x
    return None
def occ(exp,K): return "O:NVDA%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000)))

ARMS={"every Friday":None,"drop > 0.5%":-0.5,"drop > 1%":-1.0,"drop > 2%":-2.0}
plan={}; need=set()
for nm,thr in ARMS.items():
    rows=[]
    for d in days[22:]:
        if d not in rv: continue
        if thr is None:
            if datetime.date.fromisoformat(d).weekday()!=4: continue
        else:
            if mv.get(d,0) > thr: continue
        exp=nextFri(d)
        if not exp or exp>days[-1]: continue
        S=close[d]; K=round(S*0.99/2.5)*2.5
        rows.append({"d":d,"exp":exp,"S":S,"K":K,"v":rv[d]})
        for o in (0,-2.5,2.5,-5,5): need.add(occ(exp,K+o))
    plan[nm]=rows
print("entries per arm:",{k:len(v) for k,v in plan.items()})
todo=sorted(need-set(OB)); print("fetching",len(todo))
K_="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
for i in range(0,len(todo),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K_,"apikey":K_,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=400)); OB.update(r.get("bars") or {}); time.sleep(0.3)
json.dump(OB,open("nvda_opt.json","w"))
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def cbefore(d):
    best=None
    for x in days:
        if x<=d: best=x
        else: break
    return close[best]
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
FIN=close[days[-1]]
WEEKS=(datetime.date.fromisoformat(days[-1])-datetime.date.fromisoformat(days[22])).days/7
TOTAL=190*WEEKS                                   # identical delta deployed in every arm

def run(nm):
    rows=plan[nm]; per=TOTAL/len(rows)
    shares=paid=prem=0.0; bought=0.0; dw=0.0; skip=0; openp=[]; maxout=0.0
    ivs=[]; cts=0
    for r in rows:
        d=r["d"]
        for leg in list(openp):
            if leg["exp"]<=d:
                if cbefore(leg["exp"])<leg["K"]:
                    shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
                openp.remove(leg)
        K=m=None
        for o in (0,-2.5,2.5,-5,5):
            mm=mark.get((occ(r["exp"],r["K"]+o),d))
            if mm and mm>0: K,m=r["K"]+o,mm; break
        if K is None: skip+=1; continue
        dte=(datetime.date.fromisoformat(r["exp"])-datetime.date.fromisoformat(d)).days
        T=dte/365; dl=pdelta(r["S"],K,T,r["v"])
        ct=max(0,round(per/(dl*100)))
        if ct<=0: continue
        prem+=m*100*ct; dw+=dl*ct*100; cts+=ct
        ivs.append(m/(r["S"]*math.sqrt(max(T,1e-6))))     # premium per unit of sqrt-time, a rough richness proxy
        openp.append({"K":K,"ct":ct,"exp":r["exp"]})
        maxout=max(maxout,sum(l["K"]*100*l["ct"] for l in openp))
    for leg in openp:
        if cbefore(leg["exp"])<leg["K"]:
            shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
    return dict(n=len(rows),skip=skip,ct=cts,shares=shares,prem=prem,
                delivery=bought/dw if dw else 0, rich=statistics.mean(ivs) if ivs else 0,
                basis=(paid-prem)/bought if bought else 0, maxout=maxout, total=shares*FIN+prem-paid)

print("\nNVDA · 1%% OTM in every arm · %.0f total delta deployed in every arm"%TOTAL)
print("%-14s %6s %8s %9s %8s %9s %10s %11s"%("cadence","entries","shares","delivery","richness","basis","peak cash","TOTAL"))
print("-"*82)
res={}
for nm in ARMS:
    r=run(nm); res[nm]=r
    print("%-14s %6d %8.0f %8.0f%% %8.4f %9.2f %10.0f %11.0f"%(
        nm,r["n"],r["shares"],100*r["delivery"],r["rich"],r["basis"],r["maxout"],r["total"]))
base=res["every Friday"]
print()
for nm in ARMS:
    if nm=="every Friday": continue
    d=res[nm]
    print("%-14s vs Friday: shares %+6.0f · basis %+6.2f · richness %+.1f%% · TOTAL %+9.0f"%(
        nm,d["shares"]-base["shares"],d["basis"]-base["basis"],
        100*(d["rich"]/base["rich"]-1),d["total"]-base["total"]))
