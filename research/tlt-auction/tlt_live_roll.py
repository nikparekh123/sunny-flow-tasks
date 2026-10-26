# -*- coding: utf-8 -*-
"""The roll-schedule test again, on TLT's live chain instead of a flat surface.

Mids pulled from tlt-planner dry runs on 2026-08-14, spot 81.92, strike 82,
`modelled:false` on every quote. The backtest had to assume Monday and Wednesday
contracts priced on the same vol surface as Friday's. This checks that assumption
against what the market is actually charging.
"""
import math
from statistics import NormalDist
ND=NormalDist(); R=0.04; S=81.92; K=82.0

# expiry, calendar days, live mid, live delta
LIVE=[("Mon Aug 17",3,0.275,0.56),("Wed Aug 19",5,0.395,0.54),("Fri Aug 21",7,0.485,0.54),
      ("Mon Aug 24",10,0.515,0.53),("Wed Aug 26",12,0.585,0.53),("Fri Aug 28",14,0.665,0.53),
      ("Fri Sep 04",21,0.99,0.51),("Fri Sep 18",35,1.22,0.51)]

def putpx(S,K,T,v):
    if T<=0: return max(0.0,K-S)
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return K*math.exp(-R*T)*ND.cdf(-d2)-S*ND.cdf(-d1)
def iv(px,T):
    lo,hi=0.005,3.0
    for _ in range(200):
        m=(lo+hi)/2
        if putpx(S,K,T,m)>px: hi=m
        else: lo=m
    return (lo+hi)/2

print("LIVE TERM STRUCTURE, TLT 82 put, spot %.2f\n"%S)
print("%-12s %4s %7s %7s %8s %14s"%("expiry","days","mid","delta","impl vol","$/expected share"))
curve=[]
for lab,d,mid,dl in LIVE:
    T=d/365; v=iv(mid,T); curve.append((d,v))
    print("%-12s %4d %7.3f %7.2f %7.1f%% %14.3f"%(lab,d,mid,dl,v*100,mid/dl))

def volAt(d):                       # linear in days across the observed curve
    if d<=curve[0][0]: return curve[0][1]
    if d>=curve[-1][0]: return curve[-1][1]
    for (a,va),(b,vb) in zip(curve,curve[1:]):
        if a<=d<=b: return va+(vb-va)*(d-a)/(b-a)

# the two schedules over the same fortnight, Aug 14 -> Aug 28
EVERY=[3,2,2,3,2,2]     # 14>17 17>19 19>21 21>24 24>26 26>28
FRI  =[7,7]             # 14>21 21>28
WEEKLY_DELTA=1861

print("\n%-24s %14s %14s"%("","EVERY EXPIRY","FRIDAY ONLY"))
def report(lab, f): print("%-24s %14s %14s"%(lab, f(EVERY), f(FRI)))

def legs(sched):
    out=[]
    for d in sched:
        T=d/365; v=volAt(d); px=putpx(S,K,T,v)
        dl=ND.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
        out.append((d,px,dl))
    return out

# arm 1: fixed 48 contracts, which is what "48 rolled six times" literally means
def fixed(sched,ct=48):
    L=legs(sched); return sum(p*100*ct for _,p,_ in L), sum(dl*100*ct for _,_,dl in L)
# arm 2: sized to the same accumulation pace
def paced(sched):
    L=legs(sched); pr=0; de=0; pk=0
    for d,p,dl in L:
        want=WEEKLY_DELTA*d/7.0; ct=max(1,round(want/(dl*100)))
        pr+=p*100*ct; de+=dl*100*ct; pk=max(pk,K*100*ct)
    return pr,de,pk

report("rolls", lambda s:"%d"%len(s))
report("--- at a flat 48 contracts ---", lambda s:"")
report("premium",        lambda s:"$%s"%format(round(fixed(s)[0]),","))
report("delta sold",     lambda s:format(round(fixed(s)[1]),","))
report("$ per 1,000 delta", lambda s:"$%s"%format(round(1000*fixed(s)[0]/fixed(s)[1]),","))
report("--- sized to 1,861/wk ---", lambda s:"")
report("contracts per roll", lambda s:"%.0f"%(paced(s)[1]/len(s)/53))
report("premium",        lambda s:"$%s"%format(round(paced(s)[0]),","))
report("delta sold",     lambda s:format(round(paced(s)[1]),","))
report("peak cash",      lambda s:"$%s"%format(round(paced(s)[2]),","))

pe,pf=paced(EVERY)[0],paced(FRI)[0]
print("\nFriday-only pays %.0f%% more for the same shares, on live prices."%(100*(pf/pe-1)))
print("Flat-surface backtest said 64 pct. The real chain says %.0f pct."%(100*(pf/pe-1)))

# What the current three-expiry split is actually buying, on this curve.
print("\nTHE THREE-EXPIRY SPLIT, same 1,861 delta, three ways")
for lab,sched in (("nearest three (what ships): Aug 17/19/21",[3,5,7]),
                  ("three Fridays: Aug 21 / 28 / Sep 4",[7,14,21]),
                  ("one Friday: Aug 21",[7])):
    L=legs(sched); pr=0; de=0; pk=0
    per=WEEKLY_DELTA/len(sched)          # split the week's budget evenly
    for d,px,dl in L:
        ct=max(1,round(per/(dl*100))); pr+=px*100*ct; de+=dl*100*ct; pk=max(pk,K*100*ct)
    print("  %-42s premium $%-7s delta %-6s peak cash $%s"%(
        lab, format(round(pr),","), format(round(de),","), format(round(pk),",")))
