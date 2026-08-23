import json,datetime,statistics,random
random.seed(7)
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
P=json.load(open("plan.json"))["plan"]; BARS=json.load(open("opt_bars.json"))
def usd(x): return "${:,.0f}".format(x)
def occ(e,cp,k): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(e).strftime("%y%m%d"),cp,int(round(k*1000)))
def bar(c,d):
    v=BARS.get(c); return next((b for b in v if b.get("d")==d),None) if v else None
def spot_at(d):
    xs=[x for x in days if x<=d]; return close[xs[-1]] if xs else None
def run(rolls):
    out=[]
    for r in rolls:
        d,e,S=r["d"],r["exp"],r["S"]; best=None
        for k in r["ks"]:
            cb,pb=bar(occ(e,"C",k),d),bar(occ(e,"P",k),d)
            if cb and pb and cb.get("c") and pb.get("c"):
                c=(abs(k-S),k,cb["c"],pb["c"])
                if best is None or c<best: best=c
        Sx=spot_at(e)
        if best is None or Sx is None: continue
        _,k,cP,pP=best
        out.append({"dte":r["dte"],"prem":cP+pP,"net":cP+pP-abs(Sx-k)})
    return out
YRS=(datetime.date.fromisoformat("2026-08-21")-datetime.date.fromisoformat("2024-09-09")).days/365.25
R={a:run(r) for a,r in P.items()}
ORDER=["EVERY_EXP","WEEKLY","BIWEEKLY","MONTHLY"]
print("Per 100 shares. Bootstrap 2,000 resamples of the roll set.\n")
print("%-10s %4s %8s %9s %8s %26s"%("arm","n","prem/leg","net/gross","NET/yr","95%% confidence interval"))
for a in ORDER:
    o=R[a]; n=len(o)
    g=sum(x["prem"] for x in o); net=sum(x["net"] for x in o)
    per=[x["net"] for x in o]
    bs=sorted(sum(random.choice(per) for _ in range(n))*100/YRS for _ in range(2000))
    lo,hi=bs[50],bs[1949]
    print("%-10s %4d %8s %8.1f%% %8s   %s to %s"%(a,n,"$%.2f"%(g/n/2),100*net/g,usd(net*100/YRS),usd(lo),usd(hi)))
print("\nA 1-cent spread costs 2 cents a straddle. As a share of the year's NET:")
for a in ORDER:
    o=R[a]; net=sum(x["net"] for x in o)*100/YRS; cost=len(o)*0.02*100/YRS
    print("  %-10s %3d rolls/yr  spread bill %8s   =%5.0f%% of net"%(a,round(len(o)/YRS),usd(cost),100*cost/net if net else 0))
