# -*- coding: utf-8 -*-
"""Should a single day be allowed to write the whole week's budget?

The $400K ceiling caps TOTAL outstanding, about 48 contracts at 82.50. It does not
stop one day filling all of it. This measures what a per-write cap costs and what it
buys, on top of the 3-expiry split.
"""
import json, math, datetime, statistics as st
exec(open("tlt_bands.py").read().split("def walk(")[0])
def expiriesFrom(d, n):
    t=(datetime.date.fromisoformat(d)+datetime.timedelta(days=2)).isoformat()
    out=[]
    for x in days:
        if x>=t and x not in out:
            out.append(x)
            if len(out)==n: break
    return out

def walk(sub, nExp, dayCap):
    sh=float(START); lots=[[float(START), float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0; perDay=[]; capped=0
    for i,d in enumerate(sub):
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        exps=expiriesFrom(d,nExp)
        if not exps: break
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*fYieldRel(d)
        S=close[d]; K=round(S/0.5)*0.5
        T0=max((datetime.date.fromisoformat(exps[0])-datetime.date.fromisoformat(d)).days,1)/365
        pd0=pdelta(S,K,T0,rv[d])
        want=max(0,round(per/(pd0*100))) if pd0>0 else 0
        out=sum(l["K"]*100*l["ct"] for l in puts)
        room=int(max(0.0,400000-out)//(K*100))
        ct=min(want,room, dayCap if dayCap else 10**9)
        if ct<want: capped+=1
        if ct: perDay.append(ct)
        # deal the contracts out across the expiries
        base,extra=divmod(ct,len(exps))
        for j,e in enumerate(exps):
            n=base+(1 if j<extra else 0)
            if not n: continue
            T=max((datetime.date.fromisoformat(e)-datetime.date.fromisoformat(d)).days,1)/365
            puts.append({"K":K,"ct":n,"exp":e,"p":bs(S,K,T,rv[d])})
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        mtm=S*held-basis+prem; peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    return dict(sh=sh, net=prem+(Sx*held-basis), dd=dd, bp=(basis/held) if held else 0,
                mx=max(perDay) if perDay else 0, capped=capped)

wins=[i for i in range(0,len(FRI)-HOR)]
print("%d windows, 3-expiry split, varying the per-write cap\n"%len(wins))
print("%-22s %9s %9s %11s %12s %10s %9s"%("cap","shares","basis","net","worst DD","max/day","capped wks"))
print("-"*88)
for cap,lab in ((None,"none (today)"),(30,"30 contracts"),(20,"20 contracts"),(15,"15 contracts"),(10,"10 contracts")):
    rs=[walk(FRI[i:i+HOR],3,cap) for i in wins]; k=len(rs)//2
    f=lambda key: sorted(r[key] for r in rs)[k]
    print("%-22s %9s %9s %11s %12s %10d %9d"%(lab,format(int(f("sh")),","),"$%.2f"%f("bp"),
      "$%s"%format(int(f("net")),","),"$%s"%format(int(f("dd")),","),f("mx"),f("capped")))
