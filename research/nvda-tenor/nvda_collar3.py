# -*- coding: utf-8 -*-
"""Two fixes and one new test.

FIX: the floor was valued with 47 days left when the run had already reached its
expiry. Calendar days are now tracked properly, so the floor is worth its intrinsic
value at the end and nothing more.

TEST: tie the put count to the BLOCK, the way the calls already are, instead of
writing a fixed 25 every week regardless.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.04; START=224.75; FLOORK=200.0; FLOOR_COST=10.625; LIFE=154
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
def bs(S,K,T,v,put):
    if T<=0: return max(0.0,(K-S) if put else (S-K))
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    c=S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq)
    return c-S+K*math.exp(-R*T) if put else c

def run(lo,ct,tied):
    d0=datetime.date.fromisoformat(D[lo])
    hi=lo
    while hi<N-1 and (datetime.date.fromisoformat(D[hi])-d0).days<LIFE: hi+=1
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
    prem=0.0; cost=sh*START; oC=[]; oP=[]; weeks=0; peakSh=sh
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
        peakSh=max(peakSh,sh)
        if WD[i]!=4: continue
        j=fri(i)
        if not j or j>=hi: continue
        S=px(i); T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365; v=vol(i)
        weeks+=1
        cK=round(S/2.5)*2.5
        n=min(ct, max(0, sh//100 - sum(l[2] for l in oC)))
        if n>0: prem+=bs(S,cK,T,v,False)*100*n; oC.append((j,cK,n))
        pK=round(S*0.99/2.5)*2.5
        # TIED: never let the puts take the block past its starting size.
        cap = max(0, ct - sh//100) if tied else ct
        m=max(0, min(ct, cap) - sum(l[2] for l in oP))
        if m>0: prem+=bs(S,pK,T,v,True)*100*m; oP.append((j,pK,m))
    end=px(hi-1)
    fv=max(0.0, FLOORK-end)*100*ct          # at expiry: intrinsic only
    return prem, sh, peakSh, floorCost, fv, weeks

print("25 contracts, held the full 154 days to the January expiry. %d runs.\n"%len(range(70,N-130,15)))
print("%-26s %11s %11s %11s %12s %13s"%("put sizing","premium","per expiry","end shares","peak shares","floor at end"))
print("-"*88)
for tied,lab in ((False,"fixed 25 a week (before)"),(True,"tied to the block (new)")):
    PR=[];SH=[];PK=[];FV=[];WK=[]
    for s0 in range(70,N-130,15):
        pr,sh,pk,fc,fv,wk=run(s0,25,tied)
        PR.append(pr);SH.append(sh);PK.append(pk);FV.append(fv);WK.append(wk)
    m=lambda X: st.mean(X)
    print("%-26s %11s %11s %11s %12s %13s"%(lab,
        "$"+format(round(m(PR)),","), "$"+format(round(m(PR)/m(WK)),","),
        format(round(m(SH)),","), format(round(m(PK)),","),
        "$"+format(round(m(FV)),",")))
print()
print("  %d expiries in the 154 days, one a week."%round(m(WK)))
print("  floor cost was $26,562 up front, and at expiry it is worth only its intrinsic:")
print("  zero unless NVDA finished under 200.")
