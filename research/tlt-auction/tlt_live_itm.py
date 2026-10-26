# -*- coding: utf-8 -*-
"""The two mechanisms behind the backtest winner, checked on the real chain.

A trigger cannot be tested on one snapshot, but the two things it relies on can:

  1. does going IN the money really convert a fixed ceiling into shares faster
  2. does the SHORT tenor really win once you account for capital turning over

Both were true against modelled vol. Real quotes carry put skew, which the model did
not, and skew makes out-of-the-money puts richer. That is the thing that could break it.
"""
import json, math, glob
from statistics import NormalDist
ND=NormalDist(); R=0.04
DIR="/private/tmp/claude-501/-Users-niketparekh-Library-Mobile-Documents-com-apple-CloudDocs-Claude-sunny-flow-tasks/47e7cc72-31e5-44b3-9498-1bb625ae85c2/scratchpad/chain"
DAYS={"2026-08-17":3,"2026-08-21":7,"2026-08-28":14,"2026-09-04":21}
TD  ={"2026-08-17":1,"2026-08-21":5,"2026-08-28":10,"2026-09-04":14}
def bsput(S,K,T,v):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return K*math.exp(-R*T)*ND.cdf(-(a-v*math.sqrt(T)))-S*ND.cdf(-a)
def iv(px,S,K,T):
    lo,hi=0.005,3.0
    for _ in range(120):
        m=(lo+hi)/2
        if bsput(S,K,T,m)>px: hi=m
        else: lo=m
    return (lo+hi)/2

CH={}
for e in DAYS:
    d=json.load(open("%s/%s.json"%(DIR,e))); S=d["spot"]
    CH[e]={r["strike"]:(r["premium"],abs(r["delta"]) if r.get("delta") else None) for r in d["strikes"]}
SPOT=json.load(open("%s/2026-08-21.json"%DIR))["spot"]

print("TLT %.3f.  Real quotes, real Polygon deltas.\n"%SPOT)
print("PART A  Does going in the money convert the ceiling into shares faster?")
print("Aug 21 (7 day).  Ceiling is fixed, so the question is shares per dollar tied up.\n")
print("%-12s %8s %7s %8s %10s %14s %12s"%("strike","moneyness","prem","delta","impl vol","shares/$100k","eff basis"))
print("-"*80)
for k in sorted(CH["2026-08-21"]):
    if not (79.5<=k<=85): continue
    p,dl=CH["2026-08-21"][k]
    if not dl or p<=0: continue
    v=iv(p,SPOT,k,7/365)
    print("%-12.2f %8.2f %7.3f %8.3f %9.1f%% %14.0f %12.2f"%(
        k,k-SPOT,p,dl,100*v,dl*100/(k*100)*100000,k-p/dl))

print("\nPART B  Tenor, once capital turnover is counted.")
print("Strike held at 1.00 in the money (83) so only tenor changes.\n")
print("%-14s %5s %8s %7s %11s %16s %11s"%("expiry","days","prem","delta","eff basis","shares/$100k/wk","impl vol"))
print("-"*82)
for e in sorted(DAYS,key=lambda x:DAYS[x]):
    k=83.0
    if k not in CH[e]: continue
    p,dl=CH[e][k]
    if not dl or p<=0: continue
    v=iv(p,SPOT,k,TD[e]/252)
    perwk = dl*100/(k*100)*100000*(7.0/DAYS[e])
    print("%-14s %5d %8.3f %7.3f %11.2f %16.0f %10.1f%%"%(e,DAYS[e],p,dl,k-p/dl,perwk,100*v))

print("\nPART C  The head to head, at a $400,000 ceiling, from these quotes.")
print("%-34s %10s %12s %13s"%("arm","eff basis","shares/wk","wks to 100k"))
print("-"*72)
for lab,e,k in [("Aug 21 (7d) / at the money 82",  "2026-08-21",82.0),
                ("Aug 21 (7d) / 0.50 ITM  82.5",   "2026-08-21",82.5),
                ("Aug 21 (7d) / 1.00 ITM  83",     "2026-08-21",83.0),
                ("Aug 21 (7d) / 1.50 ITM  83.5",   "2026-08-21",83.5),
                ("Aug 28 (14d) / 1.00 ITM 83",     "2026-08-28",83.0),
                ("Sep 4 (21d) / 1.00 ITM  83",     "2026-09-04",83.0),
                ("Aug 21 (7d) / 1.00 OTM  81",     "2026-08-21",81.0)]:
    if k not in CH[e]: continue
    p,dl=CH[e][k]
    if not dl or p<=0: continue
    ct=int(400000/(k*100))                       # contracts the ceiling allows at once
    wk=ct*dl*100*(7.0/DAYS[e])
    print("%-34s %10.2f %12.0f %13.0f"%(lab,k-p/dl,wk,100000/wk if wk else 999))
