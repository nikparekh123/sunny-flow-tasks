import json,datetime,statistics
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
P=json.load(open("plan.json"))["plan"]; BARS=json.load(open("opt_bars.json"))
def usd(x): return "${:,.0f}".format(x)
def occ(exp,cp,k): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(k*1000)))
def bar(c,d):
    v=BARS.get(c)
    if not v: return None
    for b in v:
        if b.get("d")==d: return b
    return None
def spot_at(d):
    xs=[x for x in days if x<=d]
    return close[xs[-1]] if xs else None

SPREAD=[0.00,0.01,0.02]      # per leg, per share, paid on entry only (held to expiry)
def run(arm,rolls):
    out=[];skipped=0
    for r in rolls:
        d,exp,S=r["d"],r["exp"],r["S"]
        pick=None
        for k in r["ks"]:
            cb,pb=bar(occ(exp,"C",k),d),bar(occ(exp,"P",k),d)
            if cb and pb and cb.get("c") and pb.get("c"):
                cand=(abs(k-S),k,cb["c"],pb["c"])
                if pick is None or cand<pick: pick=cand
        if pick is None: skipped+=1; continue
        _,k,cP,pP=pick
        Sx=spot_at(exp)
        if Sx is None: skipped+=1; continue
        prem=cP+pP                      # per share
        settle=abs(Sx-k)                # straddle intrinsic at expiry
        out.append({"d":d,"exp":exp,"dte":r["dte"],"k":k,"S":S,"Sx":Sx,
                    "prem":prem,"settle":settle,"net":prem-settle})
    return out,skipped

yrs=(datetime.date.fromisoformat(days[-1])-datetime.date.fromisoformat("2024-09-09")).days/365.25
print("window 2024-09-09 -> %s  (%.2f yrs)   TLT %.2f -> %.2f"%(days[-1],yrs,close["2024-09-09"],close[days[-1]]))
print()
print("Per 100 shares (one straddle a roll). Real Polygon marks, held to expiry.")
print("%-10s %6s %7s %9s %9s %9s %8s"%("arm","rolls","med dte","gross/yr","settle/yr","NET/yr","win%"))
res={}
for arm,rolls in P.items():
    o,sk=run(arm,rolls); res[arm]=o
    if not o: continue
    g=sum(x["prem"] for x in o)*100/yrs
    s=sum(x["settle"] for x in o)*100/yrs
    n=sum(x["net"] for x in o)*100/yrs
    win=100*sum(1 for x in o if x["net"]>0)/len(o)
    print("%-10s %6d %7.1f %9s %9s %9s %7.0f%%"%(arm,len(o),statistics.median(x["dte"] for x in o),
          usd(g),usd(s),usd(n),win))
print()
print("Net per year after spread, scaled to a 10,000-share block (100 straddles):")
print("%-10s %12s %12s %12s"%("arm","spread $0.00","spread $0.01","spread $0.02"))
for arm,o in res.items():
    if not o: continue
    row=[]
    for sp in SPREAD:
        n=sum(x["net"]-2*sp for x in o)*100/yrs*100
        row.append(usd(n))
    print("%-10s %12s %12s %12s"%(arm,*row))
json.dump({k:v for k,v in res.items()},open("res.json","w"))
