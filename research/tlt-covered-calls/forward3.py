# -*- coding: utf-8 -*-
"""Forward 12 months: weekly ATM puts (tranches) vs owning shares.

Puts priced off the live Oct 14 put smile (7 Oct closes), option prices fading to
realised + 0.5pt over ~2 months (as forward2.py). Three Mon/Wed/Fri lines,
+10 contracts a week to 150. Margin 3.03%, dividend 5.04%.
"""
import math,random,statistics as st
from statistics import NormalDist
ND=NormalDist().cdf
S0=76.92; R=0.037; Q=0.0504; MR=0.0303; DAYS=252
def bsp(S,K,T,v):
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-Q+v*v/2)*T)/sq
    return K*math.exp(-R*T)*ND(-(d1-sq))-S*math.exp(-Q*T)*ND(-d1)
def solve(px,K,T=7/365):
    lo,hi=0.005,1.5
    for _ in range(80):
        m=(lo+hi)/2
        if bsp(S0,K,T,m)<px: lo=m
        else: hi=m
    return m
W={75:0.10,75.5:0.16,76:0.24,76.5:0.39,77:0.60}
SM=sorted((K/S0-1,solve(p,K)) for K,p in W.items()); ATM=solve(0.60,77)
def smile(m):
    if m<=SM[0][0]: return SM[0][1]-ATM
    for (a,va),(b,vb) in zip(SM,SM[1:]):
        if m<=b: return va+(vb-va)*(m-a)/(b-a)-ATM
    return SM[-1][1]-ATM
SCEN=[("Calm, flat",0.00,0.10),("Choppy, flat",0.00,0.16),("Fed eases +15%",0.15,0.13),
      ("QE +30%",0.30,0.18),("Inflation -15%",-0.15,0.15)]
def path(dr,vol,rng):
    mu=math.log(1+dr)/DAYS; s=vol/math.sqrt(DAYS); S=[S0]
    for _ in range(DAYS): S.append(S[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
    adj=(S0*(1+dr)/S[-1])**(1/DAYS); return [x*adj**i for i,x in enumerate(S)]
def run(S,vol,mode):
    cash=0.0; sh=0; open_={}
    if mode=="block": sh=15000; cash=-15000*S0
    for t in range(DAYS+1):
        if t:
            if cash<0: cash-= -cash*MR/252
            cash+=sh*S[t-1]*Q/252
        if mode=="weekly" and t%5==0 and sh<15000: n=min(1000,15000-sh); cash-=n*S[t]; sh+=n
        if mode in ("all","ramp","keep"):
            for ln,o in list(open_.items()):
                if o["e"]==t:
                    if S[t]<o["K"]:
                        n=o["n"]*100
                        if mode=="keep": cash-=n*o["K"]; sh+=n
                        else: cash-=n*(o["K"]-S[t])
                    del open_[ln]
            for ln in (0,2,4):
                if t%5!=ln or t+5>DAYS: continue
                tgt=150 if mode=="all" else min(150,10*(t//5+1))
                others=sum(o["n"] for l,o in open_.items() if l!=ln)
                n=max(0,min(50,math.ceil(tgt/3),tgt-others-(sh//100 if mode=="keep" else 0)))
                if not n: continue
                K=round(S[t]*2)/2
                if K>S[t]+0.25: K-=0.5
                iv=max(0.03,vol+0.005+(ATM-vol-0.005)*math.exp(-t/40)+smile(K/S[t]-1))
                cash+=n*100*(bsp(S[t],K,7/365,iv)-0.01)-n*0.65
                open_[ln]={"e":t+5,"K":K,"n":n}
    liab=sum(o["n"]*100*max(0,o["K"]-S[-1]) for o in open_.values())
    return cash+sh*S[-1]-liab
MODES=[("15,000 shares at once","block"),("Shares, 1,000 a week","weekly"),("Puts only, 150 at once","all"),
       ("Puts only, +10 a week","ramp"),("Puts, keep shares, +10 a week","keep")]
print(f"put IV today: ATM {ATM*100:.1f}%  "+" ".join(f"{K}:{v*100:.1f}" for (m,v),K in zip(SM,sorted(W))))
print(f"{'':32}"+"".join(f"{s[0]:>24}" for s in SCEN))
res={m:[] for _,m in MODES}
for k,(nm,dr,vol) in enumerate(SCEN):
    rng=random.Random(21+k); P=[path(dr,vol,rng) for _ in range(1500)]
    for _,m in MODES:
        v=sorted(run(S,vol,m) for S in P); res[m].append((st.median(v),v[150]))
for nm,m in MODES:
    print(f"{nm:32}"+"".join(f"{a:>+12,.0f} ({lo:>+9,.0f})" for a,lo in res[m]))
