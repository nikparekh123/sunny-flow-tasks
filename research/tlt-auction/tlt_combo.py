# -*- coding: utf-8 -*-
"""The three decisions together: trigger, strike, tenor.

Trigger fixed at the winner from part 3, the second red day of a streak onward.
Then sweep strike moneyness against tenor set. koff > 0 means the strike sits ABOVE
spot, i.e. in the money, which is what Nik means by "write the 82 rather than the 81.5
so it actually exercises".

Cash is tracked day by day as legs overlap, not estimated, because the ceiling is what
ruled out the deeper variants last time.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045
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

LO,HI=70,N-40
TARGET_WK=1861
def sim(tenors,koff,trig=lambda i:streak(i)>=2):
    prem=cost=dsold=0.0; sh=0; ev=0; ct_ev=[]
    out=[0.0]*N                                     # cash committed, day by day
    for i in range(LO,HI):
        if not trig(i): continue
        ev+=1; per=TARGET_WK*(0.0)  # placeholder, real size set after pace calibration
    # first pass to count events, then size so the arm hits the weekly pace
    yrs=(HI-LO)/252; wks=yrs*52
    per_ev=TARGET_WK*wks/ev if ev else 0            # delta per event to hit pace
    prem=cost=dsold=0.0; sh=0; ct_ev=[]
    for i in range(LO,HI):
        if not trig(i): continue
        for t in tenors:
            S=C[i]; K=round((S+koff)*2)/2; v=volAt(i); T=t/365
            px,dl=leg(S,K,T,v)
            ct=max(1,round((per_ev/len(tenors))/(dl*100)))
            prem+=px*100*ct; dsold+=dl*100*ct; ct_ev.append(ct)
            j=expiry(i,t)
            for k in range(i,min(j,N)): out[k]+=K*100*ct
            if j<HI and C[j]<K: cost+=K*100*ct; sh+=100*ct
    tape=st.mean(C[LO:HI])
    return dict(ev=ev, deliv=sh/dsold if dsold else 0, basis=(cost-prem)/sh if sh else 0,
                vtape=((cost-prem)/sh-tape) if sh else 0, ppsh=prem/sh if sh else 0,
                pace=sh/wks, cash=st.mean(out[LO:HI]), peak=max(out[LO:HI]),
                ct=st.mean(ct_ev))

TEN=[("7d only",[7]),("14d only",[14]),("7+14  (Aug 21/28)",[7,14]),("7+14+21",[7,14,21])]
KOF=[(-1.0,"1.00 OTM"),(-0.5,"0.50 OTM"),(0.0,"at the money"),(0.5,"0.50 ITM"),(1.0,"1.00 ITM")]

print("Trigger: second red day of a streak onward.  All arms sized to 1,861 shares/wk.")
print("Cell = basis versus the average tape.  More negative is a cheaper entry.\n")
print("%-20s"%"tenor" + "".join("%13s"%l for _,l in KOF))
print("-"*85)
G={}
for tl,ts in TEN:
    row=""
    for k,kl in KOF:
        r=sim(ts,k); G[(tl,kl)]=r; row+="%13.2f"%r['vtape']
    print("%-20s%s"%(tl,row))

print("\nDetail on the shortlist\n")
print("%-34s %7s %8s %9s %9s %11s %11s"%("arm","deliv","prem/sh","pace","contracts","avg cash","peak cash"))
print("-"*95)
for tl,kl in [("7+14  (Aug 21/28)","at the money"),("7+14  (Aug 21/28)","0.50 ITM"),
              ("7+14  (Aug 21/28)","1.00 ITM"),("14d only","0.50 ITM"),
              ("7d only","at the money"),("7+14+21","0.50 ITM")]:
    r=G[(tl,kl)]
    print("%-34s %7.2f %8.3f %9.0f %9.0f %11s %11s"%(tl+" / "+kl,r['deliv'],r['ppsh'],
        r['pace'],r['ct'],"$"+format(round(r['cash']),","),"$"+format(round(r['peak']),",")))
