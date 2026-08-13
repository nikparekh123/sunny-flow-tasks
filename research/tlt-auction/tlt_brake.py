# -*- coding: utf-8 -*-
"""Should TLT hard-stop the roll that spans a heavy event?

TLT already damps size for events, but only through conviction: a -12 penalty on a
score that feeds a 0.7-1.3 ramp, so the brake tops out around 0.9x. NVDA got a hard
zero because its conviction weight is off and the penalty did nothing at all. The
question here is whether TLT's soft brake should become a hard one.

Auction dates are REAL, from Treasury's own API (213 long-end auctions, 2017-2026).
FOMC dates are hand-entered from the published schedule and flagged as such.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
H=json.load(open("tlt.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist()
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=st.stdev(lr)*math.sqrt(252)
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv]
def nf(d):
    t=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    l=[x for x in days if x>=t]; return l[0] if l else None
def bs(S,K,T,v,cp):
    if T<=0 or v<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1)
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))

AUCT = set(json.load(open("auction_dates.json")))
# Published FOMC decision dates. HAND-ENTERED — not from an API, unlike the auctions.
FOMC = set("""2017-02-01 2017-03-15 2017-05-03 2017-06-14 2017-07-26 2017-09-20 2017-11-01 2017-12-13
2018-01-31 2018-03-21 2018-05-02 2018-06-13 2018-08-01 2018-09-26 2018-11-08 2018-12-19
2019-01-30 2019-03-20 2019-05-01 2019-06-19 2019-07-31 2019-09-18 2019-10-30 2019-12-11
2020-01-29 2020-03-15 2020-04-29 2020-06-10 2020-07-29 2020-09-16 2020-11-05 2020-12-16
2021-01-27 2021-03-17 2021-04-28 2021-06-16 2021-07-28 2021-09-22 2021-11-03 2021-12-15
2022-01-26 2022-03-16 2022-05-04 2022-06-15 2022-07-27 2022-09-21 2022-11-02 2022-12-14
2023-02-01 2023-03-22 2023-05-03 2023-06-14 2023-07-26 2023-09-20 2023-11-01 2023-12-13
2024-01-31 2024-03-20 2024-05-01 2024-06-12 2024-07-31 2024-09-18 2024-11-07 2024-12-18
2025-01-29 2025-03-19 2025-05-07 2025-06-18 2025-07-30 2025-09-17 2025-10-29 2025-12-10
2026-01-28 2026-03-18 2026-04-29 2026-06-17 2026-07-29""".split())

TARGET, START, HOR, BASE = 100000.0, 3000.0, 72, 846.0
BANDS=[(75,2.50),(80,1.50),(85,0.75),(float('inf'),0.25)]
def pfac(S):
    for hi,f in BANDS:
        if S < hi: return f
    return 0.25

def spans(d, exp, ev):
    return any(d < e <= exp for e in ev)

def walk(sub, ev, brake):
    sh=float(START); lots=[[float(START), float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0
    for i,d in enumerate(sub):
        exp=nf(d)
        if not exp: break
        S,v,T=close[d],rv[d],7/365
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]:
                    sh+=l["ct"]*100; lots.append([float(l["ct"]*100), float(l["K"])])
                puts.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i), 2*BASE)*pfac(S)
        if ev and spans(d, exp, ev): per *= brake
        K=round(S/0.5)*0.5
        pd_=pdelta(S,K,T,v); ct=max(0,round(per/(pd_*100))) if pd_>0 else 0
        if ct: puts.append({"K":K,"ct":ct,"exp":exp,"p":bs(S,K,T,v,"P")})
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        mtm=S*held-basis+prem; peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    return dict(sh=sh, net=prem+(Sx*held-basis), dd=dd)

wins=[i for i in range(0,len(FRI)-HOR)]
print("%d windows x %d weeks · TLT\n"%(len(wins),HOR))
print("%-34s %9s %11s %12s"%("arm","shares","net","worst DD"))
print("-"*70)
for label, ev, brake in (("no brake (today is ~0.9x)", None, 1.0),
                         ("auctions: hard stop", AUCT, 0.0),
                         ("auctions: 0.25x", AUCT, 0.25),
                         ("FOMC: hard stop", FOMC, 0.0),
                         ("FOMC: 0.25x", FOMC, 0.25),
                         ("both: hard stop", AUCT|FOMC, 0.0),
                         ("both: 0.25x", AUCT|FOMC, 0.25)):
    rs=[walk(FRI[i:i+HOR], ev, brake) for i in wins]
    n=len(rs)//2
    sh=sorted(r["sh"] for r in rs); nt=sorted(r["net"] for r in rs); dd=sorted(r["dd"] for r in rs)
    print("%-34s %9s %11s %12s"%(label, format(int(sh[n]),","), "$%s"%format(int(nt[n]),","), "$%s"%format(int(dd[n]),",")))
