# -*- coding: utf-8 -*-
"""Forward test: the next 12 months are NOT assumed to repeat 2024-26.

Nik (7 Oct 2026): history covers QE and the 2022 hikes; today rate cuts are priced
in, the economy is softening, M2 could restart. So each scenario sets its own TLT
drift and realised vol, and every call is priced at TODAY's market (IV solved from
the live 7 Oct chain: Oct 14 77C 0.575 and 77.5C 0.355, spot 76.92).
15,000 shares on margin at 3.03%, 5.04% dividend, 150 calls in three staggered
weekly lines (Mon ATM, Wed/Fri one strike up). Rebuy at the same close.
"""
import math,random,statistics as st
from statistics import NormalDist
ND=NormalDist().cdf
S0=76.92; R=0.037; Q=0.0504; MR=0.0303; SH=15000; LINE=50; COST=50*(0.65+1.0)  # commission + 1c spread
def bs(S,K,T,v):
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-Q+v*v/2)*T)/sq
    return S*math.exp(-Q*T)*ND(d1)-K*math.exp(-R*T)*ND(d1-sq)
def solve(px,K,T=7/365):
    lo,hi=0.01,1
    for _ in range(80):
        m=(lo+hi)/2
        if bs(S0,K,T,m)<px: lo=m
        else: hi=m
    return m
IV_ATM=solve(0.575,77.0); IV_OTM=solve(0.355,77.5)
SCEN=[("Calm range (flat, quiet)",0.00,0.10),
      ("Choppy but flat",0.00,0.16),
      ("Fed eases, TLT +15%",0.15,0.13),
      ("Recession / QE, TLT +30%",0.30,0.18),
      ("Inflation returns, TLT -15%",-0.15,0.15)]
random.seed(7); N=2000; DAYS=252
def path(drift,vol):
    mu=math.log(1+drift)/DAYS; s=vol/math.sqrt(DAYS); S=[S0]
    for _ in range(DAYS): S.append(S[-1]*math.exp(mu-s*s/2+s*random.gauss(0,1)))
    # pin the year's end move to the scenario so the drift is what Nik picked, not luck
    adj=(S0*(1+drift)/S[-1])**(1/DAYS)
    return [x*adj**i for i,x in enumerate(S)]
import sys
FADE=len(sys.argv)>1      # option prices drift back to realised + 0.5pt over ~2 months
out=[]
for nm,dr,vol in SCEN:
    calls=[];hold=[]
    for _ in range(N):
        S=path(dr,vol); c=0.0
        for start in (0,2,4):            # Mon / Wed / Fri lines, 5-trading-day tenor
            otm= start!=0
            for t in range(start,DAYS-5,5):
                K=round(S[t]*2)/2
                if otm: K+=0.5
                elif K<S[t]-0.25: K+=0.5
                iv0=IV_OTM if otm else IV_ATM
                iv=(vol+0.005+(iv0-vol-0.005)*math.exp(-t/40)) if FADE else iv0
                p=bs(S[t],K,7/365,iv)
                c+=LINE*100*p-COST-LINE*100*max(0,S[t+5]-K)
        h=SH*(S[-1]-S0)+SH*S0*(Q-MR)
        calls.append(c);hold.append(h)
    calls.sort()
    out.append((nm,st.median(hold),st.median(calls),calls[N//10],calls[9*N//10]))
print(f"IV used: ATM {IV_ATM*100:.1f}%  one strike up {IV_OTM*100:.1f}%")
print(f"{'scenario':30} {'shares+div-margin':>18} {'calls add':>10} {'calls 10th..90th pct':>24} {'total':>10}")
for nm,h,c,lo,hi in out:
    print(f"{nm:30} {h:>+18,.0f} {c:>+10,.0f} {lo:>+11,.0f} .. {hi:>+9,.0f} {h+c:>+10,.0f}")
