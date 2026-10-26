# -*- coding: utf-8 -*-
"""How much capital you allow decides the tenor. That is the whole story.

Unconstrained, long tenor gives the better entry, which is what I told Nik earlier.
Under a binding ceiling, capital turnover decides it and short tenor wins, because a
14 day leg holds the cash twice as long and crowds out the next write.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
exec(open("tlt_combo2.py").read().split("RED2=lambda")[0].split('def sim')[0])
ND=NormalDist(); R=0.045; REF=82.0
def leg(S,K,T,v):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return (K*math.exp(-R*T)*ND.cdf(-(a-v*math.sqrt(T)))-S*ND.cdf(-a), ND.cdf(-a))
EXP={}
def expiry(i,t):
    if (i,t) in EXP: return EXP[(i,t)]
    j=i
    while j<N-1 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days<t: j+=1
    EXP[(i,t)]=j; return j
def streak(i):
    n=0
    while n<i and C[i-n]/C[i-n-1]-1<0: n+=1
    return n
LO,HI=70,N-40; WKS=(HI-LO)/252*52
def sim(tenors,koff,trig,ceil,want=1861):
    prem=cost=0.0; sh=0; out=[0.0]*N
    for i in range(LO,HI):
        if not trig(i): continue
        cap=ceil*C[i]/REF; room=cap-out[i]
        if room<=0: continue
        for t in tenors:
            S=C[i]; K=round((S+koff)*2)/2; v=volAt(i); T=t/365
            px,dl=leg(S,K,T,v)
            ct=min(max(0,round((want/len(tenors))/(dl*100))), int(room/(K*100)))
            if ct<=0: continue
            room-=K*100*ct; prem+=px*100*ct
            j=expiry(i,t)
            for k in range(i,min(j,N)): out[k]+=K*100*ct
            if j<HI and C[j]<K: cost+=K*100*ct; sh+=100*ct
    tape=st.mean(C[LO:HI])
    return (((cost-prem)/sh-tape) if sh else 0), (sh/WKS)
RED2=lambda i: streak(i)>=2
FRI =lambda i: datetime.date.fromisoformat(D[i]).weekday()==4

print("Trigger: second red day onward.  Strike 1.00 ITM (the 82 when TLT is 81.9).")
print("Each cell: entry vs tape / shares per week / weeks to 100,000.\n")
print("%-14s"%"ceiling" + "".join("%26s"%t for t,_ in [("7d (Aug 21)",0),("7+14 (Aug 21/28)",0),("7+14+21",0)]))
print("-"*92)
for ceil in (400000,600000,800000,1200000,2000000,10**9):
    lab="no limit" if ceil>=10**9 else "$"+format(ceil//1000,",")+"k"
    row=""
    for ts in ([7],[7,14],[7,14,21]):
        v,p=sim(ts,1.0,RED2,ceil)
        row+="%9.2f /%5.0f /%4.0f wk"%(v,p,100000/p if p else 999)
    print("%-14s%s"%(lab,row))

print("\n\nHead to head at YOUR $400k, best strike for each trigger and tenor")
print("%-38s %9s %8s %9s %14s"%("arm","vs tape","shr/wk","wks to 100k","vs Friday ATM"))
print("-"*84)
base,_=sim([7,14],0.0,FRI,400000)
for lab,ts,k,tg in [("Friday / 7+14 / ATM  (what I recommended)",[7,14],0.0,FRI),
                    ("Friday / 7d / ATM",[7],0.0,FRI),
                    ("Friday / 7d / 1.00 ITM",[7],1.0,FRI),
                    ("2nd red / 7+14 / 1.00 ITM",[7,14],1.0,RED2),
                    ("2nd red / 7d / 0.50 ITM",[7],0.5,RED2),
                    ("2nd red / 7d / 1.00 ITM",[7],1.0,RED2)]:
    v,p=sim(ts,k,tg,400000)
    print("%-38s %9.2f %8.0f %9.0f %14s"%(lab,v,p,100000/p if p else 999,
          "$"+format(round((base-v)*100000),",")))
