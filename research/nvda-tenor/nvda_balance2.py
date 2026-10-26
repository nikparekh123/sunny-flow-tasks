# -*- coding: utf-8 -*-
"""Where is the balance: fewer calls, or calls further out?

Coverage barely moved the outcome because an ATM call assigns about half the time,
so the damage is set by the STRIKE. This sweeps strike distance against coverage and
reports both things Nik cares about at once: shares at the end, and income.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; START=225.0; SH0=1000; TARGET=27500; WKS=104; CEIL=400000
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
def nxt(i,minD):
    j=i+1
    while j<N:
        if WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=minD: return j
        j+=1
    return None
def bs(S,K,T,v,put):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); sq=v*math.sqrt(T)
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)
def sim(lo,hi,cover,coff):
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.15, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
    def streak(i,up):
        n=0
        while n<i-lo and ((ret[i-n-1]>0) if up else (ret[i-n-1]<0)): n+=1
        return n
    sh=SH0; prem=0.0; openP=[]; openC=[]; ca=0
    for i in range(lo,hi):
        for L in list(openP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100
                openP.remove(L)
        for L in list(openC):
            if L[0]<=i:
                if px(L[0])>L[1]: sh-=L[2]*100; ca+=L[2]*100
                openC.remove(L)
        wkLeft=max(1,WKS-(i-lo)/5); S=px(i); v=vol(i)
        if streak(i,False)>=2:
            j=nxt(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                K=S*0.99; p,dl=bs(S,K,T,v,True)
                ct=int(max(0.0,(TARGET-sh)/wkLeft)/(dl*100)) if dl>0 else 0
                out=sum(l[1]*100*l[2] for l in openP)
                ct=min(ct,int(max(0,CEIL-out)/(K*100)))
                if ct>0: prem+=p*100*ct; openP.append((j,K,ct))
        if cover>0 and streak(i,True)>=2:
            j=nxt(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                K=S*(1+coff); p,dl=bs(S,K,T,v,False)
                openCt=sum(l[2] for l in openC)
                ct=min(int(sh*(cover/100.0)/100.0)-openCt, max(0,(sh-openCt*100)//100))
                if ct>0: prem+=p*100*ct; openC.append((j,K,ct))
    return sh,prem,px(hi-1)/START-1,ca
WIN=520; STEP=25
COV=[15,25,40]; OFF=[(0.0,"ATM"),(0.03,"+3%"),(0.06,"+6%"),(0.10,"+10%")]
print("Start 1,000, target 27,500 in 104wk.  Cell = END SHARES / premium.\n")
print("%-12s"%"cover" + "".join("%24s"%l for _,l in OFF))
print("-"*110)
G={}
for cov in COV:
    row=""
    for off,lab in OFF:
        E=[];PR=[];DR=[]
        for s in range(70,N-WIN-40,STEP):
            sh,pr,dr,_=sim(s,s+WIN,cov,off); E.append(sh);PR.append(pr);DR.append(dr)
        G[(cov,lab)]=(E,PR,DR)
        row+="%13s /%9s"%(format(round(st.mean(E)),","),"$"+format(round(st.mean(PR)/1000),",")+"k")
    print("%-12s%s"%("%d%%"%cov,row))
E,PR,DR=[],[],[]
for s in range(70,N-WIN-40,STEP):
    sh,pr,dr,_=sim(s,s+WIN,0,0); E.append(sh);PR.append(pr);DR.append(dr)
G[(0,"none")]=(E,PR,DR)
print("%-12s%13s /%9s   (no calls at all)"%("0%",format(round(st.mean(E)),","),"$"+format(round(st.mean(PR)/1000),",")+"k"))
print("\nYOUR BEARISH CASE only (windows where NVDA fell or was flat)")
print("%-12s"%"cover" + "".join("%24s"%l for _,l in OFF))
print("-"*110)
for cov in COV:
    row=""
    for off,lab in OFF:
        E,PR,DR=G[(cov,lab)]
        d=[(e,p) for e,p,x in zip(E,PR,DR) if x<0.5]
        row+="%13s /%9s"%(format(round(st.mean([q[0] for q in d])),","),"$"+format(round(st.mean([q[1] for q in d])/1000),",")+"k")
    print("%-12s%s"%("%d%%"%cov,row))
E,PR,DR=G[(0,"none")]
d=[(e,p) for e,p,x in zip(E,PR,DR) if x<0.5]
print("%-12s%13s /%9s   (no calls at all)"%("0%",format(round(st.mean([q[0] for q in d])),","),"$"+format(round(st.mean([q[1] for q in d])/1000),",")+"k"))
