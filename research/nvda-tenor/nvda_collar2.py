# -*- coding: utf-8 -*-
"""Nik's 4-leg idea at real size: does the wheel still fund the floor over 154 days?

  own N shares, buy N/100 Jan-200 puts once, then every week sell an ATM call on
  whatever block survives and a 1% OTM put.

The payback ratio scales linearly, so 25 and 50 contracts pay the floor off in the
same 21 days. What does NOT scale is the BLOCK: at-the-money calls on 100% of it get
assigned about half the time, so the thing writing the premium shrinks week by week.
That is what this measures.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.04; START=224.75; FLOORK=200.0; FLOOR_COST=10.625
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
def bs(S,K,T,v,put):
    if T<=0: return max(0.0,(K-S) if put else (S-K))
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    c=S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq)
    return c-S+K*math.exp(-R*T) if put else c

def run(lo,hi,ct):
    sh=ct*100
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.15, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.40
    def fri(i):
        j=i+1
        while j<N and not (WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=5): j+=1
        return j if j<N else None
    floorCost=FLOOR_COST*100*ct
    prem=0.0; cost=sh*START; oC=[]; oP=[]; called=0; putto=0
    for i in range(lo,hi):
        for L in list(oC):
            if L[0]<=i:
                if px(L[0])>L[1]:
                    bas=cost/sh if sh else 0
                    prem+=(L[1]-bas)*L[2]*100; sh-=L[2]*100; cost-=bas*L[2]*100; called+=L[2]*100
                oC.remove(L)
        for L in list(oP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100; cost+=L[1]*L[2]*100; putto+=L[2]*100
                oP.remove(L)
        if WD[i]!=4: continue
        j=fri(i)
        if not j or j>=hi: continue
        S=px(i); T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365; v=vol(i)
        cK=round(S/2.5)*2.5
        n=min(ct, max(0, sh//100 - sum(l[2] for l in oC)))
        if n>0: prem+=bs(S,cK,T,v,False)*100*n; oC.append((j,cK,n))
        pK=round(S*0.99/2.5)*2.5
        m=max(0, ct - sum(l[2] for l in oP))
        if m>0: prem+=bs(S,pK,T,v,True)*100*m; oP.append((j,pK,m))
    end=px(hi-1)
    fv=bs(end,FLOORK,max(1,(154-(hi-lo)))/365,vol(hi-1),True)*100*ct
    return prem, sh, (cost/sh if sh else 0), end, floorCost, fv, called

WIN=107   # ~154 calendar days
print("Your 4 legs held for the life of the January put. NVDA started at 224.75.")
print("%d runs of ~154 days each, real NVDA returns.\n"%len(range(70,N-WIN-40,15)))
print("%-6s %10s %11s %10s %12s %12s %11s"%("ct","capital","floor cost","premium","end shares","floor worth","net"))
print("-"*80)
for ct in (1,25,50):
    CAP=[];FC=[];PR=[];SH=[];FV=[];NET=[]
    for s0 in range(70,N-WIN-40,15):
        pr,sh,bas,end,fc,fv,ca=run(s0,s0+WIN,ct)
        CAP.append(ct*100*START+fc); FC.append(fc); PR.append(pr); SH.append(sh); FV.append(fv)
        NET.append(pr - fc + fv + (sh*(end-bas) if sh else 0))
    m=lambda X: st.mean(X)
    print("%-6d %10s %11s %10s %12s %12s %11s"%(ct,
        "$"+format(round(m(CAP)/1000),",")+"k", "$"+format(round(m(FC))," ,".replace(" ","")),
        "$"+format(round(m(PR)),","), format(round(m(SH)),","),
        "$"+format(round(m(FV)),","), "$"+format(round(m(NET)),",")))
print()
print("  premium includes the gain booked when calls are assigned.")
print("  net = premium - what the floor cost + what the floor is still worth + the block's move.")
