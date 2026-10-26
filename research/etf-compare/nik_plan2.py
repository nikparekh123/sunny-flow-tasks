# -*- coding: utf-8 -*-
"""Nik's plan on SPY, QQQ, IWM vs TLT (8 Oct 2026). Same structure as nik_plan.py:
shares + 2x LEAPs (Jan-2029 ~ATM) + 3 call lines (ATM ~3.5d, 1% OTM 6d, 1% OTM 8d),
results as % of money in, so a $775 SPY and a $77 TLT compare fairly.
Weekly ATM implied from the 7 Oct Oct-16 closes; realised = IBKR 30-day (8 Oct);
'bad year' = the 1-in-20 down year at each ticker's own 5-year volatility."""
import math,random,statistics as st,json
from statistics import NormalDist
ND=NormalDist().cdf; Z5=NormalDist().inv_cdf(0.05)
R=0.037; MR=0.0303; DAYS=252; TL=834/365
def bs(S,K,T,v,q):
    if T<=0: return max(0,S-K)
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-q+v*v/2)*T)/sq
    return S*math.exp(-q*T)*ND(d1)-K*math.exp(-R*T)*ND(d1-sq)
def solve(p,S,K,T,q):
    lo,hi=0.01,3
    for _ in range(80):
        m=(lo+hi)/2
        if bs(S,K,T,m,q)<p: lo=m
        else: hi=m
    return m
def vol5(t):
    c=[x["c"] for x in json.load(open(f"{t}_hist.json"))["bars"]]
    lr=[math.log(c[i+1]/c[i]) for i in range(len(c)-1)]; return st.pstdev(lr)*math.sqrt(252)
TK={ # S (7 Oct close), q, weekly ATM (K, px, days), IBKR 30d HV, LEAP (K, px)
 "TLT":dict(S=76.92, q=0.0504,atm=(77,0.575,7),hv=0.115,leap=(75,7.92)),
 "SPY":dict(S=777.22,q=0.0098,atm=(777,5.88,9),hv=0.102,leap=(775,126.52)),
 "QQQ":dict(S=757.73,q=0.0041,atm=(758,7.88,9),hv=0.152,leap=(760,142.31)),
 "IWM":dict(S=277.70,q=0.0098,atm=(278,3.15,9),hv=0.146,leap=(275,49.32)),
}
for t,x in TK.items():
    K,p,d=x["atm"]; x["iv"]=solve(p,x["S"],K,d/365,x["q"])
    x["liv"]=solve(x["leap"][1],x["S"],x["leap"][0],TL,x["q"]); x["v5"]=vol5(t)
LINES=[(0,3.5/365,0.00,3),(1,6/365,0.01,4),(2,8/365,0.01,6)]
def run(x,dr,vol,fade,rng,N=1000):
    S0=x["S"]; mu=math.log(1+dr)/DAYS; s=vol/math.sqrt(DAYS); P=[S0]
    for _ in range(DAYS): P.append(P[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
    adj=(S0*(1+dr)/P[-1])**(1/DAYS); P=[v*adj**i for i,v in enumerate(P)]
    K,lp=x["leap"]; cost=N*S0+2*N*lp
    base=N*(P[-1]-S0)+N*S0*x["q"]+2*N*(bs(P[-1],K,TL-1,x["liv"],x["q"])-lp)-cost*MR
    calls=0.0
    for off,T,otm,td in LINES:
        t=off
        while t+td<=DAYS:
            iv=(vol+0.005+(x["iv"]-vol-0.005)*math.exp(-t/40)) if fade else x["iv"]
            k=P[t]*(1+otm)
            calls+=N*(bs(P[t],k,T,iv,x["q"])-0.01)-N/100*0.65-N*max(0,P[t+td]-k)
            t+=td
    return base/cost, calls/cost
print("TODAY  (weekly ATM implied vs IBKR 30-day actual, 5-yr vol, LEAP time value % of price)")
for t,x in TK.items():
    K,lp=x["leap"]; tv=(lp-max(0,x["S"]-K))/x["S"]
    print(f"  {t}: priced {x['iv']*100:4.1f}% vs moving {x['hv']*100:4.1f}%  (ratio {x['iv']/x['hv']:.2f})  5-yr vol {x['v5']*100:4.1f}%  LEAP time value {tv*100:4.1f}%  dividend {x['q']*100:.1f}%")
for fade in (False,True):
    print(f"\nNEXT 12 MONTHS, % of money in (calls part in brackets); option prices {'drift back to normal' if fade else 'stay as today'}")
    for t,x in TK.items():
        bad=math.exp(Z5*x["v5"])-1
        sc=[("Flat",0.0),("Up 15%",0.15),("Down 15%",-0.15),(f"Bad year {bad*100:+.0f}%",bad)]
        cells=[]
        for nm,dr in sc:
            rng=random.Random(11); r=[run(x,dr,x["hv"],fade,rng) for _ in range(600)]
            cells.append(f"{nm} {st.median(a+c for a,c in r)*100:+4.0f}% ({st.median(c for _,c in r)*100:+3.0f}%)")
        print(f"  {t}: "+"   ".join(cells))
