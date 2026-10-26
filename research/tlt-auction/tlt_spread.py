# -*- coding: utf-8 -*-
"""Concentrate the week's puts on one expiry, or spread them across two or three?

Nik: "we should not write so many puts across one expiry, spread it out, so
concentration is not on one date."

Spreading diversifies the settlement date: a dip that reverses assigns only part of
the book. Against that, a further expiry has less delivery per unit of delta, which
is what killed monthly on NVDA. Tested on TLT, same rules otherwise.
"""
import json, math, datetime, statistics as st
exec(open("tlt_bands.py").read().split("def walk(")[0])

def expiriesFrom(d, n):
    """the next n listed expiries at least 2 days out"""
    t=(datetime.date.fromisoformat(d)+datetime.timedelta(days=2)).isoformat()
    out=[]
    for x in days:
        if x>=t and x not in out:
            out.append(x)
            if len(out)==n: break
    return out

def walk(sub, nExp):
    sh=float(START); lots=[[float(START), float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0
    assignEvents=[]
    for i,d in enumerate(sub):
        got=0.0
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]:
                    sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])]); got+=l["ct"]*100
                puts.remove(l)
        if got: assignEvents.append(got)
        exps=expiriesFrom(d, nExp)
        if not exps: break
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*fYieldRel(d)
        share=per/len(exps)
        S=close[d]
        for e in exps:
            T=max((datetime.date.fromisoformat(e)-datetime.date.fromisoformat(d)).days,1)/365
            v=rv[d]
            K=round(S/0.5)*0.5
            pd_=pdelta(S,K,T,v); ct=max(0,round(share/(pd_*100))) if pd_>0 else 0
            if ct: puts.append({"K":K,"ct":ct,"exp":e,"p":bs(S,K,T,v)})
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        mtm=S*held-basis+prem; peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    big=sorted(assignEvents)[-1] if assignEvents else 0
    p95=sorted(assignEvents)[int(len(assignEvents)*0.95)] if len(assignEvents)>20 else big
    return dict(sh=sh, net=prem+(Sx*held-basis), dd=dd, bp=(basis/held) if held else 0,
                big=big, p95=p95, ev=len(assignEvents))

wins=[i for i in range(0,len(FRI)-HOR)]
print("%d windows x %d weeks · TLT\n"%(len(wins),HOR))
print("%-28s %9s %9s %11s %12s %11s %11s"%("arm","shares","basis","net","worst DD","worst 1-day","95th pct"))
print("-"*96)
for n,lab in ((1,"all on nearest expiry"),(2,"split across 2 expiries"),(3,"split across 3 expiries")):
    rs=[walk(FRI[i:i+HOR],n) for i in wins]; k=len(rs)//2
    f=lambda key: sorted(r[key] for r in rs)[k]
    print("%-28s %9s %9s %11s %12s %11s %11s"%(lab,
        format(int(f("sh")),","), "$%.2f"%f("bp"), "$%s"%format(int(f("net")),","),
        "$%s"%format(int(f("dd")),","), format(int(f("big")),","), format(int(f("p95")),",")))
