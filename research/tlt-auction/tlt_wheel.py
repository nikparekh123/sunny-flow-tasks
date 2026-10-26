# -*- coding: utf-8 -*-
"""The wheel on a sideways month: 10,000 shares, sell calls AND puts at the money.

Nik wants to see the churn. Shares leave through assigned calls and come back through
assigned puts, and both premiums are collected either way. Run on a REAL sideways
stretch so the weekly moves are honest, with options priced Black-Scholes on TLT's own
realised vol at the time.
"""
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

# real Fridays from the data, so holidays cannot produce a missing key.
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4]
i0=FRI.index("2004-08-06")
WIN=FRI[i0:i0+7]   # the most sideways stretch found: oscillates around the strike
CALL_CT, PUT_CT = 50, 50
sh=10000.0; basis=82.0*sh; cash=0.0; prem=0.0
print("TLT sideways, %s to %s.  Start: 10,000 shares at 82.00\n"%(WIN[0],WIN[-1]))
print("%-12s %7s %7s %9s %9s %8s %8s %9s %10s"%("week","TLT","strike","calls","puts","assigned","shares","premium","committed"))
print("-"*92)
for i in range(len(WIN)-1):
    d,e=WIN[i],WIN[i+1]
    S=tlt[d]; K=round(S/0.5)*0.5; v=volAt(d); T=7/365
    cCt=min(CALL_CT, int(sh//100))          # covered only
    pCt=PUT_CT
    cPx=bs(S,K,T,v,"C"); pPx=bs(S,K,T,v,"P")
    got=cCt*cPx*100 + pCt*pPx*100
    prem+=got; cash+=got
    Sx=tlt[e]
    note=""
    if Sx>K:                                 # calls assign, shares leave at K
        sold=cCt*100
        per = basis/sh if sh else 0
        cash+=sold*K; basis-=per*sold; sh-=sold
        note="%d calls -> -%s sh"%(cCt,format(int(sold),","))
    elif Sx<K:                               # puts assign, shares arrive at K
        bought=pCt*100
        cash-=bought*K; basis+=bought*K; sh+=bought
        note="%d puts -> +%s sh"%(pCt,format(int(bought),","))
    else: note="both expire"
    committed=pCt*K*100
    if cCt==0: note=("puts only, no shares to cover; " + note)
    print("%-12s %7.2f %7.1f %9s %9s %8s %8s %9s %10s"%(
        d,S,K,"%d @ %.2f"%(cCt,cPx),"%d @ %.2f"%(pCt,pPx),note,
        format(int(sh),","),"$%s"%format(int(got),","),"$%s"%format(int(committed),",")))
print()
Sx=tlt[WIN[-1]]
print("after 6 weeks")
print("   shares      %s  (started 10,000)"%format(int(sh),","))
print("   avg basis   %s  (started 82.00)"%("%.2f"%(basis/sh) if sh else "no shares"))
print("   premium     $%s"%format(int(prem),","))
print("   TLT         %.2f  (started %.2f)"%(Sx,tlt[WIN[0]]))
print("   equity P&L  $%s"%format(int(Sx*sh-basis),","))
print("   TOTAL       $%s"%format(int(prem+Sx*sh-basis),","))
