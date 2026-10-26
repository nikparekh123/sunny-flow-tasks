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

def sim(lo,hi,ladder,pD=5,cD=5,minDrop=0.0,pOff=0.0,MAXCT=10,STOP=25000,FIX=True,SCALE=None):
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
    sh=0; cost=0.0; inc=0.0; oP=[]; oC=[]; calls=0; LOG=[]; PEAK=[0.0]
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
            cap=MAXCT
            if SCALE:
                for lvl,n in SCALE:      # price band -> how many puts allowed open
                    if S>=lvl: cap=n; break
            ct=min(max(0,cap-openCt), room)
            if ct>0:
                K=snap(S*(1+pOff)); p,_=bs(S,K,T,v,True)
                inc+=p*100*ct; oP.append((j,K,ct))
                PEAK[0]=max(PEAK[0],sum(l[1]*100*l[2] for l in oP))
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
    return inc, sh, (cost/sh if sh else 0), calls, px(hi-1), LOG, px, PEAK[0]


import statistics as S2
NIK=[(200,12),(175,22),(150,32),(0,42)]
WIN=504
def run(lad,cD):
    I=[];T=[];SH=[]
    for s0 in range(70,N-WIN-40,25):
        inc,sh,bas,ca,fp,LOG,px,pk=sim(s0,s0+WIN,lad,1,cD,0.0,0.0,12,10**9,True,NIK)
        I.append(inc/2);T.append(inc+sh*(fp-bas));SH.append(sh)
    return S2.mean(I),S2.median(T),S2.median(SH)
m=lambda v:"$"+format(round(v/1e6,2),",")+"m"
print("Puts fixed at ATM, coming Friday. Only the CALL rules change.\n")
print("A. call expiry")
print("   %-32s %12s %12s %11s"%("","premium/yr","NET median","shares"))
for lab,cd in (("the coming Friday",1),("Friday >=5 days out (spec)",5),("Friday >=12 days out",12)):
    i,t,sh=run([(17,0.00),(17,0.02),(16,0.04)],cd)
    print("   %-32s %12s %12s %11s"%(lab,m(i),m(t),format(round(sh),",")))
print("\nB. call strikes, all on the coming Friday")
print("   %-32s %12s %12s %11s"%("","premium/yr","NET median","shares"))
for lab,lad in (("ladder +0 / +2 / +4% (spec)",[(17,0.00),(17,0.02),(16,0.04)]),
                ("all 50% at the anchor (ATM)",[(50,0.00)]),
                ("ladder +0 / +1 / +2%",[(17,0.00),(17,0.01),(16,0.02)]),
                ("ladder +0 / +3 / +6%",[(17,0.00),(17,0.03),(16,0.06)])):
    i,t,sh=run(lad,1)
    print("   %-32s %12s %12s %11s"%(lab,m(i),m(t),format(round(sh),",")))
