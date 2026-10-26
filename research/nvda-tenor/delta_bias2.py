# -*- coding: utf-8 -*-
"""Is the bias STABLE enough to hard-code, or does it have to be estimated live?

A fixed calibration table is only safe if the ratio holds still. NVDA drifted +44%/yr
over this sample and will not do that forever, so the question is whether the ratio
tracks the drift of the moment (estimable) or wanders (not fixable this way).
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; T=14
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; C=[x["c"] for x in b]; N=len(D)
lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
def vol(i):
    w=lr[max(0,i-63):i]
    return max(0.10, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
def nxt(i,t):
    j=i
    while j<N-1 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days<t: j+=1
    return j
def ratios(lo,hi):
    pd=pa=cd=ca=0.0
    for i in range(lo,hi):
        S=C[i]; v=vol(i); j=nxt(i,T)
        if j>=hi: break
        a=(math.log(1/0.99)+(R+v*v/2)*(T/365))/(v*math.sqrt(T/365))
        dp=ND.cdf(-a)
        a2=(math.log(1/0.99)+(R+v*v/2)*(T/365))/(v*math.sqrt(T/365))
        dc=ND.cdf(a2)
        pd+=dp; cd+=dc
        if C[j]<S*0.99: pa+=1
        if C[j]>S*1.01: ca+=1
    return (pa/pd if pd else 0), (ca/cd if cd else 0)

print("NVDA, 14-day, 1%% out.  Ratio of actual assignments to what delta promised.\n")
print("%-14s %9s %11s %11s"%("period","drift/yr","PUT ratio","CALL ratio"))
print("-"*50)
yrs={}
for i,dd in enumerate(D[:-1]): yrs.setdefault(dd[:4],[]).append(i)
for y in sorted(yrs):
    idx=yrs[y]
    lo,hi=max(70,idx[0]),min(idx[-1],N-40)
    if hi-lo<100: continue
    dr=252*st.mean(lr[lo:hi])
    p,c=ratios(lo,hi)
    print("%-14s %+8.0f%% %11.3f %11.3f"%(y,100*dr,p,c))

print("\nCorrelation between the year's drift and that year's ratios")
rows=[]
for y in sorted(yrs):
    idx=yrs[y]; lo,hi=max(70,idx[0]),min(idx[-1],N-40)
    if hi-lo<100: continue
    rows.append((252*st.mean(lr[lo:hi]),)+ratios(lo,hi))
dr=[r[0] for r in rows]; pp=[r[1] for r in rows]; cc=[r[2] for r in rows]
def corr(a,b):
    ma,mb=st.mean(a),st.mean(b)
    return sum((x-ma)*(y-mb) for x,y in zip(a,b))/math.sqrt(sum((x-ma)**2 for x in a)*sum((y-mb)**2 for y in b))
print("  drift vs PUT ratio  r = %+.2f"%corr(dr,pp))
print("  drift vs CALL ratio r = %+.2f"%corr(dr,cc))
print("\nspread: PUT %.2f to %.2f,  CALL %.2f to %.2f"%(min(pp),max(pp),min(cc),max(cc)))
