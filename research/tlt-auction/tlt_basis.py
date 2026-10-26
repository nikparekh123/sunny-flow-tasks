# -*- coding: utf-8 -*-
"""Does the longer tenor's better basis survive a falling market?

The live-chain table assumes you keep writing at the money. But a 35-day put fixes
your strike for 35 days, while weekly puts re-strike downward every Friday as TLT
falls. This runs each tenor continuously over TLT's whole history, sized to the same
delta pace, and measures the basis ACTUALLY realised against the average market price
over the same stretch. Negative means you bought below the average tape.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; WK=1861
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
days=sorted(tlt); IDX={d:i for i,d in enumerate(days)}
lr=[math.log(tlt[days[i+1]]/tlt[days[i]]) for i in range(len(days)-1)]
def volAt(d):
    i=IDX[d]; w=lr[max(0,i-63):i]
    return max(0.04, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.10
def leg(S,K,T,v):
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return (K*math.exp(-R*T)*ND.cdf(-(d1-v*math.sqrt(T)))-S*ND.cdf(-d1), ND.cdf(-d1))

def run(tenor, lo, hi):
    """Write an ATM put every `tenor` calendar days, sized to the weekly delta pace."""
    prem=0.0; cost=0.0; sh=0; i=lo; mk=[]
    while i<hi:
        d=days[i]; S=tlt[d]; K=round(S*2)/2; v=volAt(d); T=tenor/365
        px,dl=leg(S,K,T,v); ct=max(1,round((WK*tenor/7.0)/(dl*100)))
        prem+=px*100*ct
        j=i
        while j<len(days)-1 and (datetime.date.fromisoformat(days[j])-datetime.date.fromisoformat(d)).days<tenor: j+=1
        if j>=hi: break
        if tlt[days[j]]<K: cost+=K*100*ct; sh+=100*ct
        mk+= [tlt[x] for x in days[i:j]]
        i=j
    if sh==0: return None
    return (cost-prem)/sh - (sum(mk)/len(mk))     # basis minus average tape

FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4]
print("Basis realised MINUS the average TLT price over the same stretch.")
print("Negative is good, it means you accumulated below the tape.\n")
print("%-12s %14s %14s %14s"%("tenor","all history","rising 12wks","falling 12wks"))
segs=[]
for s in range(70,len(FRI)-13):
    a,b=IDX[FRI[s]],IDX[FRI[s+12]]
    segs.append((a,b,tlt[FRI[s+12]]>tlt[FRI[s]]))
for tenor,lab in ((7,"7d weekly"),(14,"14d"),(21,"21d"),(35,"35d")):
    allr=[];up=[];dn=[]
    for a,b,rise in segs:
        r=run(tenor,a,b)
        if r is None: continue
        allr.append(r); (up if rise else dn).append(r)
    print("%-12s %14.3f %14.3f %14.3f"%(lab,st.mean(allr),st.mean(up),st.mean(dn)))
