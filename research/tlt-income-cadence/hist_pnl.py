import json,datetime
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
P=json.load(open("plan.json"))["plan"]; BARS=json.load(open("opt_bars.json"))
BLOCK=10000; SPREAD=0.01
def usd(x): return ("-$" if x<-0.5 else "$")+"{:,.0f}".format(abs(x))
def occ(e,cp,k): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(e).strftime("%y%m%d"),cp,int(round(k*1000)))
def bar(c,d):
    v=BARS.get(c); return next((b for b in v if b.get("d")==d),None) if v else None
def spot_at(d):
    xs=[x for x in days if x<=d]; return close[xs[-1]] if xs else None

def sim(rolls,full_put):
    sh=BLOCK; basis=close["2024-09-09"]; credit=0.0; sharecash=0.0; spread=0.0
    calls_ex=0; puts_ex=0; n=0
    for r in rolls:
        d,e,S=r["d"],r["exp"],r["S"]; best=None
        for k in r["ks"]:
            cb,pb=bar(occ(e,"C",k),d),bar(occ(e,"P",k),d)
            if cb and pb and cb.get("c") and pb.get("c"):
                c=(abs(k-S),k,cb["c"],pb["c"])
                if best is None or c<best: best=c
        Sx=spot_at(e)
        if best is None or Sx is None: continue
        _,K,cP,pP=best; n+=1
        nc=max(0,sh//100); npu=(BLOCK//100) if full_put else max(0,(BLOCK-sh)//100)
        credit += (cP*nc + pP*npu)*100
        spread += (nc+npu)*SPREAD*100
        if Sx>K and nc:   sharecash += K*nc*100;  sh -= nc*100;  calls_ex += nc*100
        elif Sx<K and npu: sharecash -= K*npu*100; sh += npu*100; puts_ex += npu*100
    end=close[days[-1]]
    share_pnl = sharecash + sh*end - BLOCK*basis
    return {"n":n,"credit":credit,"spread":spread,"share":share_pnl,
            "tot":credit-spread+share_pnl,"sh":sh,"cex":calls_ex,"pex":puts_ex}

start=close["2024-09-09"]; end=close[days[-1]]
hold=BLOCK*(end-start)
print("Real Polygon marks, 2024-09-09 to 2026-08-21. TLT %.2f -> %.2f."%(start,end))
print("Start 10,000 shares. Sell ATM calls and puts, let them EXERCISE. No floor in this table.")
print("Spread charged at 1c a leg.  Just holding the shares made %s.\n"%usd(hold))
for full,lbl in ((False,"A. PUTS ONLY REFILL THE BLOCK"),(True,"B. FULL 100-PUT LEG EVERY CYCLE")):
    print("== %s =="%lbl)
    print("%-11s %5s %13s %10s %13s %13s %9s %12s"%("cadence","rolls","credit","spread","share P&L","TOTAL","shares","vs holding"))
    for a in ["EVERY_EXP","WEEKLY","BIWEEKLY","MONTHLY"]:
        r=sim(P[a],full)
        print("%-11s %5d %13s %10s %13s %13s %9s %12s"%(a,r["n"],usd(r["credit"]),usd(r["spread"]),
              usd(r["share"]),usd(r["tot"]),"{:,.0f}".format(r["sh"]),usd(r["tot"]-hold)))
    print()
