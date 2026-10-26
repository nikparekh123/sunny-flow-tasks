# -*- coding: utf-8 -*-
"""Nike-style split vs the TLT-style split on the live book names, real bars,
Sep 2024 to Oct 2026, Friday-to-Friday calls on every LEAP. Call P&L as % of the
stock's value per year; the LEAP side is identical in every arm."""
import json,datetime,statistics as st
def D(s): return datetime.date.fromisoformat(s)
def dyn(m):
    if m<=-0.10: return 0.2
    if m<0.05: return 0.3
    if m<0.15: return 0.5
    return 0.6
ARMS=[("Nike now: dynamic ATM / 1 SD",lambda m:[("atm",dyn(m)),("sd",1-dyn(m))]),
      ("Fixed 30/70 ATM / 1 SD",lambda m:[("atm",.3),("sd",.7)]),
      ("TLT-style 1/3 ATM, 2/3 +1%",lambda m:[("atm",1/3),("p1",2/3)]),
      ("TLT-style 1/3 ATM, 2/3 0.6 SD",lambda m:[("atm",1/3),("sd6",2/3)]),
      ("All ATM",lambda m:[("atm",1.0)]),
      ("All 1 SD",lambda m:[("sd",1.0)])]
NAMES=["NKE","BABA","NFLX","LULU","FIS","PEP","KR"]
tot={a:[] for a,_ in ARMS}; rows=[]
for t in NAMES:
    close={x["d"]:x["c"] for x in json.load(open(f"{t}_hist.json"))["bars"]}
    J=json.load(open(f"{t}_split.json")); OPX={k:{b["d"]:b["c"] for b in v} for k,v in J["bars"].items()}
    f=lambda e: 10 if (t=="NFLX" and e<"2025-11-17") else 1
    occ=lambda e,k:"O:%s%sC%08d"%(t,D(e).strftime("%y%m%d"),int(round(k*f(e)*1000)))
    weeks=[]
    for r in J["rolls"]:
        S=r["S"]; d=r["d"]; e=r["exp"]; Se=close[e]
        pr=[(k,OPX[occ(e,k)][d]/f(e)) for k in r["kc"] if occ(e,k) in OPX and d in OPX[occ(e,k)] and k>=S-1e-9]
        if not pr: continue
        legs={"atm":min(pr)}
        for key in ("p1","sd6","sd"): legs[key]=min(pr,key=lambda x:abs(x[0]-r["tg"][key]))
        weeks.append((r["m"],{k:((p-0.01)-max(0,Se-K))/S for k,(K,p) in legs.items()},Se/S-1))
    yrs=len(weeks)/52
    line=[t, sum(w[2] for w in weeks)/yrs*100]
    for nm,fn in ARMS:
        w=[sum(sh*p[k] for k,sh in fn(m)) for m,p,_ in weeks]
        y=sum(w)/yrs*100; tot[nm].append(w); line.append((y,sum(x<0 for x in w)/len(w)*100))
    rows.append(line)
hdr=["Nike now","30/70","1/3+1%","1/3+.6SD","All ATM","All 1SD"]
print(f"{'':6}{'stock/yr':>9} "+"".join(f"{h:>13}" for h in hdr))
for r in rows:
    print(f"{r[0]:6}{r[1]:+8.0f}% "+"".join(f"{y:+7.1f}% ({lw:2.0f})" for y,lw in r[2:]))
print(f"{'BOOK':6}{'':9} "+"".join(f"{st.mean(sum(w)/(len(w)/52)*100 for w in tot[a]):+7.1f}% ({st.mean(sum(x<0 for x in w)/len(w)*100 for w in tot[a]):2.0f})" for a,_ in ARMS))
