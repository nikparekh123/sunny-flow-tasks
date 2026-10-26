# -*- coding: utf-8 -*-
"""PART 2: wait-for-red versus write-on-cadence.

Tenor held constant across every arm (7 and 14 day, the Aug 21 / 28 shape), so the only
thing changing is WHEN you write. Priced on trailing realised vol, which gives the
red-day arms no IV bonus, so any edge they show is understated.

The column that decides it is `delivered`: actual assignments divided by the delta that
was sold. The whole planner assumes that ratio is 1.0. If waiting for red pushes it
below 1.0 then red days buy a cheaper strike but hand over fewer shares.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; TEN=[7,14]
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
D=sorted(tlt); IDX={x:i for i,x in enumerate(D)}
C=[tlt[x] for x in D]
lr=[math.log(C[i+1]/C[i]) for i in range(len(C)-1)]
def volAt(i):
    w=lr[max(0,i-63):i]
    return max(0.04, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.10
def leg(S,K,T,v):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return (K*math.exp(-R*T)*ND.cdf(-(a-v*math.sqrt(T)))-S*ND.cdf(-a), ND.cdf(-a))
def expiry(i,t):
    j=i
    while j<len(D)-1 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days<t: j+=1
    return j

def sim(trig, size, lo=70, hi=len(D)-40):
    prem=cost=dsold=0.0; sh=0; ev=0
    for i in range(lo,hi):
        u=trig(i)
        if not u: continue
        q=size(i); ev+=1
        for t in TEN:
            S=C[i]; K=round(S*2)/2; v=volAt(i); T=t/365
            px,dl=leg(S,K,T,v)
            ct=max(1,round((q/len(TEN))/(dl*100)))
            prem+=px*100*ct; dsold+=dl*100*ct
            j=expiry(i,t)
            if j<hi and C[j]<K: cost+=K*100*ct; sh+=100*ct
    yrs=(IDX[D[hi-1]]-IDX[D[lo]])/252
    tape=st.mean(C[lo:hi])
    return dict(ev=ev, prem=prem, sh=sh, dsold=dsold,
                deliv=sh/dsold if dsold else 0,
                basis=(cost-prem)/sh if sh else 0,
                vtape=((cost-prem)/sh - tape) if sh else 0,
                pace=sh/yrs/52, ppsh=prem/sh if sh else 0)

ret=lambda i: C[i]/C[i-1]-1
def tier(i):
    x=-ret(i)
    if x>=0.02: return 4000
    if x>=0.01: return 3000
    if x>=0.005: return 2000
    return 1000
ARMS=[("cadence: every Friday",        lambda i: datetime.date.fromisoformat(D[i]).weekday()==4, lambda i:1861),
      ("any red day, flat size",       lambda i: ret(i)<0,        lambda i:775),
      ("any red day, sized by drop",   lambda i: ret(i)<0,        tier),
      ("red day worse than -0.5%",     lambda i: ret(i)<-0.005,   lambda i:1400),
      ("red day worse than -1%",       lambda i: ret(i)<-0.01,    lambda i:3000),
      ("green days only (control)",    lambda i: ret(i)>0,        lambda i:775)]

print("PART 2  Same tenor, different trigger.  TLT 2003-2026.\n")
print("%-30s %6s %9s %9s %9s %9s %10s"%("arm","events","delivered","basis","vs tape","prem/shr","shr/week"))
print("-"*95)
res={}
for lab,t,s in ARMS:
    r=sim(t,s); res[lab]=r
    print("%-30s %6d %8.2f %9.2f %+9.2f %9.3f %10.0f"%(
        lab,r['ev'],r['deliv'],r['basis'],r['vtape'],r['ppsh'],r['pace']))
print("\n'delivered' 1.00 means you got exactly the shares delta predicted.")
print("'vs tape' negative means you accumulated below the average market price.")
