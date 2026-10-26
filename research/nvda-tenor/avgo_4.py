# -*- coding: utf-8 -*-
"""The wheel on AVGO vs NVDA. Same rules, same code, only the stock changes.

Puts at the money on the coming Friday, sized by band. Calls two green days, three
rungs at +0/+3/+6% off the higher of spot and basis, half the block, a week out.
Prices replayed from a 225 start so the two are directly comparable.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; START=225.0
def load(p):
    b=json.load(open(p))["bars"]; return [x["d"] for x in b],[x["c"] for x in b]
def bs(S,K,T,v,put):
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)
BANDS=[(200,15),(175,25),(150,35),(0,50)]
LAD=[(17,0.00),(17,0.03),(16,0.06)]

def sim(D,C,ret,lr,lo,hi,trigger):
    N=len(D); WD=[datetime.date.fromisoformat(x).weekday() for x in D]
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.15, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.40
    def fri(i,minD):
        j=i+1
        while j<N:
            if WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=minD: return j
            j+=1
        return None
    def run(i,up):
        n=0
        while n<i-lo and ((ret[i-n-1]>0) if up else (ret[i-n-1]<0)): n+=1
        return n
    sh=0; cost=0.0; inc=0.0; oP=[]; oC=[]; nw=[0,0]
    for i in range(lo,hi):
        for L in list(oP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100; cost+=L[1]*L[2]*100
                oP.remove(L)
        for L in list(oC):
            if L[0]<=i:
                if px(L[0])>L[1]:
                    b=cost/sh if sh else 0; sh-=L[2]*100; cost-=b*L[2]*100
                oC.remove(L)
        S=px(i); v=vol(i)
        fire = (WD[i]==4) if trigger=="friday" else (run(i,False)>=2)
        if fire:
            j=fri(i,1)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                cap=next(n for f,n in BANDS if S>=f)
                ct=max(0,cap-sum(l[2] for l in oP))
                if ct>0:
                    p,_=bs(S,S,T,v,True); inc+=p*100*ct; oP.append((j,S,ct)); nw[0]+=1; nw[1]+=ct
        if (run(i,True)>=2 or trigger=="friday" and WD[i]==4) and sh>0:
            j=fri(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                anc=max(S, cost/sh); oc=sum(l[2] for l in oC)
                tot=int(sh*0.5//100); base=tot//3; ex=tot%3
                for idx,(pct,off) in enumerate(LAD):
                    K=anc*(1+off)
                    want=base+(1 if idx<ex else 0)
                    ct=min(max(0,want-sum(l[2] for l in oC if abs(l[1]-K)<0.01)), max(0,sh//100-oc))
                    if ct<=0: continue
                    c,_=bs(S,K,T,v,False); inc+=c*100*ct; oc+=ct; oC.append((j,K,ct))
    return inc, sh, (cost/sh if sh else 0), px(hi-1), nw

WIN=504
print("Income is premium collected. NET also counts what the shares did.")
print("If writing every Friday buys shares at worse prices, NET is where it shows.\n")
for name,p in (("NVDA","nvda_long.json"),("AVGO","avgo_long.json")):
    D,C=load(p); ret=[C[i+1]/C[i]-1 for i in range(len(C)-1)]
    lr=[math.log(1+x) for x in ret]; N=len(D)
    print(name)
    for tg,lab in (("friday","every Friday"),("red2","two red days")):
        I=[];T=[];SH=[];B=[]
        for s0 in range(70,N-WIN-40,25):
            inc,sh,bas,fp,nw=sim(D,C,ret,lr,s0,s0+WIN,tg)
            I.append(inc/2);T.append(inc+sh*(fp-bas));SH.append(sh)
            if sh: B.append(100*(fp-bas)/bas)
        m=lambda v:"$"+format(round(v/1e6,2),",")+"m"
        print("   %-16s income %s/yr   NET median %s   worst %s   entry %+.1f%% vs end price"%(
            lab,m(st.mean(I)),m(st.median(T)),m(min(T)),st.mean(B)))
    print()
