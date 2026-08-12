# -*- coding: utf-8 -*-
"""Does the overwrite pay for the floor, on ONE share path, with rolling?

The share path comes from the accumulation programme alone and is then held fixed.
Calls are rolled at expiry rather than assigned, so the block never leaves: the cost
of keeping it is max(0, S_exp - K), which is exactly what a roll debits.
"""
import json, math, datetime, statistics, urllib.request, time
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist(); OB=json.load(open("nvda_opt.json"))
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv]
def tf(y,m):
    d=datetime.date(y,m,1); return d+datetime.timedelta(days=(4-d.weekday())%7+14)
QTR=[q for q in (tf(y,m).isoformat() for y in (2024,2025,2026) for m in (3,6,9,12)) if days[22]<=q<=days[-1]]
def occ(exp,cp,K): return "O:NVDA%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(K*1000)))
def cbefore(d):
    best=None
    for x in days:
        if x<=d: best=x
        else: break
    return close[best]

# ── 1. the canonical share path: accumulation alone, no overlay ─────────────
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def pxOf(exp,cp,K,d,offs):
    for o in offs:
        m=mark.get((occ(exp,cp,K+o),d))
        if m and m>0: return K+o,m
    return None,None
shares=1500.0; path={}; openp=[]
for d in FRI:
    exp=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    if exp>days[-1]: continue
    for leg in list(openp):
        if leg["exp"]<=d:
            if cbefore(leg["exp"])<leg["K"]: shares+=leg["ct"]*100
            openp.remove(leg)
    path[d]=shares
    S,v,T=close[d],rv[d],7/365
    d1=-N.inv_cdf(0.50); K=round(S*math.exp((R+v*v/2)*T-d1*v*math.sqrt(T))/2.5)*2.5
    K,m=pxOf(exp,"P",K,d,(0,-2.5,2.5,-5,5))
    if not K: continue
    dl=N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
    ct=max(0,round(190/(dl*100)))
    if ct>0: openp.append({"K":K,"ct":ct,"exp":exp})
print("share path: %d -> %d over %d weeks (accumulation only)\n"%(1500,shares,len(path)))

# ── 2. strikes for each call delta, and the floor ───────────────────────────
DELTAS={"0.10 delta":0.10,"0.20 delta":0.20,"0.30 delta":0.30}
need=set(); cs={}
for nm,dv in DELTAS.items():
    rows=[]
    for d in FRI:
        exp=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
        if exp>days[-1]: continue
        S,v,T=close[d],rv[d],7/365
        K=round(S*math.exp((R+v*v/2)*T-N.inv_cdf(dv)*v*math.sqrt(T))/2.5)*2.5
        rows.append({"d":d,"exp":exp,"K":K})
        for o in (0,2.5,-2.5,5,-5): need.add(occ(exp,"C",K+o))
    cs[nm]=rows
FL={}
for pct in (0.10,0.15):
    rows=[]
    for i,q in enumerate(QTR[:-1]):
        d=next((x for x in days if x>=q), None)
        if not d: continue
        K=round(close[d]*(1-pct)/2.5)*2.5
        rows.append({"d":d,"exp":QTR[i+1],"K":K})
        for o in (0,-5,5,-10,10): need.add(occ(QTR[i+1],"P",K+o))
    FL[pct]=rows
todo=sorted(need-set(OB)); print("fetching",len(todo))
K_="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
for i in range(0,len(todo),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K_,"apikey":K_,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(rq,timeout=400)); OB.update(r.get("bars") or {}); time.sleep(0.3)
json.dump(OB,open("nvda_opt.json","w"))
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]

def callPnl(nm,cov):
    got=paidBack=0.0; n=0; rolled=0; otm=[]
    for r in cs[nm]:
        sh=path.get(r["d"])
        if not sh: continue
        ct=int(sh*cov//100)
        if ct<=0: continue
        K,m=pxOf(r["exp"],"C",r["K"],r["d"],(0,2.5,-2.5,5,-5))
        if not K: continue
        px=cbefore(r["exp"])
        got+=m*100*ct; cost=max(0,px-K)*100*ct; paidBack+=cost; n+=1
        otm.append(100*(K/close[r["d"]]-1))
        if cost>0: rolled+=1
    return got,paidBack,got-paidBack,n,rolled,(sum(otm)/len(otm) if otm else 0)

def floorPnl(pct):
    paid=recov=0.0
    for r in FL[pct]:
        sh=path.get(min([d for d in path if d>=r["d"]], default=None)) or 1500
        ct=max(1,int(sh//100))
        K,m=pxOf(r["exp"],"P",r["K"],r["d"],(0,-5,5,-10,10))
        if not K: continue
        paid+=m*100*ct; recov+=max(0,K-cbefore(r["exp"]))*100*ct
    return paid,recov,recov-paid

print("\nFLOOR, rolled quarterly, sized to the block")
print("   %-10s %12s %12s %12s"%("distance","premium paid","recovered","NET"))
fl={}
for pct in (0.10,0.15):
    p,rc,net=floorPnl(pct); fl[pct]=net
    print("   %-10s %12.0f %12.0f %+12.0f"%("%.0f%% OTM"%(pct*100),p,rc,net))

print("\nOVERWRITE, rolled at expiry so the shares never leave")
print("   %-11s %5s %12s %12s %12s %8s  %s"%("delta","cov","collected","roll cost","NET","rolls","funds a 10% floor?"))
for nm in DELTAS:
    for cov in (0.20,0.35,0.50):
        got,back,net,n,rolled,avgotm=callPnl(nm,cov)
        print("   %-11s %4.0f%% %7.1f%% %12.0f %12.0f %+12.0f %4d/%-3d  %s"%(
            nm,cov*100,avgotm,got,back,net,rolled,n,
            "yes" if net>=-fl[0.10] else "no (short %.0f)"%(-fl[0.10]-net)))
