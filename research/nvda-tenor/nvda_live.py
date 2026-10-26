# -*- coding: utf-8 -*-
"""NVDA on the live chain: tenor, and the strike question.

Real Polygon quotes and real Polygon deltas, 2026-08-14, NVDA 225.15.

Two things being measured, both per EXPECTED SHARE, because that is the only unit in
which a 0.25-delta put and a 0.75-delta put are comparable:

    premium per expected share = mid / delta
    effective entry            = strike - mid / delta

You collect premium on every contract but only delta-many of them deliver shares, so
the premium from the ones that expire worthless is a rebate on the ones that land.
"""
import json, math
DIR="/private/tmp/claude-501/-Users-niketparekh-Library-Mobile-Documents-com-apple-CloudDocs-Claude-sunny-flow-tasks/47e7cc72-31e5-44b3-9498-1bb625ae85c2/scratchpad/nvchain"
DAYS={"2026-08-21":7,"2026-08-28":14,"2026-09-04":21,"2026-09-18":35}
CH={}
for e in DAYS:
    d=json.load(open("%s/%s.json"%(DIR,e)))
    CH[e]={r["strike"]:(r["premium"], abs(r["delta"]) if r.get("delta") else None) for r in d["strikes"]}
S=225.15

print("NVDA %.2f.  PART A: tenor, at the 1%% OTM strike NVDA already uses (222.5).\n"%S)
print("%-14s %5s %8s %7s %13s %12s %14s"%("expiry","days","prem","delta","prem/exp shr","entry","shares/$100k"))
print("-"*82)
for e in sorted(DAYS,key=lambda x:DAYS[x]):
    k=222.5
    if k not in CH[e] or not CH[e][k][1]: continue
    p,dl=CH[e][k]
    print("%-14s %5d %8.2f %7.3f %13.2f %12.2f %14.0f"%(
        e,DAYS[e],p,dl,p/dl,k-p/dl,dl*100/(k*100)*100000))

print("\nPART B: strike, on the 16-day-ish expiry (Aug 28, 14 days).\n")
print("%-10s %9s %8s %7s %13s %12s %14s"%("strike","moneyness","prem","delta","prem/exp shr","entry","shares/$100k"))
print("-"*80)
for k in sorted(CH["2026-08-28"]):
    p,dl=CH["2026-08-28"][k]
    if not dl or p<=0: continue
    tag = "%+.1f%%"%(100*(k-S)/S)
    print("%-10.1f %9s %8.2f %7.3f %13.2f %12.2f %14.0f"%(k,tag,p,dl,p/dl,k-p/dl,dl*100/(k*100)*100000))

print("\nPART C: the two candidates head to head, per 100 expected shares.\n")
for lab,e,k in [("Aug 21 (7d)  222.5, the safe one", "2026-08-21",222.5),
                ("Aug 28 (14d) 222.5, the aggressive one","2026-08-28",222.5)]:
    p,dl=CH[e][k]
    ct=100/(dl*100)                       # contracts needed for 100 expected shares
    print("  %-40s %.2f contracts  premium $%-7.0f  entry %.2f  cash $%s"%(
        lab, ct, p*100*ct, k-p/dl, format(round(k*100*ct),",")))
