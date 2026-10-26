# -*- coding: utf-8 -*-
"""Nik's loop on real NVDA data. Vary the call strike (set off BASIS) and the coverage."""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
START=220.0
def nxtFri(i,minD=5):
    j=i+1
    while j<N and not (WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=minD): j+=1
    return j if j<N else None
def bs(S,K,T,v,put):
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)

def sim(lo,hi,ladder,pD=5,cD=5,minDrop=0.0,pOff=0.0,MAXCT=10,STOP=25000,FIX=True):
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
    sh=0; cost=0.0; inc=0.0; oP=[]; oC=[]; calls=0; LOG=[]
    for i in range(lo,hi):
        for L in list(oP):
            if L[0]<=i:
                if px(L[0])<L[1]:
                    sh+=L[2]*100; cost+=L[1]*L[2]*100
                    LOG.append((D[i],'PUT ASSIGNED','bought %d sh at %.2f'%(L[2]*100,L[1]),sh,inc))
                else: LOG.append((D[i],'put expired','kept premium, no shares',sh,inc))
                oP.remove(L)
        for L in list(oC):
            if L[0]<=i:
                if px(L[0])>L[1]:
                    basis=cost/sh if sh else 0
                    sh-=L[2]*100; cost-=basis*L[2]*100; calls+=L[2]*100
                    LOG.append((D[i],'CALL ASSIGNED','sold %d sh at %.2f'%(L[2]*100,L[1]),sh,inc))
                oC.remove(L)
        S=px(i); v=vol(i)
        jp=nxtFri(i,pD); jc=nxtFri(i,cD)
        if red2(i) and jp and jp<hi:
            j=jp; T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
            openCt=sum(l[2] for l in oP)
            # STOP: never write puts that could take you past the target. Without this
            # the run just keeps buying all the way down and ends with 100,000 shares.
            room=max(0,(STOP-sh)//100 - openCt)
            ct=min(max(0,MAXCT-openCt), room)
            if ct>0:
                K=snap(S*(1+pOff)); p,_=bs(S,K,T,v,True)
                inc+=p*100*ct; oP.append((j,K,ct))
                LOG.append((D[i],'sell %d puts'%ct,'strike %.2f, %.2f prem, $%s in, exp %s'%(K,p,format(round(p*100*ct),','),D[j]),sh,inc))
        if grn2(i) and sh>0 and jc and jc<hi:
            j=jc; T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
            basis=cost/sh
            anchor=max(basis,S) if FIX else basis
            for frac,off in ladder:
                K=snap(anchor*(1+off))
                if K<=0: continue
                c,_=bs(S,K,T,v,False)
                # each rung is topped up to its own share of the block, independently
                oc=sum(l[2] for l in oC if abs(l[3]-off)<1e-9)
                tot=sum(l[2] for l in oC)
                ct=min(int(sh*frac/100/100)-oc, max(0,(sh-tot*100)//100))
                if ct>0 and c>0:
                    inc+=c*100*ct; oC.append((j,K,ct,off))
                    LOG.append((D[i],'sell %d calls'%ct,'strike %.2f (basis+%d%%), %.2f prem, $%s in'%(K,round(off*100),c,format(round(c*100*ct),',')),sh,inc))
    return inc, sh, (cost/sh if sh else 0), calls, px(hi-1), LOG, px


import statistics as S2
LAD=[(17,0.00),(17,0.02),(16,0.04)]
WIN=504
print("Calls anchored to the HIGHER of spot and basis, vs anchored to basis only.")
print("Two years, max 30 puts, stop at 25,000 shares. 62 runs.\n")
print("%-38s %11s %12s %13s %12s"%("call anchor","med shares","called away","gross prem","NET median"))
print("-"*90)
for fix,lab in ((False,"basis only (what I recommended)"),(True,"higher of spot and basis (fixed)")):
    SH=[];CA=[];I=[];T=[]
    for s0 in range(70,N-WIN-40,25):
        inc,sh,bas,ca,fp,LOG,px=sim(s0,s0+WIN,LAD,5,5,0.0,0.015,30,25000,fix)
        SH.append(sh);CA.append(ca);I.append(inc);T.append(inc+sh*(fp-bas))
    print("%-38s %11s %12s %13s %12s"%(lab, format(round(S2.median(SH)),","),
        format(round(S2.mean(CA)),","), "$"+format(round(S2.mean(I)/1e6,2),",")+"m",
        "$"+format(round(S2.median(T)/1e6,2),",")+"m"))
print()
inc,sh,bas,ca,fp,LOG,px=sim(N-300,N-40,LAD,5,5,0.0,0.015,30,25000,True)
print("Same window as the trace above, with the fix:")
print("  shares held        %s      (was 8,700)"%format(sh,","))
print("  called away        %s      (was 33,300)"%format(ca,","))
print("  premium            $%s   (was $999,126)"%format(round(inc),","))
print("  NET                $%s   (was $1,019,983)"%format(round(inc+sh*(fp-bas)),","))
