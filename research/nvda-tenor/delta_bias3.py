# -*- coding: utf-8 -*-
"""Can the bias actually be FORECAST, or does it only look predictable in hindsight?

Raw delta is risk-neutral: P(ITM) with the drift set to r. The candidate fix swaps in a
TRAILING drift estimate, which is knowable at write time:

    P(put lands) = N( -[ln(S/K) + (mu - sigma^2/2)T] / (sigma sqrt(T)) )

Everything is computed from data available BEFORE the write. Scored by how far each
forecast sits from what actually happened, so a fix has to earn its place.
Shrinkage lambda blends the trailing drift toward zero: 0 is pure delta-style, 1 is
full trust in the trailing number.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045
def load(p):
    b=json.load(open(p))["bars"]; return [x["d"] for x in b],[x["c"] for x in b]

def test(name, D, C, T=14, off=-0.01, look=252):
    N=len(D); lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
    def nxt(i,t):
        j=i
        while j<N-1 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days<t: j+=1
        return j
    res={}
    LAM=[0.0,0.25,0.5,0.75,1.0]
    for lam in LAM: res[lam]=[]
    raw=[]
    for i in range(look+70, N-40):
        w=lr[i-63:i]; v=max(0.10, st.pstdev(w)*math.sqrt(252))
        mu=252*st.mean(lr[i-look:i])                  # trailing drift, known at write time
        j=nxt(i,T)
        if j>=N-1: break
        S=C[i]; K=S*(1+off); t=T/365; sq=v*math.sqrt(t)
        hit = 1.0 if C[j]<K else 0.0
        d1=(math.log(S/K)+(R+v*v/2)*t)/sq
        raw.append((ND.cdf(-d1), hit))
        for lam in LAM:
            m=lam*mu + (1-lam)*R
            d2s=(math.log(S/K)+(m-v*v/2)*t)/sq
            res[lam].append((ND.cdf(-d2s), hit))
    def score(rows):
        br=st.mean([(p-h)**2 for p,h in rows])        # Brier: lower is a better forecast
        bias=st.mean([h for _,h in rows])/st.mean([p for p,_ in rows])
        return br,bias
    br,bi=score(raw)
    print("\n%s  put, %dd, %s"%(name,T,"1% OTM"))
    print("  %-34s %10s %10s"%("forecast","Brier","actual/pred"))
    print("  %-34s %10.4f %10.3f"%("raw delta (what ships today)",br,bi))
    for lam in LAM:
        b2,i2=score(res[lam])
        tag="real-world P, shrink %.2f"%lam
        print("  %-34s %10.4f %10.3f%s"%(tag,b2,i2," <- best" if b2==min(score(res[l])[0] for l in LAM) else ""))

nd,nc=load("nvda_long.json"); test("NVDA",nd,nc)
test("NVDA",nd,nc,T=7)
td,tc=load("../tlt-auction/tlt.json"); test("TLT",td,tc)
