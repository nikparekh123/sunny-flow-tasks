# -*- coding: utf-8 -*-
"""No shares, just weekly ATM puts, added in tranches (Nik, 7 Oct 2026).

Real put bars, 9 Sep 2024 to 7 Oct 2026. Three lines (Mon/Wed/Fri), each a
7-day ATM put written at its expiry. Tranches: +10 contracts a week, split across
the lines, up to 150. PURE = assignment settled at the close (you never keep
shares). KEEP = assigned shares are kept and count toward the 15,000; puts shrink
as shares arrive. Compared with 15,000 shares bought at once, or 1,000 a week.
"""
import json,datetime,math
H=json.load(open("tlt_hist.json")); bars={b["d"]:b for b in H["bars"]}; days=sorted(bars)
DIV={x["ex"]:x["amount"] for x in H["dividends"]}
OPX={c:{b["d"]:b["c"] for b in v} for c,v in json.load(open("put_bars.json")).items()}
PLAN=json.load(open("plan.json")); MR=0.0303
def D(s): return datetime.date.fromisoformat(s)
def occ(exp,k): return "O:TLT%sP%08d"%(D(exp).strftime("%y%m%d"),int(round(k*1000)))
START="2024-09-06"
writes={(r["d"],ln):r for ln,v in PLAN.items() for r in v}
def target(d):           # contracts allowed in total at date d, ramped
    w=(D(d)-D(START)).days//7; return min(150,10*(w+1))
def run(mode,ramp=True):
    cash=0.0; sh=0; open_={}; prem=pay=0.0; n_ass=0; P0=bars[START]["c"]
    if mode=="BLOCK": cash=-15000*P0; sh=15000
    prev=START
    for d in days[days.index(START)+1:]:
        b=bars[d]
        if cash<0: cash-= -cash*MR*(D(d)-D(prev)).days/365
        if d in DIV: cash+=sh*DIV[d]
        if mode=="WEEKLY1000" and D(d).weekday()==0 and sh<15000:
            n=min(1000,15000-sh); cash-=n*b["c"]; sh+=n
        if mode in ("PURE","KEEP"):
            for ln,o in list(open_.items()):
                if o["exp"]==d:
                    if b["c"]<o["K"]:
                        n=o["n"]*100; n_ass+=1
                        if mode=="PURE": cash-=n*(o["K"]-b["c"]); pay+=n*(o["K"]-b["c"])
                        else: cash-=n*o["K"]; sh+=n; pay+=n*(o["K"]-b["c"])
                    del open_[ln]
            tgt=target(d) if ramp else 150
            for ln in ("MON","WED","FRI"):
                r=writes.get((d,ln))
                if not r: continue
                others=sum(o["n"] for l,o in open_.items() if l!=ln)
                room=tgt-others-(sh//100 if mode=="KEEP" else 0)
                n=max(0,min(50,math.ceil(tgt/3),room))
                if n==0: continue
                S=b["c"]; K=round(S*2)/2
                p=OPX.get(occ(r["exp"],K),{}).get(d)
                if p is None:
                    for off in (0.5,-0.5):
                        q=OPX.get(occ(r["exp"],K+off),{}).get(d)
                        if q is not None: p=max(0.01,q+(-off)*0.5); break   # crude: half a strike step
                if p is None: continue
                got=n*100*(p-0.01)-n*0.65; cash+=got; prem+=got
                open_[ln]={"exp":r["exp"],"K":K,"n":n}
        prev=d
    end=days[-1]; S=bars[end]["c"]; liab=0
    for o in open_.values():
        p=OPX.get(occ(o["exp"],o["K"]),{}).get(end); liab+=o["n"]*100*(p if p is not None else max(0,o["K"]-S))
    return cash+sh*S-liab,prem,pay,n_ass,sh
print(f"TLT {bars[START]['c']} -> {bars[days[-1]]['c']}  ({START} to {days[-1]})\n")
for nm,args in [("15,000 shares at once",("BLOCK",)),("Shares, 1,000 a week",("WEEKLY1000",)),
                ("Puts only, 150 at once",("PURE",False)),("Puts only, +10 a week",("PURE",True)),
                ("Puts, keep assigned shares, +10 a week",("KEEP",True))]:
    eq,prem,pay,na,sh=run(*args)
    extra=f"  premium {prem:,.0f}  paid out {pay:,.0f}  assigned {na}x  shares at end {sh:,}" if prem else ""
    print(f"{nm:40} P&L {eq:+11,.0f}{extra}")
