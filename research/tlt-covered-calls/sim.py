# -*- coding: utf-8 -*-
"""Week-by-week test of Nik's TLT plan WITH SHARES (15,000 on margin, 150 calls).

Real TLT closes/opens, real dividends, real option bars (Polygon). 2024-09-09 to
2026-10-07. Lines: MON ATM, WED and FRI one strike up ($0.50). Each written at the
close of its expiry day for the same weekday a week out.

Assigned at expiry -> 5,000 shares go at the strike, rebought next morning at the
open (his rule: "let Monday exercise, rebuy Tuesday"). Day before ex-dividend, any
in-the-money call whose time value is under the dividend is assigned early; those
shares miss the dividend and are rebought at the ex-date open.
Margin 3.03% on the borrowed balance. Sell at bar close less 1c, $0.65 a contract,
shares half a cent each way.
"""
import json,datetime,math,sys
from statistics import NormalDist
ND=NormalDist().cdf
H=json.load(open("tlt_hist.json")); bars={b["d"]:b for b in H["bars"]}; days=sorted(bars)
DIV={x["ex"]:x["amount"] for x in H["dividends"]}
OB=json.load(open("opt_bars.json")); OPX={c:{b["d"]:b["c"] for b in v} for c,v in OB.items()}
PLAN=json.load(open("plan.json"))
GAPS=[]; ROLLS=[]
MR=0.0303; HALF=0.01; COM=0.65; SH_C=0.005; LINE=50
def D(s): return datetime.date.fromisoformat(s)
def occ(exp,k): return "O:TLT%sC%08d"%(D(exp).strftime("%y%m%d"),int(round(k*1000)))
def bs(S,K,T,v,r=0.04):
    if T<=0: return max(0,S-K)
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(r+v*v/2)*T)/sq
    return S*ND(d1)-K*math.exp(-r*T)*ND(d1-sq)
def ivof(px,S,K,T):
    lo,hi=0.01,2
    for _ in range(80):
        m=(lo+hi)/2
        if bs(S,K,T,m)<px: lo=m
        else: hi=m
    return m
def price(exp,K,d,S):
    """Real bar close on d; else price off the nearest strike with a bar that day."""
    p=OPX.get(occ(exp,K),{}).get(d)
    if p is not None: return p,True
    T=max(1,(D(exp)-D(d)).days)/365
    for off in (0.5,-0.5,1,-1,1.5,-1.5):
        q=OPX.get(occ(exp,K+off),{}).get(d)
        if q is not None and q>max(0,S-(K+off))+0.005:
            return bs(S,K,T,ivof(q,S,K+off,T)),False
    return None,False
def nextday(d):
    i=days.index(d); return days[i+1] if i+1<len(days) else None

