# -*- coding: utf-8 -*-
import json, math, datetime
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); bars={b["d"]:b["c"] for b in H["bars"]}
days=sorted(bars); DIV=[(x["ex"],x["amount"]) for x in H.get("dividends") or []]
P=json.load(open("nvda_plan.json"))["plan"]; OB=json.load(open("nvda_opt.json"))
R,N=0.045,NormalDist()
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def occ(exp,K): return "O:NVDA%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000)))
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
def cbefore(d):
    best=None
    for x in days:
        if x<=d: best=x
        else: break
    return bars[best]

WEEKLY_DELTA=190          # the accumulation RATE, identical in every arm
CEIL=None                 # capital is reported, not capped, so tenor is not hidden by a cap

# A contract can exist and simply not TRADE on the roll date, which is common on
# far-dated strikes and would otherwise drop those rolls entirely — penalising the
# long tenors for a gap in the data rather than a gap in the market. Fall back to
# the most recent print within three sessions.
BACK=[d for d in days]
def price(r):
    """the roll's own strike if it trades, else the nearest listed neighbour"""
    i=BACK.index(r["d"]) if r["d"] in BACK else -1
    dates=[r["d"]]+([BACK[j] for j in range(i-1,max(-1,i-4),-1)] if i>0 else [])
    for off in (0,-1,1,-1.5,1.5,-2,2,-2.5,2.5,-5,5):
        k=round((r["K"]+off)*2)/2
        for dd in dates:
            m=mark.get((occ(r["exp"],k),dd))
            if m and m>0: return k,m
    return None,None

def run(name):
    rolls=P[name]; dte=rolls[0]["dte"]; per=WEEKLY_DELTA*dte/7
    shares=paid=prem=divs=0.0; bought=0.0; skip=0; openp=[]; maxout=0.0; deltaWritten=0.0
    divq=sorted(DIV)
    for r in rolls:
        d,S,v,T=r["d"],r["S"],r["v"],r["dte"]/365
        for leg in list(openp):
            if leg["exp"]<=d:
                px=cbefore(leg["exp"])
                if px<leg["K"]:
                    shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
                openp.remove(leg)
        while divq and divq[0][0]<=d: divs+=divq.pop(0)[1]*shares
        K,m=price(r)
        if K is None: skip+=1; continue
        dl=pdelta(S,K,T,v)
        ct=max(0,round(per/(dl*100))) if dl>0 else 0
        if ct>0:
            prem+=m*100*ct; deltaWritten+=dl*ct*100; openp.append({"K":K,"ct":ct,"exp":r["exp"]})
            maxout=max(maxout,sum(l["K"]*100*l["ct"] for l in openp))
    for leg in openp:
        px=cbefore(leg["exp"])
        if px<leg["K"]: shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
    while divq: divs+=divq.pop(0)[1]*shares
    fin=bars[days[-1]]
    return dict(n=len(rolls),skip=skip,deltaWritten=deltaWritten,delivery=(bought/deltaWritten if deltaWritten else 0),shares=shares,bought=bought,prem=prem,paid=paid,divs=divs,
                basis=(paid-prem)/bought if bought else 0,
                gross=paid/bought if bought else 0,
                maxout=maxout, total=shares*fin+prem-paid+divs)

print("NVDA accumulation · REAL marks · same 190 delta/week in every arm")
print("NVDA %.2f -> %.2f  (%s to %s)\n"%(bars[days[22]],bars[days[-1]],days[22],days[-1]))
hdr="%-9s %5s %8s %9s %9s %9s %9s %11s %11s"%("tenor","rolls","shares","DELIVERY","premium","gross bx","NET BASIS","peak cash","TOTAL")
print(hdr); print("-"*len(hdr))
res={}
for name in ("weekly","biweekly","monthly"):
    r=run(name); res[name]=r
    print("%-9s %5d %8.0f %8.0f%% %9.0f %9.2f %9.2f %11.0f %11.0f"%(
        name,r["n"],r["shares"],100*r["delivery"],r["prem"],r["gross"],r["basis"],r["maxout"],r["total"]))
print()
w=res["weekly"]
for k in ("biweekly","monthly"):
    d=res[k]
    print("%-9s vs weekly: basis %+.2f/share · shares %+.0f · peak cash %+.0f · total %+.0f"%(
        k, d["basis"]-w["basis"], d["shares"]-w["shares"], d["maxout"]-w["maxout"], d["total"]-w["total"]))
print("\nskipped rolls (no mark):", {k:res[k]["skip"] for k in res})
