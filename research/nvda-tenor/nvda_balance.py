# -*- coding: utf-8 -*-
"""Accumulate to 25-30K while running an ATM call income overlay. How much coverage fits?

Nik: 1,000 shares now, 25,000-30,000 in two years, bearish, wants income too.

Real NVDA daily RETURNS are replayed from a start price of 225 rather than using the
raw 2018 prices, because 27,500 shares means $137k at 2018's split-adjusted $5 and
$6.2m at today's $225. Returns transfer across the sample; price levels do not.

  puts  : second red day onward, 1% OTM, Friday >=5 days, sized by the chase
  calls : second green day onward, AT THE MONEY, Friday >=5 days, capped at coverage
  cash  : $400,000 ceiling on put commitments
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; START=225.0; SH0=1000; TARGET=27500; WKS=104; CEIL=400000
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]
lr=[math.log(1+x) for x in ret]
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

def sim(lo, hi, cover):
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i: P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.15, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
    def streak(i,up):
        n=0
        while n<i-lo and ((ret[i-n-1]>0) if up else (ret[i-n-1]<0)): n+=1
        return n
    sh=SH0; prem=0.0; openP=[]; openC=[]; called=0; assigned=0
    for i in range(lo,hi):
        for L in list(openP):                       # settle puts
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100; assigned+=L[2]*100
                openP.remove(L)
        for L in list(openC):                       # settle calls
            if L[0]<=i:
                if px(L[0])>L[1]: sh-=L[2]*100; called+=L[2]*100
                openC.remove(L)
        wkLeft=max(1,WKS-(i-lo)/5)
        S=px(i); v=vol(i)
        if streak(i,False)>=2:                      # PUT: second red day
            j=nxt(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                K=S*0.99; p,dl=bs(S,K,T,v,True)
                need=max(0.0,(TARGET-sh)/wkLeft)
                ct=int(need/(dl*100)) if dl>0 else 0
                out=sum(l[1]*100*l[2] for l in openP)
                ct=min(ct, int(max(0,CEIL-out)/(K*100)))
                if ct>0: prem+=p*100*ct; openP.append((j,K,ct))
        if cover>0 and streak(i,True)>=2:           # CALL: second green day, ATM
            j=nxt(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                K=S; p,dl=bs(S,K,T,v,False)
                openCt=sum(l[2] for l in openC)
                # coverage is a share percentage; a contract is 100 shares. Missing the
                # /100 wrote 100 contracts against a 1,000 share block and drove the
                # position negative.
                ct=int(sh*(cover/100.0)/100.0)-openCt
                ct=min(ct, max(0,(sh-openCt*100)//100))     # never write naked
                if ct>0: prem+=p*100*ct; openC.append((j,K,ct))
    return sh, prem, px(hi-1)/START-1, called, assigned

STEP=25; WIN=520                                    # 104 weeks of trading days
print("Start 1,000 shares, target 27,500 in 104 weeks, $400k put ceiling, NVDA at 225.\n")
print("%-14s %11s %11s %13s %11s %10s"%("call cover","end shares","hit target","premium","called away","assigned"))
print("-"*76)
runs={}
for cover in (0,10,15,25,35,50):
    E=[];PR=[];HIT=0;CA=[];AS=[];DR=[]
    for s in range(70,N-WIN-40,STEP):
        sh,pr,dr,ca,asg = sim(s,s+WIN,cover)
        E.append(sh);PR.append(pr);CA.append(ca);AS.append(asg);DR.append(dr)
        if sh>=25000: HIT+=1
    runs[cover]=(E,PR,DR)
    print("%-14s %11s %10.0f%% %13s %11s %10s"%(
        "%d%%"%cover, format(round(st.mean(E)),","), 100*HIT/len(E),
        "$"+format(round(st.mean(PR)),","), format(round(st.mean(CA)),","), format(round(st.mean(AS)),",")))

print("\nSplit by what NVDA actually did over the two years (your bearish case is the left column)")
print("%-14s %24s %24s"%("call cover","NVDA FELL or flat","NVDA ROSE"))
print("%-14s %11s %12s %11s %12s"%("","end shares","premium","end shares","premium"))
print("-"*64)
for cover in (0,10,15,25,35,50):
    E,PR,DR=runs[cover]
    dn=[(e,p) for e,p,d in zip(E,PR,DR) if d<0.5]; up=[(e,p) for e,p,d in zip(E,PR,DR) if d>=0.5]
    f=lambda X,k: format(round(st.mean([x[k] for x in X])),",") if X else "n/a"
    print("%-14s %11s %12s %11s %12s"%("%d%%"%cover, f(dn,0),"$"+f(dn,1), f(up,0),"$"+f(up,1)))
