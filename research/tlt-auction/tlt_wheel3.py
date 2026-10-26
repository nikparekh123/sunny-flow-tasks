# -*- coding: utf-8 -*-
"""25 calls one strike above, puts at the money. Same sideways six weeks."""
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

def run(callCt, putCt, callUp):
    """callUp = strikes above the money for the call leg"""
    sh=10000.0; basis=82.0*sh; prem=0.0; commit=0.0; naked=0; log=[]
    for i in range(len(WIN)-1):
        d,e=WIN[i],WIN[i+1]
        S=tlt[d]; v=volAt(d); T=7/365
        pK=round(S/0.5)*0.5                 # puts at the money
        cK=pK+0.5*callUp                    # calls one strike up
        cCt=min(callCt, int(sh//100))
        got=cCt*bs(S,cK,T,v,"C")*100 + putCt*bs(S,pK,T,v,"P")*100
        prem+=got
        if putCt*100>sh: naked+=1
        commit=max(commit, putCt*pK*100)
        Sx=tlt[e]; ev=[]
        if Sx>cK and cCt:
            per=basis/sh if sh else 0; sold=cCt*100
            basis-=per*sold; sh-=sold; ev.append("-%s"%format(int(sold),","))
        if Sx<pK:
            b=putCt*100; basis+=b*pK; sh+=b; ev.append("+%s"%format(int(b),","))
        log.append((d,S,cK,pK,cCt,"/".join(ev) or "both expire",sh,got))
    Sx=tlt[WIN[-1]]
    return dict(sh=sh,prem=prem,bp=(basis/sh) if sh else 0,commit=commit,naked=naked,eq=Sx*sh-basis,log=log)

print("TLT %s to %s, drift %+.1f%%.  Start 10,000 at 82.00\n"%(WIN[0],WIN[-1],100*(tlt[WIN[-1]]/tlt[WIN[0]]-1)))
print("%-30s %9s %8s %11s %12s %7s %11s"%("arm","end shares","basis","premium","peak commit","naked","total"))
print("-"*94)
for c,p,up,lab in ((50,50,0,"50 calls ATM / 50 puts"),
                   (25,50,1,"25 calls +1 strike / 50 puts"),
                   (25,75,1,"25 calls +1 strike / 75 puts"),
                   (25,100,1,"25 calls +1 strike / 100 puts")):
    r=run(c,p,up)
    print("%-30s %9s %8s %11s %12s %7d %11s"%(lab,format(int(r["sh"]),","),
        ("%.2f"%r["bp"]) if r["sh"] else "none","$%s"%format(int(r["prem"]),","),
        "$%s"%format(int(r["commit"]),","),r["naked"],"$%s"%format(int(r["prem"]+r["eq"]),",")))
print()
r=run(25,50,1)
print("25 calls +1 strike / 50 puts, week by week")
for d,S,cK,pK,cc,ev,shx,got in r["log"]:
    print("   %-12s TLT %6.2f  call %5.1f  put %5.1f  %2d calls  %-14s shares %-7s  $%s"%(
        d,S,cK,pK,cc,ev,format(int(shx),","),format(int(got),",")))
