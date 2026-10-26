# -*- coding: utf-8 -*-
"""NVDA PART 3: the trigger fires mid-week, so WHICH Friday does it write?

Part 2 assumed a flat 7-day contract on every trigger, which is not what NVDA does.
NVDA writes to a Friday expiry, so a Tuesday trigger writing "the coming Friday" is a
3-day contract, and the TLT study showed premium per unit of delta falls hard as tenor
shortens. The alternative is to skip to the following Friday, 8 to 11 days out.

Delivery is the constraint that makes this non-obvious: NVDA's tenor test put delivery
at 98% for a week and 82% for a month, so reaching for tenor eventually costs shares.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; OTM=0.99
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; C=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
def volAt(i):
    w=lr[max(0,i-63):i]
    return max(0.10, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
def leg(S,K,T,v):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return (K*math.exp(-R*T)*ND.cdf(-(a-v*math.sqrt(T)))-S*ND.cdf(-a), ND.cdf(-a))
def streak(i):
    n=0
    while n<i and C[i-n]/C[i-n-1]-1<0: n+=1
    return n
def nextFri(i, minDays):
    j=i+1
    while j<N:
        if WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=minDays: return j
        j+=1
    return None

def run(trig, minDays, lo, hi):
    prem=cost=dsold=0.0; sh=0.0; ev=0; ten=[]
    for i in range(lo,hi):
        if not trig(i): continue
        j=nextFri(i,minDays)
        if j is None or j>=hi: continue
        t=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days
        S=C[i]; K=S*OTM; v=volAt(i); T=t/365
        px,dl=leg(S,K,T,v)
        if dl<=0: continue
        ct=1.0/dl; ev+=1; ten.append(t)
        prem+=px*ct; dsold+=dl*ct
        if C[j]<K: cost+=K*ct; sh+=ct
    if sh<=0: return None
    tape=st.mean(C[lo:hi])
    return dict(ev=ev, deliv=sh/dsold, pct=100*((cost-prem)/sh-tape)/tape, ten=st.mean(ten))

RED2=lambda i: streak(i)>=2
FRI =lambda i: WD[i]==4
ARMS=[("every Friday, next Friday",      FRI, 1),
      ("2nd red day, the COMING Friday", RED2, 1),
      ("2nd red day, Friday >=5 days",   RED2, 5),
      ("2nd red day, Friday >=8 days",   RED2, 8),
      ("2nd red day, Friday >=12 days",  RED2, 12)]
acc={l:[] for l,_,_ in ARMS}; dv={l:[] for l,_,_ in ARMS}; tn={l:[] for l,_,_ in ARMS}; evc={l:[] for l,_,_ in ARMS}
segs=0
for s in range(70,N-70,10):
    lo,hi=s,s+60
    if hi>=N-14: break
    got={}
    for lab,t,m in ARMS:
        r=run(t,m,lo,hi)
        if r is None: got=None; break
        got[lab]=r
    if not got: continue
    segs+=1
    for lab in got:
        acc[lab].append(got[lab]['pct']); dv[lab].append(got[lab]['deliv'])
        tn[lab].append(got[lab]['ten']); evc[lab].append(got[lab]['ev'])

print("NVDA, 1%% OTM, real Friday expiries.  %d rolling 12-week windows.\n"%segs)
print("%-34s %10s %9s %9s %8s"%("arm","basis %","avg tenor","delivered","events"))
print("-"*74)
for lab,_,_ in ARMS:
    print("%-34s %+10.3f %8.1fd %9.2f %8.0f"%(lab,st.mean(acc[lab]),st.mean(tn[lab]),
          st.mean(dv[lab]),st.mean(evc[lab])))
base="every Friday, next Friday"
print("\n%-34s %14s %13s"%("arm","beats Friday","by (pct pts)"))
for lab,_,_ in ARMS:
    if lab==base: continue
    w=sum(1 for a,b_ in zip(acc[lab],acc[base]) if a<b_)
    print("%-34s %13.0f%% %+13.3f"%(lab,100*w/segs,st.mean(acc[lab])-st.mean(acc[base])))
