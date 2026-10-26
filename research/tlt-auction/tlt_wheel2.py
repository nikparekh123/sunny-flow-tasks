# -*- coding: utf-8 -*-
"""Same sideways six weeks, varying the put count against 50 calls."""
import json, math, datetime, statistics as st
from statistics import NormalDist
N=NormalDist(); R=0.045
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
days=sorted(tlt)
lr=[math.log(tlt[days[i+1]]/tlt[days[i]]) for i in range(len(days)-1)]
def volAt(d):
    i=days.index(d); w=lr[max(0,i-63):i]
    return st.stdev(w)*math.sqrt(252) if len(w)>5 else 0.10
def bs(S,K,T,v,cp):
    if T<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2) if cp=="C" else K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1)
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4]
i0=FRI.index("2004-08-06"); WIN=FRI[i0:i0+7]

def run(callCt, putCt, show=False):
    sh=10000.0; basis=82.0*sh; prem=0.0; peakCommit=0.0; nakedWks=0; log=[]
    for i in range(len(WIN)-1):
        d,e=WIN[i],WIN[i+1]
        S=tlt[d]; K=round(S/0.5)*0.5; v=volAt(d); T=7/365
        cCt=min(callCt, int(sh//100))
        got=cCt*bs(S,K,T,v,"C")*100 + putCt*bs(S,K,T,v,"P")*100
        prem+=got
        naked=max(0.0, putCt*100 - sh)          # puts with no shares behind them
        if naked>0: nakedWks+=1
        peakCommit=max(peakCommit, putCt*K*100)
        Sx=tlt[e]; note="both expire"
        if Sx>K and cCt:
            per=basis/sh if sh else 0; sold=cCt*100
            basis-=per*sold; sh-=sold; note="-%s sh"%format(int(sold),",")
        elif Sx<K:
            b=putCt*100; basis+=b*K; sh+=b; note="+%s sh"%format(int(b),",")
        log.append((d,S,cCt,putCt,note,sh,got))
    Sx=tlt[WIN[-1]]
    return dict(sh=sh, prem=prem, bp=(basis/sh) if sh else 0, commit=peakCommit,
                naked=nakedWks, eq=Sx*sh-basis, log=log)

print("TLT %s to %s, drift %+.1f%%.  Start 10,000 shares at 82.00\n"%(
    WIN[0],WIN[-1],100*(tlt[WIN[-1]]/tlt[WIN[0]]-1)))
print("%-16s %9s %9s %11s %12s %8s %11s"%("arm","end shares","basis","premium","peak commit","naked wk","total"))
print("-"*84)
for c,p in ((50,50),(50,75),(50,100)):
    r=run(c,p)
    print("%-16s %9s %9s %11s %12s %8d %11s"%("%d calls / %d puts"%(c,p),
        format(int(r["sh"]),","), ("%.2f"%r["bp"]) if r["sh"] else "none",
        "$%s"%format(int(r["prem"]),","), "$%s"%format(int(r["commit"]),","),
        r["naked"], "$%s"%format(int(r["prem"]+r["eq"]),",")))
print()
for c,p in ((50,75),(50,100)):
    r=run(c,p)
    print("%d calls / %d puts, week by week"%(c,p))
    for d,S,cc,pc,note,shx,got in r["log"]:
        print("   %-12s %6.2f  %2d calls %3d puts  %-10s  shares %-7s  $%s"%(
            d,S,cc,pc,note,format(int(shx),","),format(int(got),",")))
    print()
