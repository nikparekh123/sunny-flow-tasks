import json,math,datetime
from statistics import NormalDist
H=json.load(open("tlt_hist.json")); bars={b["d"]:b["c"] for b in H["bars"]}
days=sorted(bars); DIV=[(x["ex"],x["amount"]) for x in H["dividends"]]
plan=json.load(open("plan.json"))["plan"]; OB=json.load(open("opt_bars.json"))
R=0.045; N=NormalDist()
mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=(b["c"],b.get("v",0))
def occ(exp,cp,K): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(K*1000)))
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
def cbefore(d):
    best=None
    for x in days:
        if x<=d: best=x
        else: break
    return bars[best]
def pf(S): return 2.5 if S<75 else 1.5 if S<80 else 0.75 if S<85 else 0.25
BASE=846; CEIL=400_000
DELTA_FLOOR,DELTA_CEIL,TIE_ABS,TIE_REL=0.25,0.70,0.03,0.15
rolls=sorted(plan)

def pick_ext(d,S,v,exp,T):
    """the deployed rule: rank tradeable strikes by extrinsic inside a delta band,
       then take the LOWEST strike within a tie of the best."""
    base=round(S*2)/2; cands=[]
    for off in [x*0.5 for x in range(-4,4)]:
        K=base+off
        m=mark.get((occ(exp,"P",K),d))
        if not m or m[0]<=0: continue
        px=m[0]; intr=max(0,K-S); extr=px-intr
        dl=pdelta(S,K,T,v)
        if extr<=0 or dl<DELTA_FLOOR or dl>DELTA_CEIL: continue
        cands.append((K,px,intr,extr,dl))
    if not cands: return None
    best=max(c[3] for c in cands); tie=max(TIE_ABS,TIE_REL*best)
    return min([c for c in cands if c[3]>=best-tie],key=lambda c:c[0])

def run(pol,w0="0000",w1="9999"):
    shares=cash=prem=paid=recv=divs=extr_tot=0.0; openp=[]; skip=0; bought=0.0
    divq=sorted(DIV)
    for d in [x for x in rolls if w0<=x<=w1]:
        r=plan[d]; S=r["S"]; v=r["v"]; exp=r["exp"]; T=7/365
        for leg in list(openp):
            if leg["exp"]<=d:
                px=cbefore(leg["exp"])
                if px<leg["K"]: shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
                openp.remove(leg)
        while divq and divq[0][0]<=d: divs+=divq.pop(0)[1]*shares
        if pol=="EXT":
            c=pick_ext(d,S,v,exp,T)
            if c is None: skip+=1; continue
            K,px,intr,extr,dl=c
        else:
            K=r["put"][pol]; m=mark.get((occ(exp,"P",K),d))
            if not m or m[0]<=0: skip+=1; continue
            px=m[0]; intr=max(0,K-S); extr=px-intr; dl=pdelta(S,K,T,v)
        want=max(0,round(BASE*pf(S)/(dl*100))) if dl>0 else 0
        out=sum(l["K"]*100*l["ct"] for l in openp)
        ct=min(want,int((CEIL-out)//(K*100)))
        if ct>0:
            prem+=px*100*ct; extr_tot+=extr*100*ct; openp.append({"K":K,"ct":ct,"exp":exp})
    for leg in openp:
        px=cbefore(leg["exp"])
        if px<leg["K"]: shares+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100; bought+=leg["ct"]*100
    while divq: divs+=divq.pop(0)[1]*shares
    fin=bars[max(x for x in days if x<=w1)] if w1!="9999" else bars[days[-1]]
    return dict(shares=shares,prem=prem,extr=extr_tot,paid=paid,divs=divs,bought=bought,
                basis=(paid/bought if bought else 0),total=shares*fin+prem-paid+recv+divs,skip=skip)

W=[("FULL  2024-07 -> 2026-08   91.6 -> 82.2  (down)","0000","9999"),
   ("RALLY 2025-06 -> 2026-02   85.2 -> 90.8  (up)","2025-06-01","2026-02-27"),
   ("FALL  2026-03 -> 2026-08   89.6 -> 82.2  (down)","2026-03-01","9999")]
for title,w0,w1 in W:
    print("\n"+"="*84); print(title+"   · no calls, delta budget held constant"); print("="*84)
    hdr="%-6s %8s %9s %9s %8s %8s %11s"%("policy","shares","premium","EARNED","divs","basis","TOTAL")
    print(hdr); print("-"*len(hdr))
    for pol in ("OTM","ATM","ITM","EXT"):
        r=run(pol,w0,w1)
        star=" <-" if pol=="EXT" else ""
        print("%-6s %8.0f %9.0f %9.0f %8.0f %8.2f %11.0f%s"%(pol,r["shares"],r["prem"],r["extr"],r["divs"],r["basis"],r["total"],star))
