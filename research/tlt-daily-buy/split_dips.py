# -*- coding: utf-8 -*-
"""Block vs daily vs split vs buying only on down days (Nik, 7 Oct 2026).

Every method ends with 15,000 shares and is judged on the same day, 252 trading
days after the start. A dip method that has not finished by day 251 buys the rest
that day, so nobody gets credit for simply owning less. History: every start since
Apr 2007, real closes and dividends, margin 3.03%. Forward: Monte Carlo from 76.92
at today's 5.04% dividend.
"""
import json,math,random,statistics as st
A=json.load(open("../tlt-auction/tlt.json"))["bars"]; B=json.load(open("tlt_hist.json"))
px={x["d"]:x["c"] for x in A}; px.update({x["d"]:x["c"] for x in B["bars"]})
days=sorted(px); DIV={x["ex"]:x["amount"] for x in B["dividends"]}
MR=0.0303; TOTAL=15000; H=252
def rule_block(t,P,held): return TOTAL if t==0 else 0
def rule_daily(t,P,held): return 100
def split(now):
    def r(t,P,held): return now if t==0 else 100
    return r
def downs(n,streak=1):
    def r(t,P,held):
        if t==0: return 0
        k=0
        while t-k>0 and P[t-k]<P[t-k-1]: k+=1
        return n if k>=streak else 0
    return r
METHODS=[("One block",rule_block),("100 a day",rule_daily),("10k now + 100/day",split(10000)),
         ("5k now + 100/day",split(5000)),("200 on any down day",downs(200)),
         ("300 on 2nd+ red day in a row",downs(300,2))]
def run(P,div,rule):
    sh=0; cash=0.0; done_t=None; buys=[]
    for t in range(H+1):
        if t>0:
            cash-= -min(cash,0)*MR/252
            cash+=sh*div[t]
        if t<H and sh<TOTAL:
            n=min(rule(t,P,sh),TOTAL-sh)
            if t==H-1: n=TOTAL-sh
            if n>0: cash-=n*P[t]; sh+=n; buys.append((n,P[t]))
            if sh>=TOTAL and done_t is None: done_t=t
    avg=sum(n*p for n,p in buys)/TOTAL
    return cash+sh*P[H], avg, done_t
def hist():
    starts=[i for i,d in enumerate(days) if d>="2007-04-02" and i+H<len(days)]
    out={m:[] for m,_ in METHODS}
    for i in starts[::2]:
        P=[px[days[i+t]] for t in range(H+1)]; dv=[DIV.get(days[i+t],0) for t in range(H+1)]
        base,bavg,_=run(P,dv,rule_block)
        for m,r in METHODS:
            e,a,dt=run(P,dv,r); out[m].append((days[i],e-base,a/P[0]-1,dt))
    return out
def show(out,label,f=lambda r:True):
    print(f"\n{label}")
    for m,_ in METHODS[1:]:
        x=[r for r in out[m] if f(r)]; v=[r[1] for r in x]
        print(f"  {m:30} ahead {sum(a>0 for a in v)/len(v)*100:4.0f}%  median {st.median(v):+9,.0f}  "
              f"worst {min(v):+9,.0f}  avg price vs start {st.median(r[2] for r in x)*100:+5.1f}%  "
              f"done day {st.median(r[3] for r in x if r[3] is not None) if any(r[3] is not None for r in x) else '-'}")
out=hist()
chg={}
for i,d in enumerate(days):
    if i+H<len(days): chg[d]=px[days[i+H]]/px[d]-1
show(out,"HISTORY, all starts 2007-2025 (vs one block)")
show(out,"  ...years TLT rose >5%",lambda r:chg[r[0]]>0.05)
show(out,"  ...years TLT within 5%",lambda r:abs(chg[r[0]])<=0.05)
show(out,"  ...years TLT fell >5%",lambda r:chg[r[0]]<-0.05)
S0=76.92; Q=0.0504
SCEN=[("Calm, flat",0.00,0.10),("Fed eases +15%",0.15,0.13),("QE +30%",0.30,0.18),("Inflation -15%",-0.15,0.15)]
print("\nFORWARD 12 months from 76.92: median vs one block (daily-ahead %)")
print(f"  {'':30}"+"".join(f"{s[0]:>22}" for s in SCEN))
res={m:[] for m,_ in METHODS[1:]}
for k,(nm,dr,vol) in enumerate(SCEN):
    rng=random.Random(9+k); acc={m:[] for m,_ in METHODS[1:]}
    for _ in range(1500):
        mu=math.log(1+dr)/H; s=vol/math.sqrt(H); P=[S0]
        for _ in range(H): P.append(P[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
        dv=[0]+[P[t-1]*Q/252 for t in range(1,H+1)]
        base,_,_=run(P,dv,rule_block)
        for m,r in METHODS[1:]: acc[m].append(run(P,dv,r)[0]-base)
    for m in acc: v=acc[m]; res[m].append((st.median(v),sum(a>0 for a in v)/len(v)))
for m,v in res.items():
    print(f"  {m:30}"+"".join(f"{a:>+14,.0f} ({p*100:3.0f}%)" for a,p in v))
