# -*- coding: utf-8 -*-
"""Same grid, but the ceiling is enforced instead of assumed.

The previous run sized every arm to hit 1,861 shares a week and then reported what that
cost. It cost $3m of peak commitment, because "second red day onward" fires on every day
of a streak, so a five day slide stacks four writes on top of each other.

Here the ceiling is a hard cap that scales with the price level (TLT averaged about 100
across the history against 82 today, so a flat dollar cap would be far tighter in 2020
than it is now). You write what fits and skip what does not. Pace becomes an OUTPUT.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; CEIL=400000.0; REF=82.0
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
D=sorted(tlt); C=[tlt[x] for x in D]; N=len(D)
lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
def volAt(i):
    w=lr[max(0,i-63):i]
    return max(0.04, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.10
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

def sim(tenors,koff,trig,want=1861):
    prem=cost=0.0; sh=0; ev=0; skip=0; out=[0.0]*N
    for i in range(LO,HI):
        if not trig(i): continue
        ev+=1; cap=CEIL*C[i]/REF                      # ceiling scaled to the price level
        room=cap-out[i]
        if room<=0: skip+=1; continue
        wrote=False
        for t in tenors:
            S=C[i]; K=round((S+koff)*2)/2; v=volAt(i); T=t/365
            px,dl=leg(S,K,T,v)
            ct=max(0,round((want/len(tenors))/(dl*100)))
            ct=min(ct, int(room/(K*100)))              # only what fits
            if ct<=0: continue
            wrote=True; room-=K*100*ct
            prem+=px*100*ct
            j=expiry(i,t)
            for k in range(i,min(j,N)): out[k]+=K*100*ct
            if j<HI and C[j]<K: cost+=K*100*ct; sh+=100*ct
        if not wrote: skip+=1
    tape=st.mean(C[LO:HI])
    return dict(ev=ev,skip=skip,vtape=((cost-prem)/sh-tape) if sh else 0,
                pace=sh/WKS, cash=st.mean(out[LO:HI])*REF/tape,
                util=st.mean(out[LO:HI])/(CEIL*tape/REF))

RED2=lambda i: streak(i)>=2
FRI =lambda i: datetime.date.fromisoformat(D[i]).weekday()==4
TEN=[("7d only",[7]),("14d only",[14]),("7+14 (Aug 21/28)",[7,14]),("7+14+21",[7,14,21])]
KOF=[(-1.0,"1.00 OTM"),(-0.5,"0.50 OTM"),(0.0,"at the money"),(0.5,"0.50 ITM"),(1.0,"1.00 ITM")]

for tlab,trig in (("SECOND RED DAY ONWARD",RED2),("EVERY FRIDAY (today's rule)",FRI)):
    print("\n%s   entry vs tape / shares per week, under a hard $400k ceiling"%tlab)
    print("%-20s"%"" + "".join("%17s"%l for _,l in KOF))
    print("-"*105)
    for tl,ts in TEN:
        row=""
        for k,kl in KOF:
            r=sim(ts,k,trig); row+="%10.2f /%5.0f"%(r['vtape'],r['pace'])
        print("%-20s%s"%(tl,row))

print("\n\nShortlist, ceiling enforced\n")
print("%-40s %9s %8s %8s %9s %7s"%("arm","vs tape","shr/wk","fired","skipped","ceil use"))
print("-"*88)
for lab,ts,k,tg in [("2nd red / 7+14 / 1.00 OTM",[7,14],-1.0,RED2),
                    ("2nd red / 7+14 / 0.50 OTM",[7,14],-0.5,RED2),
                    ("2nd red / 7+14 / at the money",[7,14],0.0,RED2),
                    ("2nd red / 7+14 / 0.50 ITM",[7,14],0.5,RED2),
                    ("2nd red / 7d  / 1.00 OTM",[7],-1.0,RED2),
                    ("Friday / 7+14 / at the money",[7,14],0.0,FRI),
                    ("Friday / 7+14 / 1.00 OTM",[7,14],-1.0,FRI)]:
    r=sim(ts,k,tg)
    print("%-40s %9.2f %8.0f %8d %9d %6.0f%%"%(lab,r['vtape'],r['pace'],r['ev'],r['skip'],100*r['util']))
