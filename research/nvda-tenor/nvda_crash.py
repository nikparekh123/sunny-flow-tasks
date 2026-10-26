# -*- coding: utf-8 -*-
"""What does the accumulation programme do in a real NVDA crash?

Every parameter here was fitted on a rising NVDA. The data contains one genuine
bear: -66% from Nov 2021 to Oct 2022, 221 sessions. This runs the LIVE rules --
bounded chase, MA100 dial with the new 0.20x slow lane, 1% OTM, weekly Fridays --
straight through it, and reports what the ceiling and the drawdown actually do.
"""
exec(open("nvda_regime.py").read().split("# ── validation")[0])
CEILING = 400000.0

def walk(sub, label):
    sh=float(START); lots=[[float(START), float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0; maxOut=0.0; blocked=0
    for i,d in enumerate(sub):
        exp=nf(d)
        if not exp: break
        S,v,T=close[d],rv[d]*IVMULT,7/365
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*mafac(S,ma[d])
        K=round(S*0.99/2.5)*2.5
        pd_=pdelta(S,K,T,v); want=max(0,round(per/(pd_*100))) if pd_>0 else 0
        out=sum(l["K"]*100*l["ct"] for l in puts)
        room=max(0.0, CEILING-out)
        ct=min(want, int(room//(K*100)))
        if ct<want: blocked+=1
        if ct: puts.append({"K":K,"ct":ct,"exp":exp,"p":bs(S,K,T,v,"P")})
        out=sum(l["K"]*100*l["ct"] for l in puts); maxOut=max(maxOut,out)
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        mtm=S*held-basis+prem; peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    print("%-26s %8s %9s %11s %12s %10s %7s"%(label, format(int(sh),","), "$%.2f"%(basis/held if held else 0),
          "$%s"%format(int(prem+(Sx*held-basis)),","), "$%s"%format(int(dd),","),
          "$%.0fK"%(maxOut/1000), "%d wk"%blocked))

start = [i for i,d in enumerate(FRI) if d>="2021-11-26"][0]
print("%-26s %8s %9s %11s %12s %10s %7s"%("window","shares","basis","net","worst DD","peak cash","ceiling"))
print("-"*92)
walk(FRI[start:start+HOR], "into the -66% crash")
q = [i for i,d in enumerate(FRI) if d>="2024-05-24"][0]
walk(FRI[q:q+HOR], "the rally (for contrast)")
print()
sub=FRI[start:start+HOR]
print("  NVDA %.2f -> %.2f over the window (%+.0f%%)"%(close[sub[0]], close[sub[-1]], 100*(close[sub[-1]]/close[sub[0]]-1)))
