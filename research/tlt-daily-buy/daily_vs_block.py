# -*- coding: utf-8 -*-
"""100 TLT shares a day vs one block (Nik, 7 Oct 2026).

Same end state: 15,000 shares after 150 trading days. Every start day since April
2007 (real closes, real dividends), margin 3.03% on what is borrowed. Then the same
build forward 150 days under the 12-month scenarios, at today's 5.04% dividend.
"""
import json,math,random,statistics as st,datetime
A=json.load(open("../tlt-auction/tlt.json"))["bars"]; B=json.load(open("tlt_hist.json"))
px={x["d"]:x["c"] for x in A}; px.update({x["d"]:x["c"] for x in B["bars"]})
days=sorted(px); DIV={x["ex"]:x["amount"] for x in B["dividends"]}
MR=0.0303; TOTAL=15000; PER=100; NB=TOTAL//PER
def D(s): return datetime.date.fromisoformat(s)
def build(i0,daily):
    sh=0; cash=0.0
    for j in range(i0,i0+NB+1):
        d=days[j]
        if j>i0:
            cash-= -min(cash,0)*MR*(D(d)-D(days[j-1])).days/365
            if d in DIV: cash+=sh*DIV[d]
        if j<i0+NB or not daily:
            n = PER if daily else (TOTAL if j==i0 else 0)
            if j==i0+NB: n=0
            cash-=n*px[d]; sh+=n
    end=days[i0+NB]
    return cash+sh*px[end]
starts=[i for i,d in enumerate(days) if d>="2007-04-02" and i+NB<len(days)]
res=[]
for i in starts:
    dl=build(i,True); lp=build(i,False)
    avg=st.mean(px[days[j]] for j in range(i,i+NB))
    res.append((days[i],dl-lp,avg/px[days[i]]-1,px[days[i+NB]]/px[days[i]]-1))
def summ(rs,label):
    x=[r[1] for r in rs]
    print(f"{label:24} windows {len(x):5}  daily ahead {sum(v>0 for v in x)/len(x)*100:4.0f}%  "
          f"median {st.median(x):+9,.0f}  best {max(x):+9,.0f}  worst {min(x):+9,.0f}  "
          f"avg price lower {sum(r[2]<0 for r in rs)/len(rs)*100:3.0f}% of the time")
print("Daily (100/day) minus one block, after 150 days, 15,000 shares\n")
summ(res,"All 2007-2026")
summ([r for r in res if r[0]<"2020-08-01"],"2007-Jul 2020 (rates falling)")
summ([r for r in res if r[0]>="2020-08-01"],"Aug 2020-2026 (rates rising)")
summ([r for r in res if r[3]>0.03],"TLT rose >3% in window")
summ([r for r in res if abs(r[3])<=0.03],"TLT within 3%")
summ([r for r in res if r[3]<-0.03],"TLT fell >3%")

# forward: next 150 trading days, today's dividend
S0=76.92; Q=0.0504
SCEN=[("Calm, flat",0.00,0.10),("Choppy, flat",0.00,0.16),("Fed eases +15%",0.15,0.13),
      ("QE +30%",0.30,0.18),("Inflation -15%",-0.15,0.15)]
print("\nForward 150 days from 76.92 (scenario moves are per 12 months)")
for k,(nm,dr,vol) in enumerate(SCEN):
    rng=random.Random(5+k); out=[]; avgs=[]
    for _ in range(3000):
        mu=math.log(1+dr)/252; s=vol/math.sqrt(252); S=[S0]
        for _ in range(NB): S.append(S[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
        held=[PER*j for j in range(NB)]                     # daily: shares held each day
        carry=sum((h if True else 0) for h in held)          # share-days
        # daily: P&L = sum over buys of (S_end - S_buy)*100 + carry on share-days
        dl=sum((S[-1]-S[j])*PER for j in range(NB))+sum(PER*j*S[j] for j in range(NB))*(Q-MR)/252
        lp=TOTAL*(S[-1]-S0)+sum(TOTAL*S[j] for j in range(NB))*(Q-MR)/252
        out.append(dl-lp); avgs.append(st.mean(S[:NB])/S0-1)
    out.sort()
    print(f"  {nm:16} daily minus block: median {st.median(out):+9,.0f}  (10th {out[300]:+9,.0f} .. 90th {out[2700]:+9,.0f})  daily ahead {sum(v>0 for v in out)/len(out)*100:3.0f}%")
