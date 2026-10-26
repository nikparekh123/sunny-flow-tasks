# -*- coding: utf-8 -*-
"""What each expiry choice actually costs and earns, per share acquired.

Live TLT chain, 2026-08-14, spot 81.92, strike 82, quotes straight off the planner
(modelled:false on every one). Sized so every option delivers the same 1,861 expected
shares a week, so the comparison is like for like.

The number that matters is the EFFECTIVE basis: K - premium/delta. You collect premium
on every contract but only about half of them deliver shares, so the premium from the
ones that expire worthless is a rebate on the ones that land.
"""
WK=1861; K=82.0; SPOT=81.92; TARGET=100000; HELD=100
LIVE={3:(0.275,0.56),5:(0.395,0.54),7:(0.485,0.54),10:(0.515,0.53),
      12:(0.585,0.53),14:(0.665,0.53),21:(0.99,0.51),35:(1.22,0.51)}
NAME={3:"Mon Aug 17",5:"Wed Aug 19",7:"Fri Aug 21",10:"Mon Aug 24",
      12:"Wed Aug 26",14:"Fri Aug 28",21:"Fri Sep 04",35:"Fri Sep 18"}

def build(sch):
    per=WK/len(sch); prem=cash=cd=sh=0; ct_t=0
    for d in sch:
        mid,dl=LIVE[d]; ct=max(1,round(per/(dl*100)))
        prem+=mid*100*ct; cash+=K*100*ct; cd+=K*100*ct*d; sh+=dl*100*ct; ct_t+=ct
    avg=cd/7                       # steady state: written every week, legs overlap
    return dict(prem=prem, cash=cash, avg=avg, sh=sh, ct=ct_t,
                basis=K-prem/sh, yld=prem*52/avg, wks=(TARGET-HELD)/sh)

OPT=[("Aug 17 / 19 / 21   (ships today)",[3,5,7]),
     ("Aug 17/19/21/24/28  (five)",       [3,5,7,10,14]),
     ("Aug 21 alone",                     [7]),
     ("Aug 21 / 28",                      [7,14]),
     ("Aug 21 / 28 / Sep 4",              [7,14,21]),
     ("Aug 28 alone",                     [14]),
     ("Aug 28 / Sep 4",                   [14,21]),
     ("Sep 4 alone",                      [21]),
     ("Sep 18 alone",                     [35])]

print("Every row delivers ~1,861 shares a week.  TLT %.2f, strike 82.\n"%SPOT)
print("%-34s %8s %7s %10s %6s %9s %8s"%(
      "expiries written each week","premium","ct","cash out","of400k","yield","new avg"))
print("-"*92)
for lab,s in OPT:
    r=build(s)
    print("%-34s %8s %7d %10s %5.0f%% %8.1f%% %8.2f"%(lab,"$"+format(round(r['prem']),","),
          r['ct'],"$"+format(round(r['avg']),","),100*r['avg']/400000,100*r['yld'],r['basis']))

print("\nWhat the basis is worth over the whole 100,000 share programme")
base=build([3,5,7])['basis']
for lab,s in OPT:
    r=build(s)
    print("  %-34s avg %.2f   %+9s vs what ships   %.0f weeks to 100k"%(
      lab,r['basis'],"$"+format(round((base-r['basis'])*TARGET),","),r['wks']))
