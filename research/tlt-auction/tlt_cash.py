# -*- coding: utf-8 -*-
"""Correcting the cash column: all legs of a split are written at once, so the
commitment is the SUM of the legs, not the biggest one. Also how LONG the cash is
tied up, since a 21-day leg holds it three times as long as a 7-day leg."""
import math
from statistics import NormalDist
ND=NormalDist(); R=0.04; S=81.92; K=82.0; WK=1861
CURVE=[(3,.117),(5,.105),(7,.104),(10,.102),(12,.103),(14,.106),(21,.135),(35,.132)]  # trading-day IV
TD={3:1,5:3,7:5,10:6,12:8,14:10,21:14,35:24}
def vol(d): return dict(CURVE)[d]
def px(d):
    T=TD[d]/252; v=vol(d)
    a=(math.log(S/K)+(R*d/365/T+v*v/2)*T)/(v*math.sqrt(T)); b=a-v*math.sqrt(T)
    return K*math.exp(-R*d/365)*ND.cdf(-b)-S*ND.cdf(-a), ND.cdf(-a)

print("%-38s %9s %14s %14s %13s"%("split","premium","cash at once","cash-days","prem/cash-day"))
for lab,sch in (("nearest three: Aug 17 / 19 / 21",[3,5,7]),
                ("three Fridays: Aug 21 / 28 / Sep 4",[7,14,21]),
                ("one Friday: Aug 21 alone",[7])):
    per=WK/len(sch); pr=cash=cd=0
    for d in sch:
        p,dl=px(d); ct=max(1,round(per/(dl*100)))
        pr+=p*100*ct; cash+=K*100*ct; cd+=K*100*ct*d
    print("%-38s %9s %14s %14s %13.2f"%(lab,"$"+format(round(pr),","),
          "$"+format(round(cash),","), format(round(cd/1000),",")+"k", 1000*pr/cd))

# In STEADY STATE you write every week, so last week's legs are still alive when this
# week's go on. Average cash outstanding = cash-days per week / 7. That is the number
# the $400,000 ceiling actually governs.
print("\n%-34s %9s %12s %10s %s"%("split, written every week","premium","avg cash out","of $400k","fits?"))
best=[]
for lab,sch in (("Aug 17/19/21 (what ships)",[3,5,7]),("Aug 21 alone",[7]),
                ("Aug 21 / 28",[7,14]),("Aug 21 / 28 / Sep 4",[7,14,21]),
                ("Aug 19 / 21",[5,7]),("Aug 21 / 24 / 28",[7,10,14]),
                ("Aug 17/19/21/24/28",[3,5,7,10,14])):
    per=WK/len(sch); pr=cd=0
    for d in sch:
        p,dl=px(d); ct=max(1,round(per/(dl*100))); pr+=p*100*ct; cd+=K*100*ct*d
    avg=cd/7; ok=avg<=400000
    best.append((ok,pr,lab,avg))
    print("%-34s %9s %12s %9.0f%% %s"%(lab,"$"+format(round(pr),","),
          "$"+format(round(avg),","),100*avg/400000,"yes" if ok else "NO, over"))
f=[b for b in best if b[0]]; f.sort(key=lambda x:-x[1])
print("\nBest that fits the ceiling: %s at $%s a week, using %.0f%% of the ceiling."%(
    f[0][2], format(round(f[0][1]),","), 100*f[0][3]/400000))
