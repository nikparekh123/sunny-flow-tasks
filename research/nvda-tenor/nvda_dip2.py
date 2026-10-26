# -*- coding: utf-8 -*-
"""NVDA PART 2: wait-for-red versus write-every-Friday.

Two design changes from the TLT version, both forced by NVDA:

  1. NVDA ran roughly 5 to 225 over this sample, so "basis versus the average tape"
     over the whole history is meaningless: any arm that accumulated early wins on
     the trend rather than on skill. Everything here runs in ROLLING 12-week windows
     and is measured in PERCENT against that window's own mean price.
  2. Strikes are not snapped to a grid. A $2.50 grid is right at $225 and absurd at
     $5, and the sample spans both.

NVDA's own rules are held fixed: 1% out of the money, weekly Friday expiry.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; OTM=0.99; TEN=7
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; C=[x["c"] for x in b]; N=len(D); IDX={x:i for i,x in enumerate(D)}
lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
def volAt(i):
    w=lr[max(0,i-63):i]
    return max(0.10, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
def leg(S,K,T,v):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return (K*math.exp(-R*T)*ND.cdf(-(a-v*math.sqrt(T)))-S*ND.cdf(-a), ND.cdf(-a))
def expiry(i,t):
    j=i
    while j<N-1 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days<t: j+=1
    return j
def streak(i):
    n=0
    while n<i and C[i-n]/C[i-n-1]-1<0: n+=1
    return n

def run(trig,lo,hi,size=lambda i:1.0):
    """Returns basis as a PERCENT of the window's mean price, plus delivery stats."""
    prem=cost=dsold=0.0; sh=0.0; ev=0
    for i in range(lo,hi):
        if not trig(i): continue
        ev+=1; S=C[i]; K=S*OTM; v=volAt(i); T=TEN/365
        px,dl=leg(S,K,T,v); q=size(i)
        # sized in DELTA so every arm delivers the same expected shares per event
        ct=q/ (dl if dl>0 else 1)
        prem+=px*ct; dsold+=dl*ct
        j=expiry(i,TEN)
        if j<hi and C[j]<K: cost+=K*ct; sh+=ct
    if sh<=0: return None
    tape=st.mean(C[lo:hi])
    return dict(ev=ev, deliv=sh/dsold if dsold else 0,
                pct=100*((cost-prem)/sh-tape)/tape, sh=sh)

FRI=[i for i in range(N) if datetime.date.fromisoformat(D[i]).weekday()==4]
ARMS=[("every Friday (today's rule)", lambda i: datetime.date.fromisoformat(D[i]).weekday()==4),
      ("any red day",                 lambda i: C[i]<C[i-1]),
      ("second red day onward",       lambda i: streak(i)>=2),
      ("third red day onward",        lambda i: streak(i)>=3),
      ("first red day of a streak",   lambda i: streak(i)==1),
      ("green days only (control)",   lambda i: C[i]>C[i-1])]

wins={l:[] for l,_ in ARMS}; dl={l:[] for l,_ in ARMS}; ev={l:[] for l,_ in ARMS}
segs=0
for s in range(70,N-70,10):
    lo,hi=s,s+60
    if hi>=N-6: break
    ok={}
    for lab,t in ARMS:
        r=run(t,lo,hi)
        if r is None: ok=None; break
        ok[lab]=r
    if not ok: continue
    segs+=1
    for lab in ok:
        wins[lab].append(ok[lab]['pct']); dl[lab].append(ok[lab]['deliv']); ev[lab].append(ok[lab]['ev'])

print("NVDA, 1%% OTM weekly puts.  %d rolling 12-week windows, 2018-2026.\n"%segs)
print("%-32s %10s %10s %9s %9s"%("arm","basis %","median","delivered","events"))
print("-"*74)
for lab,_ in ARMS:
    print("%-32s %+10.3f %+10.3f %9.2f %9.0f"%(lab,st.mean(wins[lab]),st.median(wins[lab]),
          st.mean(dl[lab]),st.mean(ev[lab])))
print("\nbasis %% = entry against that window's own mean price. Negative is cheaper.")
base="every Friday (today's rule)"
print("\n%-32s %14s %14s"%("arm","beats Friday","by (pct pts)"))
for lab,_ in ARMS:
    if lab==base: continue
    w=sum(1 for a,b_ in zip(wins[lab],wins[base]) if a<b_)
    print("%-32s %13.0f%% %+14.3f"%(lab,100*w/segs,st.mean(wins[lab])-st.mean(wins[base])))
