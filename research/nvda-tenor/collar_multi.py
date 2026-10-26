# -*- coding: utf-8 -*-
"""The 4-leg structure across tickers, and weekly versus every expiry.

  own TARGET shares, buy TARGET/100 long-dated puts ~11% out (the floor),
  then each write day sell an ATM call on the block and enough 1% OTM puts to
  REFILL toward the target. Not fixed (runs away) and not capped by holdings
  (ratchets down) -- refill toward target, which is the rule neither earlier
  test used.

Every price is modelled off that ticker's own trailing realised vol, so levels are
approximate but the COMPARISON between tickers is like for like.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.04; TARGET=2500; LIFE=154; FLOOR_OTM=0.89
def bs(S,K,T,v,put):
    if T<=0: return max(0.0,(K-S) if put else (S-K))
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    c=S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq)
    return c-S+K*math.exp(-R*T) if put else c

def load(t):
    b=json.load(open("%s_long.json"%t.lower()))["bars"]
    D=[x["d"] for x in b]; C=[x["c"] for x in b]
    return D, C, [C[i+1]/C[i]-1 for i in range(len(C)-1)]

def run(D,ret,lr,lo,START,everyExp):
    N=len(D); WD=[datetime.date.fromisoformat(x).weekday() for x in D]
    d0=datetime.date.fromisoformat(D[lo]); hi=lo
    while hi<N-1 and (datetime.date.fromisoformat(D[hi])-d0).days<LIFE: hi+=1
    if hi>=N-1: return None
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.12, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.35
    EXPD={0,2,4} if everyExp else {4}
    def nxt(i):
        c=[j for j in range(i+1,N) if WD[j] in EXPD]
        return c[2] if everyExp and len(c)>2 else (c[0] if c else None)
    fc = bs(START,START*FLOOR_OTM,LIFE/365,vol(lo),True)*100*(TARGET//100)
    sh=TARGET; cost=sh*START; prem=0.0; oC=[]; oP=[]; wr=0; peak=sh
    for i in range(lo,hi):
        for L in list(oC):
            if L[0]<=i:
                if px(L[0])>L[1]:
                    bas=cost/sh if sh else 0
                    prem+=(L[1]-bas)*L[2]*100; sh-=L[2]*100; cost-=bas*L[2]*100
                oC.remove(L)
        for L in list(oP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100; cost+=L[1]*L[2]*100
                oP.remove(L)
        peak=max(peak,sh)
        if WD[i] not in EXPD: continue
        j=nxt(i)
        if j is None or j>=hi: continue
        S=px(i); T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
        if T<=0: continue
        v=vol(i); wr+=1
        n=max(0, sh//100 - sum(l[2] for l in oC))
        if n>0: prem+=bs(S,S,T,v,False)*100*n; oC.append((j,S,n))
        # REFILL toward the target: what is missing, less what is already coming
        want=max(0,(TARGET-sh)//100 - sum(l[2] for l in oP))
        if want>0: prem+=bs(S,S*0.99,T,v,True)*100*want; oP.append((j,S*0.99,want))
    end=px(hi-1)
    return prem, sh, peak, fc, max(0.0,START*FLOOR_OTM-end)*100*(TARGET//100), wr, st.pstdev(lr[lo:hi])*math.sqrt(252)

print("2,500 shares. Floor = a 154-day put 11%% out. Calls ATM, puts 1%% out refilling")
print("toward 2,500. Every price modelled on that ticker's own trailing vol.\n")
print("%-6s %-14s %5s %11s %11s %12s %10s %11s"%("","cadence","vol","floor cost","premium","per expiry","pays for","end shares"))
print("-"*90)
for t,start in (("NVDA",224.75),("AVGO",416.05),("TSLA",327.51),("SPCX",146.15),("SPY",772.49)):
    D,C,ret=load(t); lr=[math.log(1+x) for x in ret]; N=len(D)
    for ev,lab in ((False,"weekly"),(True,"every expiry")):
        PR=[];FC=[];SH=[];WR=[];V=[]
        for s0 in range(70,N-130,20):
            r=run(D,ret,lr,s0,start,ev)
            if not r: continue
            pr,sh,pk,fc,fv,wr,v=r
            PR.append(pr);FC.append(fc);SH.append(sh);WR.append(wr);V.append(v)
        if not PR: continue
        m=lambda X: st.mean(X)
        print("%-6s %-14s %4.0f%% %11s %11s %12s %9.1fx %11s"%(
            t if lab=="weekly" else "", lab, 100*m(V),
            "$"+format(round(m(FC)),","), "$"+format(round(m(PR)),","),
            "$"+format(round(m(PR)/m(WR)),","), m(PR)/m(FC), format(round(m(SH)),",")))
    print()
