import json,datetime,statistics
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
P=json.load(open("plan.json"))["plan"]; BARS=json.load(open("opt_bars.json"))
def usd(x): return "${:,.0f}".format(x)
def occ(e,cp,k): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(e).strftime("%y%m%d"),cp,int(round(k*1000)))
def bar(c,d):
    v=BARS.get(c)
    if not v: return None
    for b in v:
        if b.get("d")==d: return b
    return None
def spot_at(d):
    xs=[x for x in days if x<=d]; return close[xs[-1]] if xs else None
def yrs(a,b): return (datetime.date.fromisoformat(b)-datetime.date.fromisoformat(a)).days/365.25

def run(rolls):
    out=[];sk=0
    for r in rolls:
        d,e,S=r["d"],r["exp"],r["S"]; best=None
        for k in r["ks"]:
            cb,pb=bar(occ(e,"C",k),d),bar(occ(e,"P",k),d)
            if cb and pb and cb.get("c") and pb.get("c"):
                c=(abs(k-S),k,cb["c"],pb["c"])
                if best is None or c<best: best=c
        Sx=spot_at(e)
        if best is None or Sx is None: sk+=1; continue
        _,k,cP,pP=best
        out.append({"d":d,"exp":e,"dte":r["dte"],"k":k,"prem":cP+pP,
                    "settle":abs(Sx-k),"net":cP+pP-abs(Sx-k)})
    return out,sk

RES={a:run(r) for a,r in P.items()}
WIN=[("FULL   flat-to-down","2024-09-09","2026-08-21"),
     ("TREND  -11% leg     ","2024-09-09","2025-01-31"),
     ("RANGE  88->86 chop  ","2025-07-01","2026-06-30"),
     ("RECENT 2026 ytd     ","2026-01-01","2026-08-21")]
ORDER=["EVERY_EXP","WEEKLY","BIWEEKLY","MONTHLY"]

print("Real Polygon marks. ATM straddle per 100 shares, held to expiry, rolled on expiry.")
print("Coverage:", ", ".join("%s %d/%d"%(a,len(RES[a][0]),len(P[a])) for a in ORDER))
for lbl,a0,b0 in WIN:
    y=yrs(a0,b0); s0,s1=spot_at(a0),spot_at(b0)
    print("\n== %s  %s -> %s   TLT %.2f -> %.2f (%+.1f%%) =="%(lbl,a0,b0,s0,s1,100*(s1/s0-1)))
    print("%-10s %5s %7s %10s %10s %10s %6s"%("arm","n","med dte","gross/yr","settle/yr","NET/yr","win%"))
    for a in ORDER:
        o=[x for x in RES[a][0] if a0<=x["d"]<=b0]
        if len(o)<4: print("%-10s %5d   too few rolls to read"%(a,len(o))); continue
        g=sum(x["prem"] for x in o)*100/y; st=sum(x["settle"] for x in o)*100/y
        n=sum(x["net"] for x in o)*100/y; w=100*sum(1 for x in o if x["net"]>0)/len(o)
        print("%-10s %5d %7.1f %10s %10s %10s %5.0f%%"%(a,len(o),statistics.median(x["dte"] for x in o),
              usd(g),usd(st),usd(n),w))

print("\n== NET per year on a 10,000-share block (100 straddles), after entry spread ==")
print("%-10s %13s %13s %13s"%("arm","$0.00/leg","$0.01/leg","$0.02/leg"))
y=yrs("2024-09-09","2026-08-21")
for a in ORDER:
    o=RES[a][0]
    print("%-10s %13s %13s %13s"%(a,*[usd(sum(x["net"]-2*sp for x in o)*100/y*100) for sp in (0.0,0.01,0.02)]))
