# -*- coding: utf-8 -*-
"""Which candidate signals actually predict a week's put outcome?

Each Friday write of a 1% OTM weekly is scored two ways: the option's own P&L per
contract, and whether it delivered shares. A family only earns its place if a high
reading separates good weeks from bad.
"""
import json, math, datetime, statistics
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist(); OB=json.load(open("nvda_opt.json"))
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def occ(exp,K): return "O:NVDA%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000)))
cl=[close[d] for d in days]
def sma(n,i): return sum(cl[i-n+1:i+1])/n if i>=n-1 else None
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)

rows=[]
for i,d in enumerate(days):
    if d not in rv or datetime.date.fromisoformat(d).weekday()!=4: continue
    exp=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    if exp>days[-1]: continue
    S=close[d]; K=round(S*0.99/2.5)*2.5
    m=None
    for o in (0,-2.5,2.5,-5,5):
        mm=mark.get((occ(exp,K+o),d))
        if mm and mm>0: K,m=K+o,mm; break
    if m is None: continue
    px=None
    for x in days:
        if x<=exp: px=close[x]
        else: break
    T=7/365
    iv=m/(S*math.sqrt(T))*2.5                       # rough implied, premium normalised by sqrt-time
    ma100=sma(100,i); ma50=sma(50,i); ma200=sma(200,i)
    if not ma100 or not ma200: continue
    rows.append(dict(
        d=d, pnl=m-max(0,K-px), assigned=1 if px<K else 0,
        rich=iv-rv[d],                              # implied minus realised: the variance premium
        ivlvl=iv,
        below=100*(S/ma100-1),                      # the multiplier's own reading, for reference
        trend=100*(ma50/ma200-1),
        hv=rv[d],
        lastwk=100*(S/close[days[i-5]]-1) if i>=5 else 0,
    ))
print("weeks scored: %d  (%s to %s)\n"%(len(rows),rows[0]["d"],rows[-1]["d"]))

def tertiles(key,label):
    r=sorted(rows,key=lambda x:x[key]); n=len(r); t=n//3
    lo,mid,hi=r[:t],r[t:2*t],r[2*t:]
    f=lambda g,k: statistics.mean([x[k] for x in g])
    print("  %-22s  P&L/ct  low %+6.2f  mid %+6.2f  high %+6.2f   spread %+6.2f   |   delivery  %2.0f%% %2.0f%% %2.0f%%"%(
        label, f(lo,"pnl"), f(mid,"pnl"), f(hi,"pnl"), f(hi,"pnl")-f(lo,"pnl"),
        100*f(lo,"assigned"), 100*f(mid,"assigned"), 100*f(hi,"assigned")))

print("sorted low -> high on each signal, %d weeks per tertile\n"%(len(rows)//3))
tertiles("rich","variance premium (IV-HV)")
tertiles("ivlvl","implied level")
tertiles("hv","realised vol")
tertiles("below","distance vs MA100")
tertiles("trend","50 vs 200 day")
tertiles("lastwk","last week's move")
print()
base=statistics.mean([x["pnl"] for x in rows])
print("  baseline P&L per contract %+.2f  ·  delivery %.0f%%  ·  sd of weekly P&L %.2f"%(
    base, 100*statistics.mean([x["assigned"] for x in rows]), statistics.stdev([x["pnl"] for x in rows])))
