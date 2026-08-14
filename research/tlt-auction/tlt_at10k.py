# -*- coding: utf-8 -*-
"""At 10,000 TLT shares, what do the two sides actually look like?

Priced Black-Scholes on TLT's own realised vol, which is what the engines use when a
quote is missing. Put side follows the live rules: 846/wk base x the yield band, 1%
OTM weekly Fridays. Call side is hypothetical -- TLT is in ACCUMULATE and calls are
OFF there -- so this is what HOLD would look like.
"""
import json, csv, math, statistics as st
from statistics import NormalDist
N=NormalDist(); R=0.045
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
days=sorted(tlt)
lr=[math.log(tlt[days[i+1]]/tlt[days[i]]) for i in range(len(days)-1)]
def vol(n): 
    w=lr[-n:]; return st.stdev(w)*math.sqrt(252)
S=tlt[days[-1]]
v1, v3 = vol(252), vol(63)
print("TLT %.2f · realised vol 1y %.1f%% · 3m %.1f%%\n"%(S,100*v1,100*v3))
def bs(S,K,T,v,cp):
    if T<=0 or v<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    if cp=="C": return S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2)
    return K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1)
def dlt(S,K,T,v,cp):
    if T<=0 or v<=0: return 1.0 if (S>K if cp=="C" else S<K) else 0.0
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return N.cdf(d1) if cp=="C" else N.cdf(-d1)

SHARES=10000
print("=== PUT SIDE — the accumulation, 1%% OTM weekly Fridays ===")
K=round(S*0.99/2)*2/2 if False else round(S*0.99*2)/2
T=7/365; px=bs(S,K,T,v1,"P"); d=dlt(S,K,T,v1,"P")
print("  strike %.1f · %.0f%% delta · %.2f premium"%(K,100*d,px))
print("  %-26s %8s %10s %12s %14s"%("band","delta/wk","contracts","premium/wk","premium/yr"))
for lab,f in (("50bp+ above mean",2.50),("25-50bp above",1.75),("0-25bp above",1.25),
              ("0-25bp below",0.75),("well below",0.25)):
    wk=846*f; ct=round(wk/(d*100)); prem=ct*px*100
    print("  %-26s %8.0f %10d %12s %14s"%(lab,wk,ct,"$%s"%format(int(prem),","),"$%s"%format(int(prem*52),",")))

print("\n=== CALL SIDE — hypothetical, %d shares = %d contracts of cover ==="%(SHARES,SHARES//100))
print("  %-14s %-9s %8s %9s %11s %13s"%("tenor","strike","delta","cover","contracts","premium"))
for Tl,tl in ((7/365,"weekly"),(30/365,"monthly")):
    for otm in (0.00,0.02,0.04):
        Kc=round(S*(1+otm)*2)/2
        pxc=bs(S,Kc,Tl,v1,"C"); dc=dlt(S,Kc,Tl,v1,"C")
        for cov in (0.25,0.50,1.00):
            ct=int(SHARES*cov//100)
            print("  %-14s %-9s %7.0f%% %8.0f%% %11d %13s"%(tl,"%.1f%s"%(Kc," ATM" if otm==0 else ""),100*dc,100*cov,ct,"$%s"%format(int(ct*pxc*100),",")))
    print()
