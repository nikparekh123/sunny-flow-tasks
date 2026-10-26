# -*- coding: utf-8 -*-
"""Forward 12 months, $1.15M in each, weekly Friday ATM calls on every 100 shares.
Calls priced at each ticker's live 7 Oct ATM vol, fading to realised + 0.5pt over
~2 months. Each ticker moves with its own realised vol (60-day). Margin 3.03%.
URA's dividend is lumpy year-end capital gains: 3% assumed (2023-25 average)."""
import math,random,statistics as st,json
from statistics import NormalDist
ND=NormalDist().cdf
R=0.037; MR=0.0303; CAP=1_150_000; DAYS=252
def bs(S,K,T,v,q):
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-q+v*v/2)*T)/sq
    return S*math.exp(-q*T)*ND(d1)-K*math.exp(-R*T)*ND(d1-sq)
def solve(p,S,K,T,q):
    lo,hi=0.01,3
    for _ in range(80):
        m=(lo+hi)/2
        if bs(S,K,T,m,q)<p: lo=m
        else: hi=m
    return m
T9=9/365; TL=834/365
TK={ # spot, q, live ATM call (strike, px, days), realised 60d, LEAP Jan-2029 ATM (K, px), deep (K,px)
 "TLT":dict(S=76.92,q=0.0504,atm=(77,0.575,7),rv=0.099,leap=(75,7.92),deep=(60,17.80)),
 "SLV":dict(S=53.82,q=0.0,  atm=(54,1.06,9), rv=0.380,leap=(55,13.30),deep=(30,28.47)),
 "URA":dict(S=39.93,q=0.03, atm=(40,1.02,9), rv=0.439,leap=(40,12.87),deep=(25,20.95)),
}
for t,x in TK.items():
    K,p,d=x["atm"]; x["iv"]=solve(p,x["S"],K,d/365,x["q"])
    for nm in ("leap","deep"):
        k,lp=x[nm]; x[nm+"_iv"]=solve(lp,x["S"],k,TL,x["q"])
SCEN=[("Flat",0.0),("Up 15%",0.15),("Up 30%",0.30),("Down 15%",-0.15),("Down 30%",-0.30)]
def path(S0,dr,vol,rng):
    mu=math.log(1+dr)/DAYS; s=vol/math.sqrt(DAYS); S=[S0]
    for _ in range(DAYS): S.append(S[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
    adj=(S0*(1+dr)/S[-1])**(1/DAYS); return [v*adj**i for i,v in enumerate(S)]
print("TODAY: weekly ATM premium, implied vs realised, LEAP time value")
for t,x in TK.items():
    K,p,d=x["atm"]; wk=bs(x["S"],x["S"],7/365,x["iv"],x["q"])/x["S"]
    lk,lp=x["leap"]; ext=lp-max(0,x["S"]-lk); dk,dp=x["deep"]; dext=dp-max(0,x["S"]-dk)
    print(f"  {t}: 7-day ATM {wk*100:.2f}% of price   implied {x['iv']*100:.1f}% vs realised {x['rv']*100:.1f}%   "
          f"carry {(x['q']-MR)*100:+.1f}%/yr   Jan-29 {lk}C time value {ext/x['S']*100:.0f}% of price, {dk}C {dext/x['S']*100:.0f}%")
print("\nNEXT 12 MONTHS on $1.15M (median): shares only -> shares + weekly ATM calls")
print(f"{'':6}"+"".join(f"{s[0]:>24}" for s in SCEN))
for t,x in TK.items():
    S0=x["S"]; N=int(CAP/S0/100)*100; rng=random.Random(3); row=[]; vol=x["rv"]
    for nm,dr in SCEN:
        a=[];b=[]
        for _ in range(1200):
            S=path(S0,dr,vol,rng); sh=N*(S[-1]-S0)+N*S0*(x["q"]-MR); c=0.0
            for t0 in range(0,DAYS-5,5):
                iv=vol+0.005+(x["iv"]-vol-0.005)*math.exp(-t0/40)
                c+=N*(bs(S[t0],S[t0],7/365,iv,x["q"])-max(0,S[t0+5]-S[t0]))-N/100*0.65-N*0.01
            a.append(sh);b.append(sh+c)
        row.append((st.median(a),st.median(b)))
    print(f"{t:6}"+"".join(f"{s/1000:>+10,.0f}k ->{c/1000:>+8,.0f}k" for s,c in row))
print("\nSHARES vs LEAPS, flat price for a year, per $1.15M of exposure")
for t,x in TK.items():
    S0=x["S"]; N=int(CAP/S0/100)*100
    for nm in ("leap","deep"):
        k,lp=x[nm]; p1=bs(S0,k,TL-1,x[nm+"_iv"],x["q"]); 
        print(f"  {t} Jan-29 {k}C: shares {N*S0*(x['q']-MR):+,.0f}   LEAPs {N*(p1-lp)-N*lp*MR:+,.0f}  (cost {N*lp:,.0f})")
