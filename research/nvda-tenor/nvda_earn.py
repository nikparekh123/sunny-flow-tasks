# -*- coding: utf-8 -*-
"""Earnings week: play it, skip it, or halve it. ATM weekly, 190 delta/week."""
import json, math, datetime, statistics
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist(); OB=json.load(open("nvda_opt.json"))
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv]
EARN=['2024-08-28','2024-11-20','2025-02-26','2025-05-28','2025-08-27','2025-11-19','2026-02-25','2026-05-27']
def occ(exp,K): return "O:NVDA%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000)))
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
def cbefore(d):
    best=None
    for x in days:
        if x<=d: best=x
        else: break
    return close[best]
FIN=close[days[-1]]; WEEK=190

rolls=[]
for d in FRI:
    exp=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    if exp>days[-1]: continue
    S,v,T=close[d],rv[d],7/365
    d1=-N.inv_cdf(0.50); K=round(S*math.exp((R+v*v/2)*T-d1*v*math.sqrt(T))/2.5)*2.5
    spans=any(d < e <= exp for e in EARN)          # the print lands inside this contract's life
    rolls.append({"d":d,"exp":exp,"S":S,"v":v,"K":K,"earn":spans})
print("weekly rolls %d · of which span a print: %d\n"%(len(rolls),sum(r["earn"] for r in rolls)))

def run(policy):
    shares=paid=prem=0.0; bought=0.0; dw=0.0; skip=0
    ePnl=0.0; eCt=0; eAssigned=0; detail=[]
    for r in rolls:
        S,v,T=r["S"],r["v"],7/365
        K=m=None
        for o in (0,-2.5,2.5,-5,5):
            mm=mark.get((occ(r["exp"],r["K"]+o),r["d"]))
            if mm and mm>0: K,m=r["K"]+o,mm; break
        if K is None: skip+=1; continue
        dl=pdelta(S,K,T,v)
        size = 1.0 if not r["earn"] else (0.0 if policy=="skip" else 0.5 if policy=="half" else 1.0)
        ct=max(0,round(WEEK*size/(dl*100))) if dl>0 else 0
        if ct<=0: continue
        px=cbefore(r["exp"])
        prem+=m*100*ct; dw+=dl*ct*100
        assigned = px<K
        if assigned: shares+=ct*100; paid+=K*ct*100; bought+=ct*100
        if r["earn"]:
            contrib = m*100*ct + (ct*100*(FIN-K) if assigned else 0)
            ePnl+=contrib; eCt+=ct; eAssigned+= (ct if assigned else 0)
            detail.append((r["d"],K,ct,m,px,assigned,contrib))
    return dict(shares=shares,prem=prem,delivery=bought/dw if dw else 0,
                basis=(paid-prem)/bought if bought else 0,
                total=shares*FIN+prem-paid, ePnl=ePnl, eCt=eCt, eAssigned=eAssigned, detail=detail)

print("%-6s %9s %9s %9s %9s %11s"%("policy","shares","delivery","premium","basis","TOTAL"))
print("-"*62)
res={}
for p in ("play","half","skip"):
    r=run(p); res[p]=r
    print("%-6s %9.0f %8.0f%% %9.0f %9.2f %11.0f"%(p,r["shares"],100*r["delivery"],r["prem"],r["basis"],r["total"]))
print("\nplay minus skip: %+.0f   ·   play minus half: %+.0f"%(
    res["play"]["total"]-res["skip"]["total"], res["play"]["total"]-res["half"]["total"]))
print("\nTHE EIGHT EARNINGS ROLLS, PLAYED (contribution = premium kept + gain on any shares taken)")
print("   %-11s %7s %4s %7s %9s %9s %11s"%("written","strike","ct","prem","exp px","assigned","contribution"))
for d,K,ct,m,px,a,c in res["play"]["detail"]:
    print("   %-11s %7.1f %4d %7.2f %9.2f %9s %11.0f"%(d,K,ct,m,px,"yes" if a else "no",c))
print("   %-11s %7s %4d %7s %9s %9s %11.0f"%("TOTAL","",res["play"]["eCt"],"","","",res["play"]["ePnl"]))
