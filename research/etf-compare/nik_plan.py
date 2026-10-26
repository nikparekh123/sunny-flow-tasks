# -*- coding: utf-8 -*-
"""Nik's exact plan (8 Oct 2026), same on each ticker:
1,000 shares + 20 Jan-2029 ATM LEAPs. 30 calls in three lines, each rolled at
expiry: 10 ATM ~3.5 days, 10 1% OTM 6 days, 10 1% OTM 8 days. Assigned shares
are rebought (economically the same as paying the intrinsic). Margin 3.03% on
shares + LEAP cost. Results as % of the money put in, so a cheaper ticker is
not penalised. Realised vol = IBKR's 30-day historical (8 Oct) unless stated.
Calls priced at today's measured ATM implied, fading to realised+0.5pt (FADE)
or held (HOLD)."""
import math,random,statistics as st,sys
from statistics import NormalDist
ND=NormalDist().cdf
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
TK={"TLT":dict(S=76.92,q=0.0504,iv=0.147,hv=0.115,hv2=0.099,leap=(75,7.92)),
    "SLV":dict(S=53.82,q=0.0,  iv=0.333,hv=0.391,hv2=0.380,leap=(55,13.30)),
    "URA":dict(S=39.93,q=0.0522,iv=0.420,hv=0.361,hv2=0.439,leap=(40,12.87))}
for x in TK.values(): x["liv"]=solve(x["leap"][1],x["S"],x["leap"][0],TL,x["q"])
LINES=[(0,3.5/365,0.00,3),(1,6/365,0.01,4),(2,8/365,0.01,6)]   # (offset, tenor, otm, trading days)
def run(x,dr,vol,fade,rng):
    S0=x["S"]; mu=math.log(1+dr)/DAYS; s=vol/math.sqrt(DAYS); P=[S0]
    for _ in range(DAYS): P.append(P[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
    adj=(S0*(1+dr)/P[-1])**(1/DAYS); P=[v*adj**i for i,v in enumerate(P)]
    K,lp=x["leap"]; cost=1000*S0+2000*lp
    shares=1000*(P[-1]-S0)+1000*S0*x["q"]
    leaps=2000*(bs(P[-1],K,TL-1,x["liv"],x["q"])-lp)
    calls=0.0
    for off,T,otm,td in LINES:
        t=off
        while t+td<=DAYS:
            iv=(vol+0.005+(x["iv"]-vol-0.005)*math.exp(-t/40)) if fade else x["iv"]
            k=P[t]*(1+otm)
            calls+=1000*(bs(P[t],k,T,iv,x["q"])-0.01)-10*0.65-1000*max(0,P[t+td]-k)
            t+=td
    return shares,leaps,calls,-cost*MR,cost
SC=[("Flat",0.0),("Up 15%",0.15),("Up 30%",0.30),("Down 15%",-0.15),("Down 30%",-0.30)]
for fade in (True,False):
  for hvkey,label in (("hv","IBKR 30-day"),("hv2","60-day")):
    print(f"\n=== realised vol = {label}; option prices {'drift back to normal' if fade else 'stay at today'} ===")
    for t,x in TK.items():
        vol=x[hvkey]; out=[]
        for nm,dr in SC:
            rng=random.Random(7); r=[run(x,dr,vol,fade,rng) for _ in range(800)]
            cost=r[0][4]
            out.append((st.median(a+b+c+d for a,b,c,d,_ in r)/cost, st.median(c for _,_,c,_,_ in r)/cost))
        print(f"  {t} (IV {x['iv']*100:.0f} vs {vol*100:.0f}, money in ${cost:,.0f}): "+"  ".join(f"{nm} {a*100:+.0f}% (calls {c*100:+.0f}%)" for (nm,_),(a,c) in zip(SC,out)))
print("\nGross call premium a year at today's prices, % of money in:")
for t,x in TK.items():
    K,lp=x["leap"]; cost=1000*x["S"]+2000*lp; g=0
    for off,T,otm,td in LINES: g+=1000*bs(x["S"],x["S"]*(1+otm),T,x["iv"],x["q"])*(DAYS/td)
    print(f"  {t}: ${g:,.0f} = {g/cost*100:.0f}%   LEAP time value {2000*(lp-max(0,x['S']-K)):,.0f} over 2.3 yrs")
