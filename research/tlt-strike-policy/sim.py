import json,math,datetime
from statistics import NormalDist
H=json.load(open("tlt_hist.json")); bars={b["d"]:b["c"] for b in H["bars"]}
days=sorted(bars); DIV=[(d["ex"],d["amount"]) for d in H["dividends"]]
P=json.load(open("plan.json")); plan=P["plan"]
OB=json.load(open("opt_bars.json"))
R=0.045; N=NormalDist()
mark={}                                  # (contract,date) -> close
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def occ(exp,cp,K): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(K*1000)))
def bsdelta(S,K,T,v,cp):
    if T<=0 or v<=0: return (1.0 if S>K else 0.0) if cp=="C" else (1.0 if S<K else 0.0)
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
    return N.cdf(d1) if cp=="C" else N.cdf(-d1)
def close_on_or_before(d):
    lo,hi=0,len(days)-1; best=None
    for x in days:
        if x<=d: best=x
        else: break
    return bars[best],best
def pf(S): return 2.5 if S<75 else 1.5 if S<80 else 0.75 if S<85 else 0.25

BASE=846; CEIL=400_000; CALL_FLOOR=5000; COVER=0.20
rolls=sorted(plan)
final=bars[days[-1]]

def run(putpol,callpol):
    shares=0.0; cash=0.0; prem=0.0; paid=0.0; recv=0.0; divs=0.0
    openp=[]; openc=[]; skipped=0; bought=0.0; maxout=0.0
    divq=sorted(DIV)
    for d in rolls:
        r=plan[d]; S=r["S"]; v=r["v"]; exp=r["exp"]; T=7/365
        # settle anything expiring on/before this roll first
        for lst,cp in ((openp,"P"),(openc,"C")):
            for leg in list(lst):
                if leg["exp"]<=d:
                    px,_=close_on_or_before(leg["exp"])
                    if cp=="P" and px<leg["K"]:
                        shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
                    if cp=="C" and px>leg["K"]:
                        q=min(shares,leg["ct"]*100); shares-=q; recv+=leg["K"]*q
                    lst.remove(leg)
        # dividends up to this date
        while divq and divq[0][0]<=d:
            ex,amt=divq.pop(0); divs+=amt*shares
        # ── puts ──
        K=r["put"][putpol]; c=occ(exp,"P",K); m=mark.get((c,d))
        if m is None or m<=0: skipped+=1
        else:
            dl=bsdelta(S,K,T,v,"P")
            want=max(0,round(BASE*pf(S)/(dl*100))) if dl>0 else 0
            out=sum(l["K"]*100*l["ct"] for l in openp)
            ct=min(want,int((CEIL-out)//(K*100)))
            if ct>0:
                prem+=m*100*ct; openp.append({"K":K,"ct":ct,"exp":exp})
                maxout=max(maxout,out+K*100*ct)
        # ── calls ──
        if callpol!="none" and shares>=CALL_FLOOR:
            Kc=r["call"][callpol]; cc=occ(exp,"C",Kc); mc=mark.get((cc,d))
            if mc is not None and mc>0:
                room=int((shares*COVER-sum(l["ct"]*100 for l in openc))//100)
                if room>0: prem+=mc*100*room; openc.append({"K":Kc,"ct":room,"exp":exp})
    # settle the tail
    for lst,cp in ((openp,"P"),(openc,"C")):
        for leg in lst:
            px,_=close_on_or_before(leg["exp"])
            if cp=="P" and px<leg["K"]: shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
            if cp=="C" and px>leg["K"]:
                q=min(shares,leg["ct"]*100); shares-=q; recv+=leg["K"]*q
    while divq: ex,amt=divq.pop(0); divs+=amt*shares
    total=shares*final+prem-paid+recv+divs
    return dict(shares=shares,prem=prem,paid=paid,recv=recv,divs=divs,total=total,
                bought=bought,basis=(paid/bought if bought else 0),
                net=( (paid-prem)/shares if shares else 0),maxout=maxout,skipped=skipped)

print("TLT accumulation · REAL closes + REAL option marks · %s -> %s · %d weekly rolls"%(rolls[0],rolls[-1],len(rolls)))
print("delta budget %d/wk x price multiplier · ceiling $%dK · calls off below %d shares · 20%% coverage"%(BASE,CEIL//1000,CALL_FLOOR))
print("TLT %.2f -> %.2f\n"%(bars[rolls[0]],final))
hdr="%-14s %8s %9s %9s %8s %8s %11s"%("arm","shares","premium","paid","divs","basis","TOTAL")
print(hdr); print("-"*len(hdr))
res={}
for pp in ("OTM","ATM","ITM"):
    for cp in ("none","far","atm"):
        r=run(pp,cp); res[(pp,cp)]=r
        print("%-14s %8.0f %9.0f %9.0f %8.0f %8.2f %11.0f"%(f"{pp} / {cp}",r["shares"],r["prem"],r["paid"],r["divs"],r["basis"],r["total"]))
json.dump({f"{a}|{b}":v for (a,b),v in res.items()},open("results.json","w"))
print("\nskipped rolls (no mark): %s"%{f"{a}/{b}":v["skipped"] for (a,b),v in res.items() if v["skipped"]})
