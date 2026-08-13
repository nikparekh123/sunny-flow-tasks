# -*- coding: utf-8 -*-
"""Price bands, yield bands, or yield-vs-its-own-mean?

TLT's dial reads an ABSOLUTE PRICE: below 75 buy hardest, above 85 barely at all.
Those lines were set at a price level and say nothing durable — 85 meant something
in 2024 and nothing in 2012. The 30-year yield explains TLT with R2 0.95, so the
question is whether anchoring the bands there is better, and whether it should be
an absolute yield or a distance from the yield's own trailing mean (the shape that
won on NVDA, where a fixed price could never have worked).
"""
import json, csv, math, datetime, statistics as st
from statistics import NormalDist
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
y30={}
for r in csv.DictReader(open("dgs30.csv")):
    v=r["DGS30"]
    if v not in (".","",None):
        try: y30[r["observation_date"]]=float(v)
        except ValueError: pass
days=sorted(set(tlt)&set(y30)); R,N=0.045,NormalDist()
close={d:tlt[d] for d in days}
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=st.stdev(lr)*math.sqrt(252)
# the yield's own 250-session mean — the moving reference
ymean={days[i]: st.mean(y30[d] for d in days[i-249:i+1]) for i in range(249,len(days))}
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv and d in ymean]
def nf(d):
    t=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    l=[x for x in days if x>=t]; return l[0] if l else None
def bs(S,K,T,v):
    if T<=0 or v<=0: return max(0.0,K-S)
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1)
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))

def fPrice(d):
    S=close[d]
    for hi,f in ((75,2.50),(80,1.50),(85,0.75),(1e9,0.25)):
        if S<hi: return f
def fYieldAbs(d):
    v=y30[d]
    for lo,f in ((5.75,2.50),(5.50,1.75),(5.25,1.25),(5.00,0.75)):
        if v>=lo: return f
    return 0.25
def fYieldRel(d):
    # distance from the yield's own 250d mean, in 25bp steps
    g=(y30[d]-ymean[d])*100
    for lo,f in ((50,2.50),(25,1.75),(0,1.25),(-25,0.75)):
        if g>=lo: return f
    return 0.25

TARGET,START,HOR,BASE=100000.0,3000.0,72,846.0
def walk(sub,fac):
    sh=float(START); lots=[[float(START),float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0
    for i,d in enumerate(sub):
        exp=nf(d)
        if not exp: break
        S,v,T=close[d],rv[d],7/365
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*fac(d)
        K=round(S/0.5)*0.5
        pd_=pdelta(S,K,T,v); ct=max(0,round(per/(pd_*100))) if pd_>0 else 0
        if ct: puts.append({"K":K,"ct":ct,"exp":exp,"p":bs(S,K,T,v)})
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        mtm=S*held-basis+prem; peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    return dict(sh=sh, net=prem+(Sx*held-basis), dd=dd, bp=(basis/held) if held else 0)

wins=[i for i in range(0,len(FRI)-HOR)]
print("%d windows x %d weeks  (%s .. %s)\n"%(len(wins),HOR,FRI[0],FRI[wins[-1]]))
print("%-30s %9s %9s %11s %12s"%("bands","shares","basis","net","worst DD"))
print("-"*76)
for label,fn in (("price 75/80/85 (today)",fPrice),
                 ("yield abs 5.00-5.75",fYieldAbs),
                 ("yield vs its 250d mean",fYieldRel)):
    rs=[walk(FRI[i:i+HOR],fn) for i in wins]; n=len(rs)//2
    sh=sorted(r["sh"] for r in rs); nt=sorted(r["net"] for r in rs)
    bp=sorted(r["bp"] for r in rs); dd=sorted(r["dd"] for r in rs)
    print("%-30s %9s %9s %11s %12s"%(label,format(int(sh[n]),","),"$%.2f"%bp[n],
          "$%s"%format(int(nt[n]),","),"$%s"%format(int(dd[n]),",")))
print()
for label,fn in (("price",fPrice),("yield abs",fYieldAbs),("yield rel",fYieldRel)):
    from collections import Counter
    c=Counter(fn(d) for d in FRI)
    print("  %-10s band usage: %s"%(label, dict(sorted(c.items()))))
