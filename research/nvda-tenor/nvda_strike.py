# -*- coding: utf-8 -*-
"""NVDA accumulation: ATM or out of the money, at a constant delta budget."""
import json, math, datetime, statistics, urllib.request, time
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist()
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv]

# ATM by delta; the OTM arms by distance, which is how a person actually says it
ARMS={"ATM":("delta",0.50),"OTM 2%":("pct",0.02),"OTM 5%":("pct",0.05)}
def strike(S,v,T,kind,val):
    if kind=="delta":
        d1=-N.inv_cdf(val); K=S*math.exp((R+v*v/2)*T-d1*v*math.sqrt(T))
    else:
        K=S*(1-val)
    return round(K/2.5)*2.5

plan={}; need=set()
for name,(kind,val) in ARMS.items():
    rows=[]
    for d in FRI:
        exp=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
        if exp>days[-1]: continue
        S,v,T=close[d],rv[d],7/365
        K=strike(S,v,T,kind,val)
        rows.append({"d":d,"exp":exp,"S":S,"v":v,"K":K})
        for o in (0,-2.5,2.5,-5,5):
            k=K+o
            if k>0: need.add("O:NVDA%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(k*1000))))
    plan[name]=rows
OB=json.load(open("nvda_opt.json"))
todo=sorted(need-set(OB)); print("rolls/arm",{k:len(v) for k,v in plan.items()},"| fetching",len(todo))
K_="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
for i in range(0,len(todo),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K_,"apikey":K_,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=400)); OB.update(r.get("bars") or {})
    time.sleep(0.3)
json.dump(OB,open("nvda_opt.json","w"))
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def occ(exp,K): return "O:NVDA%sP%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000)))
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
def cbefore(d):
    best=None
    for x in days:
        if x<=d: best=x
        else: break
    return close[best]

WEEK=190
def run(name):
    shares=paid=prem=0.0; bought=0.0; dw=0.0; skip=0; openp=[]; maxout=0.0; cts=0
    for r in plan[name]:
        d,S,v,T=r["d"],r["S"],r["v"],7/365
        for leg in list(openp):
            if leg["exp"]<=d:
                if cbefore(leg["exp"])<leg["K"]:
                    shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
                openp.remove(leg)
        K=m=None
        for o in (0,-2.5,2.5,-5,5):
            mm=mark.get((occ(r["exp"],r["K"]+o),d))
            if mm and mm>0: K,m=r["K"]+o,mm; break
        if K is None: skip+=1; continue
        dl=pdelta(S,K,T,v)
        ct=max(0,round(WEEK/(dl*100))) if dl>0 else 0
        if ct>0:
            prem+=m*100*ct; dw+=dl*ct*100; cts+=ct
            openp.append({"K":K,"ct":ct,"exp":r["exp"]})
            maxout=max(maxout,sum(l["K"]*100*l["ct"] for l in openp))
    for leg in openp:
        if cbefore(leg["exp"])<leg["K"]:
            shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
    fin=close[days[-1]]
    return dict(n=len(plan[name])-skip,ct=cts,shares=shares,prem=prem,
                delivery=bought/dw if dw else 0,
                basis=(paid-prem)/bought if bought else 0,
                maxout=maxout,total=shares*fin+prem-paid,skip=skip)

print("\nNVDA accumulation · REAL marks · 190 delta/week in every arm · weekly")
print("NVDA %.2f -> %.2f\n"%(close[FRI[0]],close[days[-1]]))
hdr="%-8s %6s %8s %9s %9s %9s %11s %11s"%("strike","ct/wk","shares","DELIVERY","premium","NET BASIS","peak cash","TOTAL")
print(hdr); print("-"*len(hdr))
res={}
for name in ARMS:
    r=run(name); res[name]=r
    print("%-8s %6.1f %8.0f %8.0f%% %9.0f %9.2f %11.0f %11.0f"%(
        name,r["ct"]/max(1,r["n"]),r["shares"],100*r["delivery"],r["prem"],r["basis"],r["maxout"],r["total"]))
a=res["ATM"]
for k in ("OTM 2%","OTM 5%"):
    d=res[k]
    print("\n%-7s vs ATM: shares %+.0f · basis %+.2f · peak cash %+.0f · TOTAL %+.0f"%(
        k,d["shares"]-a["shares"],d["basis"]-a["basis"],d["maxout"]-a["maxout"],d["total"]-a["total"]))
print("\nskipped:",{k:res[k]["skip"] for k in res})
