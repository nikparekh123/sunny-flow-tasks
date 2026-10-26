# -*- coding: utf-8 -*-
"""Hold unwritten budget and spend it on a drop, instead of forcing it out on a calendar.

Nik: "the slice is what did not get executed, we should hold those for a good price."
The same shape lost badly on NVDA (-$53,890 to -$143,704): writing into a drop is
writing into the condition where the stock most often bounces back above the strike,
so delivery fell and capital doubled. TLT is a different animal, mean reverting around
a yield at a quarter of the vol, so it gets its own test.

Reservoir accrues the weekly budget. It spends when TLT is down TRIG% over the last
five sessions, and a backstop forces it out once it exceeds CAP weeks of budget so it
cannot sit unspent forever.
"""
import json, csv, math, datetime, statistics as st
exec(open("tlt_bands.py").read().split("def walk(")[0])

def walk(sub, trig, capWk):
    """trig=None is the current behaviour: write the slice every expiry."""
    sh=float(START); lots=[[float(START), float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0; res=0.0; fired=0; forced=0
    for i,d in enumerate(sub):
        exp=nf(d)
        if not exp: break
        S,v,T=close[d],rv[d],7/365
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*fYieldRel(d)
        if trig is None:
            spend=per
        else:
            res+=per
            j=days.index(d)
            ref=close[days[max(0,j-5)]]
            drop=100*(S/ref-1)
            if drop<=-trig: spend=res; res=0.0; fired+=1
            elif res>=capWk*per and per>0: spend=res; res=0.0; forced+=1
            else: spend=0.0
        K=round(S/0.5)*0.5
        pd_=pdelta(S,K,T,v); ct=max(0,round(spend/(pd_*100))) if pd_>0 else 0
        if ct: puts.append({"K":K,"ct":ct,"exp":exp,"p":bs(S,K,T,v)})
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        mtm=S*held-basis+prem; peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    return dict(sh=sh, net=prem+(Sx*held-basis), dd=dd,
                bp=(basis/held) if held else 0, fired=fired, forced=forced)

wins=[i for i in range(0,len(FRI)-HOR)]
print("%d windows x %d weeks · TLT\n"%(len(wins),HOR))
print("%-34s %9s %9s %11s %12s %8s"%("arm","shares","basis","net","worst DD","fired"))
print("-"*88)
def run(label,trig,cap):
    rs=[walk(FRI[i:i+HOR],trig,cap) for i in wins]; n=len(rs)//2
    sh=sorted(r["sh"] for r in rs); nt=sorted(r["net"] for r in rs)
    bp=sorted(r["bp"] for r in rs); dd=sorted(r["dd"] for r in rs)
    fi=st.mean(r["fired"] for r in rs); fo=st.mean(r["forced"] for r in rs)
    print("%-34s %9s %9s %11s %12s %8s"%(label,format(int(sh[n]),","),"$%.2f"%bp[n],
      "$%s"%format(int(nt[n]),","),"$%s"%format(int(dd[n]),","),
      "%.0f+%.0f"%(fi,fo) if trig else "-"))
run("write every expiry (today)",None,0)
for t in (1,2,3):
    run("hold, spend on -%d%% in 5d (cap 4wk)"%t,t,4)
run("hold, spend on -2%% (cap 8wk)",2,8)
