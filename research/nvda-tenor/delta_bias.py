# -*- coding: utf-8 -*-
"""How wrong is delta as a forecast of shares, and is it wrong in a stable way?

The planner treats delta as expected shares on BOTH legs and nets them. Delta is
risk-neutral: it assumes the underlying drifts at the risk-free rate. Anything that
actually drifts faster will assign its puts LESS often than delta says and its calls
MORE often. That is a directional bias, not noise, so if it is stable it is fixable
with a calibration factor.

Measured as (actual assignment rate) / (delta at the time of writing). 1.00 means delta
was right. Below 1 means fewer assignments than promised.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045

def load(path, key=None):
    d=json.load(open(path)); b=d["bars"]
    return [x["d"] for x in b], [x["c"] for x in b]

def study(name, D, C):
    N=len(D); WD=[datetime.date.fromisoformat(x).weekday() for x in D]
    lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.04, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.3
    def legs(S,K,T,v):
        a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
        return ND.cdf(-a), ND.cdf(a)          # put delta abs, call delta
    def nxt(i,t):
        j=i
        while j<N-1 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days<t: j+=1
        return j
    drift=252*st.mean(lr)
    print("\n%s  %s to %s  drift %+.1f%%/yr  vol %.0f%%"%(name,D[0],D[-1],100*drift,100*st.pstdev(lr)*math.sqrt(252)))
    print("  %-8s %-9s %14s %14s"%("tenor","moneyness","PUT actual/delta","CALL actual/delta"))
    for t in (7,14,21,35):
        for off,lab in ((-0.03,"3% OTM"),(-0.01,"1% OTM"),(0.0,"ATM"),(0.01,"1% ITM")):
            pd=pa=cd=ca=0.0
            for i in range(70,N-40,1):
                S=C[i]; v=vol(i); j=nxt(i,t)
                if j>=N-1: break
                Kp=S*(1+off); Kc=S*(1-off)     # mirror the offset for calls
                dp,_=legs(S,Kp,t/365,v); _,dc=legs(S,Kc,t/365,v)
                pd+=dp; cd+=dc
                if C[j]<Kp: pa+=1
                if C[j]>Kc: ca+=1
            print("  %-8s %-9s %14.3f %14.3f"%("%dd"%t,lab,pa/pd if pd else 0, ca/cd if cd else 0))

nd,nc = load("nvda_long.json")
study("NVDA", nd, nc)
td,tc = load("../tlt-auction/tlt.json")
study("TLT", td, tc)
