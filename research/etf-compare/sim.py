# -*- coding: utf-8 -*-
"""Same money in each: $1.15M of shares on margin (3.03%), one weekly ATM call per
100 shares, Friday to Friday, real option bars. Settled as a roll at the expiry
close (no overnight rebuy luck). 6 Sep 2024 to 2 Oct 2026."""
import json,math,datetime,statistics as st,sys
from statistics import NormalDist
ND=NormalDist().cdf
CAP=1_150_000; MR=0.0303
def D(s): return datetime.date.fromisoformat(s)
def bs(S,K,T,v,r=0.04):
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(r+v*v/2)*T)/sq; return S*ND(d1)-K*math.exp(-r*T)*ND(d1-sq)
def ivof(p,S,K,T):
    lo,hi=0.01,3
    for _ in range(70):
        m=(lo+hi)/2
        if bs(S,K,T,m)<p: lo=m
        else: hi=m
    return m
OUT={}
for t in (sys.argv[1:] or ["TLT","SLV","URA"]):
    H=json.load(open(f"{t}_hist.json")); close={x["d"]:x["c"] for x in H["bars"]}; days=sorted(close)
    DIV={x["ex"]:x["amount"] for x in H["dividends"]}
    C=json.load(open(f"{t}_calls.json")); OPX={k:{b["d"]:b["c"] for b in v} for k,v in C["bars"].items()}
    occ=lambda e,k:"O:%s%sC%08d"%(t,D(e).strftime("%y%m%d"),int(round(k*1000)))
    R=C["rolls"]; S0=R[0]["S"]; N=int(CAP/S0/100)*100; end=R[-1]["exp"]
    shares=N*(close[end]-S0); divs=sum(N*a for d,a in DIV.items() if R[0]["d"]<d<=end)
    yrs=(D(end)-D(R[0]["d"])).days/365; interest=N*S0*MR*yrs
    rows=[]
    for r in R:
        S=r["S"]; ks=[k for k in r["ks"] if occ(r["exp"],k) in OPX and r["d"] in OPX[occ(r["exp"],k)]]
        if not ks: continue
        K=min(ks,key=lambda k:(abs(k-S),-k))
        p=OPX[occ(r["exp"],K)][r["d"]]; T=(D(r["exp"])-D(r["d"])).days/365
        iv=ivof(p,S,K,T) if p>max(0,S-K)+0.005 else None
        i=days.index(r["d"]); j=days.index(r["exp"])
        lr=[math.log(close[days[k+1]]/close[days[k]]) for k in range(i,j)]
        n=N//100; prem=n*100*(p-0.01)-n*0.65; pay=n*100*max(0,close[r["exp"]]-K)
        rows.append((r["d"],prem,pay,iv,lr,p/S))
    prem=sum(x[1] for x in rows); pay=sum(x[2] for x in rows)
    print(f"\n{t}: {S0:.2f} -> {close[end]:.2f} ({(close[end]/S0-1)*100:+.0f}%)  {N:,} shares  over {yrs:.2f} yrs")
    print(f"  shares only (price + dividends - margin): {shares+divs-interest:+,.0f}   [dividends {divs:,.0f}, margin {-interest:,.0f}]")
    print(f"  calls: premium {prem:,.0f}  paid out {pay:,.0f}  kept {prem-pay:+,.0f}  ({(prem-pay)/yrs:+,.0f}/yr, {(prem-pay)/prem*100:.0f}% of premium)")
    print(f"  with calls total: {shares+divs-interest+prem-pay:+,.0f}   avg weekly premium {st.mean(x[5] for x in rows)*100:.2f}% of price")
    per={}
    for x in rows: per.setdefault(x[0][:4]+(" H1" if int(x[0][5:7])<=6 else " H2"),[]).append(x)
    for k,v in per.items():
        a=close[v[0][0]]; b=close[days[min(len(days)-1,days.index(v[-1][0])+5)]]
        ivs=[x[3] for x in v if x[3]]; lr=[y for x in v for y in x[4]]
        print(f"   {k} {t} {(b/a-1)*100:+5.0f}%  kept {sum(x[1]-x[2] for x in v):+10,.0f}  implied {st.mean(ivs)*100:5.1f}%  realised {st.pstdev(lr)*math.sqrt(252)*100:5.1f}%")
    lr=[math.log(close[days[k+1]]/close[days[k]]) for k in range(len(days)-1)]
    print("  realised vol now: "+"  ".join(f"{n}d {st.pstdev(lr[-n:])*math.sqrt(252)*100:.1f}%" for n in (20,60,250)))
