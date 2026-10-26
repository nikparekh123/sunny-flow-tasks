# -*- coding: utf-8 -*-
"""Nik's loop on real NVDA data. Vary the call strike (set off BASIS) and the coverage."""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
START=220.0; MAXCT=10
def nxtFri(i,minD=5):
    j=i+1
    while j<N and not (WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=minD): j+=1
    return j if j<N else None
def bs(S,K,T,v,put):
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)

def sim(lo,hi,ladder,pD=5,cD=5,minDrop=0.0,pOff=0.0):
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    snap=lambda x: round(x/2.5)*2.5
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.20, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
    def red2(i):
        if i-lo<2 or ret[i-1]>=0 or ret[i-2]>=0: return False
        drop=(1+ret[i-1])*(1+ret[i-2])-1          # how far the two days fell together
        return -drop>=minDrop
    def grn2(i):
        return i-lo>=2 and ret[i-1]>0 and ret[i-2]>0
    sh=0; cost=0.0; inc=0.0; oP=[]; oC=[]; calls=0
    for i in range(lo,hi):
        for L in list(oP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100; cost+=L[1]*L[2]*100
                oP.remove(L)
        for L in list(oC):
            if L[0]<=i:
                if px(L[0])>L[1]:
                    basis=cost/sh if sh else 0
                    sh-=L[2]*100; cost-=basis*L[2]*100; calls+=L[2]*100
                oC.remove(L)
        S=px(i); v=vol(i)
        jp=nxtFri(i,pD); jc=nxtFri(i,cD)
        if red2(i) and jp and jp<hi:
            j=jp; T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
            openCt=sum(l[2] for l in oP)
            ct=max(0,MAXCT-openCt)
            if ct>0:
                K=snap(S*(1+pOff)); p,_=bs(S,K,T,v,True)
                inc+=p*100*ct; oP.append((j,K,ct))
        if grn2(i) and sh>0 and jc and jc<hi:
            j=jc; T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
            basis=cost/sh
            for frac,off in ladder:
                K=snap(basis*(1+off))
                if K<=0: continue
                c,_=bs(S,K,T,v,False)
                # each rung is topped up to its own share of the block, independently
                oc=sum(l[2] for l in oC if abs(l[3]-off)<1e-9)
                tot=sum(l[2] for l in oC)
                ct=min(int(sh*frac/100/100)-oc, max(0,(sh-tot*100)//100))
                if ct>0 and c>0: inc+=c*100*ct; oC.append((j,K,ct,off))
    return inc, sh, (cost/sh if sh else 0), calls, px(hi-1)


WIN=252; STEP=25
print("All rows cover the SAME 50% of the block. Only the spread differs.\n")
print("%-48s %11s %11s %11s"%("call structure (50% total coverage)","income","shares kept","total"))
print("-"*86)
ARMS=[("flat: all 50% at basis +0% (at basis)",[(50,0.00)]),
      ("flat: all 50% at basis +3%",           [(50,0.03)]),
      ("flat: all 50% at basis +6%",           [(50,0.06)]),
      ("ladder: 25 / 25 at +0 / +3%",          [(25,0.00),(25,0.03)]),
      ("ladder: 25 / 25 at +0 / +6%",          [(25,0.00),(25,0.06)]),
      ("ladder: 17 / 17 / 16 at +0 / +2 / +4%",[(17,0.00),(17,0.02),(16,0.04)]),
      ("ladder: 17 / 17 / 16 at +0 / +3 / +6%",[(17,0.00),(17,0.03),(16,0.06)]),
      ("ladder: 10 / 20 / 20 at +0 / +3 / +6%",[(10,0.00),(20,0.03),(20,0.06)])]
for lab,lad in ARMS:
    I=[];S_=[];TOT=[]
    for s0 in range(70,N-WIN-40,STEP):
        inc,sh,bas,ca,fp=sim(s0,s0+WIN,lad,5,5,0.0,0.015)
        I.append(inc);S_.append(sh);TOT.append(inc+sh*(fp-bas))
    print("%-48s %11s %11s %11s"%(lab,
        "$"+format(round(st.mean(I)),","), format(round(st.mean(S_)),","),
        "$"+format(round(st.mean(TOT)),",")))
