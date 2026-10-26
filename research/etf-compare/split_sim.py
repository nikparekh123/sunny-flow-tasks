# -*- coding: utf-8 -*-
"""Split retest on real bars (Nik, 8 Oct 2026), Sep 2024 to Oct 2026, weekly
Friday calls on every 100 shares. Short-call P&L = premium (bar close - 1c) minus
what the call is worth at expiry, as % of the stock's value, summed per year.
Arms differ ONLY in how the calls are split, so the share/LEAP side is identical."""
import json,datetime,statistics as st
def D(s): return datetime.date.fromisoformat(s)
def dyn(m):            # Nik's NKE/NFLX rule: ATM share by last month's move, capped at 60%
    if m <= -0.10: return 0.2
    if m < 0.05: return 0.3
    if m < 0.15: return 0.5
    return 0.6
ARMS=[("All ATM",lambda m:[("atm",1.0)]),
      ("1/3 ATM, 2/3 +1% (TLT plan)",lambda m:[("atm",1/3),("p1",2/3)]),
      ("30/70 ATM / 1 SD (NKE fixed)",lambda m:[("atm",0.3),("sd",0.7)]),
      ("Dynamic 20-60% ATM / 1 SD (NKE)",lambda m:[("atm",dyn(m)),("sd",1-dyn(m))]),
      ("All at 1 SD",lambda m:[("sd",1.0)])]
res={}
for t in ("TLT","SLV","URA","SPY","QQQ","IWM"):
    close={x["d"]:x["c"] for x in json.load(open(f"{t}_hist.json"))["bars"]}
    J=json.load(open(f"{t}_split.json")); OPX={k:{b["d"]:b["c"] for b in v} for k,v in J["bars"].items()}
    occ=lambda e,k:"O:%s%sC%08d"%(t,D(e).strftime("%y%m%d"),int(round(k*1000)))
    weeks=[]
    for r in J["rolls"]:
        S=r["S"]; d=r["d"]; e=r["exp"]; Se=close[e]
        pr=[(k,OPX[occ(e,k)][d]) for k in r["kc"] if occ(e,k) in OPX and d in OPX[occ(e,k)] and k>=S-1e-9]
        if not pr: continue
        legs={"atm":min(pr)}
        for key in ("p1","sd"):
            legs[key]=min(pr,key=lambda x:abs(x[0]-r["tg"][key]))
        pnl={key:((p-0.01)-max(0,Se-k))/S for key,(k,p) in legs.items()}
        weeks.append((d,r["m"],pnl,Se/S-1))
    yrs=(D(weeks[-1][0])-D(weeks[0][0])).days/365+7/365
    stock=sum(w[3] for w in weeks)/yrs
    out=[]
    for nm,f in ARMS:
        w=[sum(sh*p[k] for k,sh in f(m)) for _,m,p,_ in weeks]
        up=[x for x,(_,_,_,r) in zip(w,weeks) if r>0.01]
        out.append((nm,sum(w)/yrs*100,sum(x<0 for x in w)/len(w)*100,sum(up)/yrs*100))
    res[t]=(stock*100,out,len(weeks))
for t,(stock,out,n) in res.items():
    print(f"\n{t}  ({n} weeks; stock itself {stock:+.1f}%/yr, sum of weekly moves)")
    for nm,y,lw,up in out:
        print(f"   {nm:34} calls {y:+6.1f}%/yr   losing weeks {lw:3.0f}%   in up-weeks {up:+6.1f}%/yr")
