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

def sim(lo,hi,cOff,cover,pD=5,cD=5,minDrop=0.0):
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
                K=snap(S); p,_=bs(S,K,T,v,True)
                inc+=p*100*ct; oP.append((j,K,ct))
        if grn2(i) and sh>0 and jc and jc<hi:
            j=jc; T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
            basis=cost/sh
            K=snap(basis*(1+cOff))
            if K>0:
                c,_=bs(S,K,T,v,False)
                oc=sum(l[2] for l in oC)
                ct=min(int(sh*cover/100/100)-oc, max(0,(sh-oc*100)//100))
                if ct>0 and c>0: inc+=c*100*ct; oC.append((j,K,ct))
    return inc, sh, (cost/sh if sh else 0), calls, px(hi-1)


WIN=252; STEP=25
print("Puts 1 week, calls 1 week at basis +3%, 50% cover. How far must it fall first?\n")
print("%-24s %8s %11s %11s %12s %11s"%("trigger","fires/yr","income","shares kept","avg basis","total"))
print("-"*82)
for md,lab in ((0.00,"any two red days"),(0.01,"two days, -1% or more"),
               (0.02,"two days, -2% or more"),(0.03,"two days, -3% or more"),
               (0.04,"two days, -4% or more"),(0.06,"two days, -6% or more")):
    I=[];S_=[];TOT=[];B=[];EV=[]
    for s0 in range(70,N-WIN-40,STEP):
        inc,sh,bas,ca,fp=sim(s0,s0+WIN,0.03,50,5,5,md)
        I.append(inc);S_.append(sh);TOT.append(inc+sh*(fp-bas))
        if sh: B.append(100*(fp-bas)/bas)
        # count firings
        P=[220.0]
        for k in range(1,WIN+1): P.append(P[-1]*(1+ret[s0+k-1]))
        n=0
        for i in range(s0+2,s0+WIN):
            if ret[i-1]<0 and ret[i-2]<0 and -((1+ret[i-1])*(1+ret[i-2])-1)>=md: n+=1
        EV.append(n)
    print("%-24s %8.0f %11s %11s %11.1f%% %11s"%(lab,st.mean(EV),
        "$"+format(round(st.mean(I)),","), format(round(st.mean(S_)),","),
        st.mean(B) if B else 0, "$"+format(round(st.mean(TOT)),",")))
