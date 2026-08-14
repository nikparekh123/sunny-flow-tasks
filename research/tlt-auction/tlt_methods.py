# -*- coding: utf-8 -*-
"""Ten ways to run the wheel on 10,000 TLT shares, over two weeks.

Strikes round to the NEAREST 0.50, so 82.12 writes the 82 and 81.65 writes the 81.50.
Total is change in net worth: premium, plus realised gains on any shares called away,
plus the mark on whatever is still held. That makes arms that end with different share
counts comparable, which "premium collected" alone does not.
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
def near(S): return round(S/0.5)*0.5           # 82.12 -> 82.00, 81.65 -> 81.50

FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4]
i0=FRI.index("2004-08-06"); WIN=FRI[i0:i0+3]   # two weeks
START_SH = 10000.0
# Marked at the START PRICE, not at the 82 cost. Otherwise an arm that sells the block
# books the whole 82-to-86 gain as if it were the fortnight's work, and any method that
# liquidates wins on a number that is really just pre-existing profit.
START_BASIS = tlt[FRI[FRI.index("2004-08-06")]]

def run(cCt, cUp, pCt, pDn):
    sh=START_SH; per=START_BASIS; prem=0.0; realised=0.0; commit=0.0; naked=0
    for i in range(len(WIN)-1):
        d,e=WIN[i],WIN[i+1]
        S=tlt[d]; v=volAt(d); T=7/365
        cK=near(S)+0.5*cUp; pK=near(S)-0.5*pDn
        c=min(cCt, int(sh//100))
        prem += c*bs(S,cK,T,v,"C")*100 + pCt*bs(S,pK,T,v,"P")*100
        commit=max(commit, pCt*pK*100)
        if pCt*100>sh: naked+=1
        Sx=tlt[e]
        if Sx>cK and c:
            sold=c*100; realised+=(cK-per)*sold; sh-=sold
        if Sx<pK and pCt:
            b=pCt*100; per=(per*sh+pK*b)/(sh+b); sh+=b
    Sx=tlt[WIN[-1]]
    equity=(Sx-per)*sh
    return dict(sh=sh, per=per, prem=prem, realised=realised, commit=commit, naked=naked,
                total=prem+realised+equity)

M=[("1  ATM both, 50/50",              50,0, 50,0, "the naive wheel, both legs at the money"),
   ("2  calls +1, puts ATM, 25/50",    25,1, 50,0, "corridor above only, light call cover"),
   ("3  calls +1, puts -1, 25/50",     25,1, 50,1, "corridor both sides, one strike each"),
   ("4  calls +2, puts -2, 25/50",     25,2, 50,2, "wide corridor, expects nothing to assign"),
   ("5  calls +2, puts ATM, 25/50",    25,2, 50,0, "sell upside cheap, buy dips at the money"),
   ("6  calls +1 only, 50/0",          50,1, 0,0,  "pure overwrite, no accumulation"),
   ("7  puts ATM only, 0/50",           0,0, 50,0, "pure accumulation, no calls"),
   ("8  calls +1, puts ATM, 50/25",    50,1, 25,0, "call heavy, drains on purpose"),
   ("9  calls +3, puts ATM, 25/50",    25,3, 50,0, "calls far out, almost never called"),
   ("10 calls ATM, puts -1, 25/50",    25,0, 50,1, "give up upside, only buy on a dip")]

print("TLT %s to %s.  %.2f -> %.2f -> %.2f   Start 10,000 shares at 82.00\n"%(
    WIN[0],WIN[-1],tlt[WIN[0]],tlt[WIN[1]],tlt[WIN[2]]))
print("%-30s %8s %7s %9s %9s %10s %8s %10s"%("method","shares","basis","premium","realised","commit","naked","TOTAL"))
print("-"*98)
for lab,cc,cu,pc,pd,why in M:
    r=run(cc,cu,pc,pd)
    print("%-30s %8s %7s %9s %9s %10s %8d %10s"%(lab,format(int(r["sh"]),","),
      "%.2f"%r["per"] if r["sh"] else "none","$%s"%format(int(r["prem"]),","),
      "$%s"%format(int(r["realised"]),","),"$%s"%format(int(r["commit"]),","),
      r["naked"],"$%s"%format(int(r["total"]),",")))
print()
for lab,_,_,_,_,why in M: print("   %-32s %s"%(lab, why))