def run(arm,ARM=""):
    # arm: dict line->strike offset in $0.50 steps, or None for HOLD
    start="2024-09-06"; S0=bars[start]["c"]
    sh=15000; cash=-sh*S0-sh*SH_C
    open_={}             # line -> {exp,K,n}
    rebuy={}             # date -> shares to buy at open
    log=[]; stats={"assign":0,"exdiv":0,"written":0,"modelled":0,"skipped":0,"prem":0.0,"give":0.0,"gap":0.0,"cost":0.0,"divmiss":0.0}
    writes={(r["d"],ln):r for ln,v in PLAN.items() for r in v}
    weekly={}
    prev=start
    for d in days[days.index(start)+1:]:
        b=bars[d]
        cash-= -min(cash,0)*MR*(D(d)-D(prev)).days/365 if cash<0 else 0
        # dividend: holders at the prior close, so before this morning's rebuys
        if d in DIV: cash+=sh*DIV[d]
        # morning rebuys
        n=rebuy.pop(d,0)
        if n:
            cash-=n*(b["o"]+SH_C); sh+=n; stats["cost"]+=n*SH_C
        # settle expiries at the close
        if arm:
            for ln,o in list(open_.items()):
                if o["exp"]==d:
                    if not o.get("idle") and b["c"]>o["K"]:
                        n=o["n"]*100; cash+=n*o["K"]; sh-=n; stats["assign"]+=1
                        ROLLS[o["roll"]]["pay"]=n*(b["c"]-o["K"]); stats["give"]+=n*(b["c"]-o["K"]); GAPS.append((d,ln,bars[nextday(d)]["o"]-b["c"] if nextday(d) else 0))
                        nd=nextday(d)
                        if nd: rebuy[nd]=rebuy.get(nd,0)+n; stats["gap"]+=n*(bars[nd]["o"]-b["c"])
                    del open_[ln]
            # early assignment the day before ex-dividend
            nd=nextday(d)
            if nd in DIV:
                for ln,o in list(open_.items()):
                    intr=b["c"]-o["K"]
                    if intr<=0: continue
                    p=OPX.get(occ(o["exp"],o["K"]),{}).get(d)
                    ext=(p-intr) if p is not None else 0.0
                    if ext<DIV[nd]:
                        n=o["n"]*100; cash+=n*o["K"]; sh-=n; stats["exdiv"]+=1; stats["assign"]+=1
                        stats["give"]+=n*intr; ROLLS[o["roll"]]["pay"]=n*intr+n*DIV[nd]; stats["gap"]+=n*(bars[nd]["o"]-b["c"]); stats["divmiss"]+=n*DIV[nd]
                        rebuy[nd]=rebuy.get(nd,0)+n
                        o["gone"]=True
                for ln in [l for l,o in open_.items() if o.get("gone")]:
                    open_[ln]={"exp":open_[ln]["exp"],"K":0,"n":0,"idle":True}
            # write
            for ln,off in arm.items():
                r=writes.get((d,ln))
                if not r: continue
                if ln in open_ and not open_[ln].get("idle"): continue
                S=b["c"]; K=round(S*2)/2+0.5*off
                if off==0 and abs(K-S)>0.25: K=round(S*2)/2
                p,real=price(r["exp"],K,d,S)
                if p is None: stats["skipped"]+=1; open_.pop(ln,None); continue
                stats["written"]+=1; stats["modelled"]+=0 if real else 1
                got=LINE*100*(p-HALF)-LINE*COM
                cash+=got; stats["prem"]+=got; stats["cost"]+=LINE*100*HALF+LINE*COM
                open_[ln]={"exp":r["exp"],"K":K,"n":LINE,"roll":len(ROLLS)}; ROLLS.append({"arm":ARM,"d":d,"ln":ln,"prem":got,"pay":0.0,"S":S,"K":K})
                wk=D(d).isocalendar()[:2]; weekly[wk]=weekly.get(wk,0)+got
        prev=d
    # mark at the end
    end=days[-1]; S=bars[end]["c"]; liab=0
    for ln,o in open_.items():
        if o.get("idle") or not o["n"]: continue
        p=OPX.get(occ(o["exp"],o["K"]),{}).get(end)
        liab+=o["n"]*100*(p if p is not None else max(0,S-o["K"]))
    for n in rebuy.values(): sh+=n; cash-=n*S
    eq=cash+sh*S-liab
    return eq,stats,S0,S
arms={"HOLD":None,"PLAN Mon ATM, Wed/Fri +1 strike":{"MON":0,"WED":1,"FRI":1},
      "ALL ATM":{"MON":0,"WED":0,"FRI":0},"ALL +1 strike":{"MON":1,"WED":1,"FRI":1}}
res={}
for nm,a in arms.items():
    eq,st,S0,S=run(a,nm); res[nm]=(eq,st)
yrs=(D(days[-1])-D("2024-09-06")).days/365
base=res["HOLD"][0]
print(f"TLT {S0:.2f} -> {S:.2f} over {yrs:.2f} years, 15,000 shares, margin 3.03%")
for nm,(eq,st) in res.items():
    print(f"\n{nm}\n  total P&L {eq:+,.0f}   vs HOLD {eq-base:+,.0f}  ({(eq-base)/yrs:+,.0f}/yr)")
    if st["written"]:
        print(f"  premium {st['prem']:,.0f}  given up at assignment {st['give']:,.0f}  overnight rebuy gap {st['gap']:+,.0f}  missed dividends {st['divmiss']:,.0f}")
        print(f"  writes {st['written']} (modelled {st['modelled']}, skipped {st['skipped']})  assignments {st['assign']} (ex-div {st['exdiv']})")
