# -*- coding: utf-8 -*-
"""NVDA CALLS: sell on a timetable, or sell into a bounce?

The mirror of the put question. If buying is best after a run of red days, selling
upside should be best after a run of green ones. Part 1 hinted at it: "up over 2%" was
the ONLY bucket with a negative next day, at -0.090%.

For a call the good outcome is the opposite of a put. You want either to keep the
shares and the premium, or, if called away, to have sold high. So the number that
matters is the effective SALE price:

    effective sale = strike + premium / delta

and HIGHER is better. Same per-expected-share logic as the puts: you collect premium on
every contract but only delta-many deliver a sale, so the rest is a bonus on those.

Measured in percent against each window's own mean price, because NVDA ran 5 to 225.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; C=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
lr=[math.log(C[i+1]/C[i]) for i in range(N-1)]
def volAt(i):
    w=lr[max(0,i-63):i]
    return max(0.10, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
def callLeg(S,K,T,v):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return (S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-v*math.sqrt(T)), ND.cdf(a))
def greenStreak(i):
    n=0
    while n<i and C[i-n]/C[i-n-1]-1>0: n+=1
    return n
def nextFri(i,minD):
    j=i+1
    while j<N:
        if WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=minD: return j
        j+=1
    return None

OTMC=1.01                                   # calls 1% out, the mirror of the puts
def run(trig,minD,lo,hi):
    prem=sold=dsold=0.0; got=0.0; ev=0
    for i in range(lo,hi):
        if not trig(i): continue
        j=nextFri(i,minD)
        if j is None or j>=hi: continue
        t=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days
        S=C[i]; K=S*OTMC; v=volAt(i)
        px,dl=callLeg(S,K,t/365,v)
        if dl<=0: continue
        ct=1.0/dl; ev+=1
        prem+=px*ct; dsold+=dl*ct
        if C[j]>K: sold+=K*ct; got+=ct              # called away at K
    if got<=0: return None
    tape=st.mean(C[lo:hi])
    return dict(ev=ev, deliv=got/dsold, pct=100*((sold+prem)/got-tape)/tape)

ARMS=[("every Friday (timetable)",       lambda i: WD[i]==4, 5),
      ("any green day",                  lambda i: C[i]>C[i-1], 5),
      ("second green day onward",        lambda i: greenStreak(i)>=2, 5),
      ("third green day onward",         lambda i: greenStreak(i)>=3, 5),
      ("first green day of a run only",  lambda i: greenStreak(i)==1, 5),
      ("RED days only (control)",        lambda i: C[i]<C[i-1], 5)]
acc={l:[] for l,_,_ in ARMS}; ec={l:[] for l,_,_ in ARMS}; dv={l:[] for l,_,_ in ARMS}
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
    for lab in got: acc[lab].append(got[lab]['pct']); ec[lab].append(got[lab]['ev']); dv[lab].append(got[lab]['deliv'])

print("NVDA calls, 1%% OTM, Friday >=5 days.  %d rolling 12-week windows.\n"%segs)
print("%-32s %12s %11s %10s %8s"%("arm","sale % ","median","called/delta","events"))
print("-"*78)
for lab,_,_ in ARMS:
    print("%-32s %+12.3f %+11.3f %10.2f %8.0f"%(lab,st.mean(acc[lab]),st.median(acc[lab]),st.mean(dv[lab]),st.mean(ec[lab])))
print("\nsale %% = effective sale against the window's own mean price. HIGHER is better.")
base="every Friday (timetable)"
print("\n%-32s %14s %13s"%("arm","beats timetable","by (pct pts)"))
for lab,_,_ in ARMS:
    if lab==base: continue
    w=sum(1 for a,b_ in zip(acc[lab],acc[base]) if a>b_)
    print("%-32s %13.0f%% %+13.3f"%(lab,100*w/segs,st.mean(acc[lab])-st.mean(acc[base])))
