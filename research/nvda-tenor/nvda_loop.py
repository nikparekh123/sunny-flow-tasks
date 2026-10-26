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
def nxtFri(i):
    j=i+1
    while j<N and not (WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=5): j+=1
    return j if j<N else None
def bs(S,K,T,v,put):
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)

def sim(lo,hi,cOff,cover):
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    snap=lambda x: round(x/2.5)*2.5
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.20, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
    def red2(i):
        return i-lo>=2 and ret[i-1]<0 and ret[i-2]<0
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
        j=nxtFri(i)
        if not j or j>=hi: continue
        T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
        S=px(i); v=vol(i)
        if red2(i):
            openCt=sum(l[2] for l in oP)
            ct=max(0,MAXCT-openCt)
            if ct>0:
                K=snap(S); p,_=bs(S,K,T,v,True)
                inc+=p*100*ct; oP.append((j,K,ct))
        if grn2(i) and sh>0:
            basis=cost/sh
            K=snap(basis*(1+cOff))
            if K>0:
                c,_=bs(S,K,T,v,False)
                oc=sum(l[2] for l in oC)
                ct=min(int(sh*cover/100/100)-oc, max(0,(sh-oc*100)//100))
                if ct>0 and c>0: inc+=c*100*ct; oC.append((j,K,ct))
    return inc, sh, (cost/sh if sh else 0), calls, px(hi-1)

WIN=252; STEP=25
print("Sell up to 10 puts on two red days. Calls set off YOUR BASIS, on two green days.")
print("One year per run, %d runs, starting from no shares.\n"%len(range(70,N-WIN-40,STEP)))
print("%-26s %11s %11s %12s %12s"%("call strike / cover","income","shares kept","called away","total"))
print("-"*76)
for cOff,ol in ((0.00,"at basis"),(0.01,"basis +1%"),(0.03,"basis +3%"),(0.06,"basis +6%")):
    for cover in (50,100):
        I=[];S_=[];CA=[];TOT=[]
        for s in range(70,N-WIN-40,STEP):
            inc,sh,bas,ca,fp=sim(s,s+WIN,cOff,cover)
            I.append(inc);S_.append(sh);CA.append(ca);TOT.append(inc+sh*(fp-bas))
        print("%-26s %11s %11s %12s %12s"%("%s / %d%%"%(ol,cover),
            "$"+format(round(st.mean(I)),","), format(round(st.mean(S_)),","),
            format(round(st.mean(CA)),","), "$"+format(round(st.mean(TOT)),",")))
I=[];S_=[];TOT=[]
for s in range(70,N-WIN-40,STEP):
    inc,sh,bas,ca,fp=sim(s,s+WIN,0,0); I.append(inc);S_.append(sh);TOT.append(inc+sh*(fp-bas))
print("%-26s %11s %11s %12s %12s"%("no calls at all",
    "$"+format(round(st.mean(I)),","), format(round(st.mean(S_)),","), "0", "$"+format(round(st.mean(TOT)),",")))
