# -*- coding: utf-8 -*-
"""Does a longer floor pay in the crash the short one was never tested against?

The live floor is 75x 220 puts expiring 18 Sep -- about one month of cover on a
72-week programme. The earlier collar test priced a 10% floor rolled QUARTERLY at
-$263,448 over two years, but that ran through a rally, which is where insurance
always looks expensive. This runs the same structure through NVDA's real -66%.

Floor is 1:1 on shares HELD (Nik's OTM 1:1 structure), struck OTM_PCT below spot,
bought at the roll and rolled at expiry. Priced Black-Scholes on realised vol x
IVMULT, the same engine validated to within 3% on the real-mark window.
"""
exec(open("nvda_crash.py").read().split("def walk(")[0])
CEILING = 400000.0

def walk(sub, floorDays, otmPct, label):
    sh=float(START); lots=[[float(START), float(close[sub[0]])]]
    prem=0.0; puts=[]; peak=0.0; dd=0.0
    floor=None; floorPaid=0.0; floorBack=0.0; rolls=0
    for i,d in enumerate(sub):
        exp=nf(d)
        if not exp: break
        S,v,T=close[d],rv[d]*IVMULT,7/365
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        # ── the floor: settle then re-buy, sized to shares held ──
        if floorDays:
            if floor and d >= floor["exp"]:
                floorBack += max(0.0, floor["K"]-close[floor["exp"]]) * floor["q"]
                floor=None
            if floor is None:
                K=round(S*(1-otmPct)/2.5)*2.5
                Tf=floorDays/365
                px=bs(S,K,Tf,rv[d]*IVMULT,"P")
                q=sh
                tgt=(datetime.date.fromisoformat(d)+datetime.timedelta(days=floorDays)).isoformat()
                exf=[x for x in days if x>=tgt]
                if exf:
                    floor={"K":K,"q":q,"exp":exf[0]}; floorPaid += px*q; rolls+=1
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*mafac(S,ma[d])
        K=round(S*0.99/2.5)*2.5
        pd_=pdelta(S,K,T,v); want=max(0,round(per/(pd_*100))) if pd_>0 else 0
        out=sum(l["K"]*100*l["ct"] for l in puts)
        ct=min(want, int(max(0.0,CEILING-out)//(K*100)))
        if ct: puts.append({"K":K,"ct":ct,"exp":exp,"p":bs(S,K,T,v,"P")})
        basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
        # floor marked at intrinsic — conservative, ignores its remaining time value
        fv = max(0.0, floor["K"]-S)*floor["q"] if floor else 0.0
        mtm=S*held-basis+prem-floorPaid+floorBack+fv
        peak=max(peak,mtm); dd=min(dd,mtm-peak)
    Sx=close[sub[-1]]; basis=sum(q*p for q,p in lots); held=sum(q for q,_ in lots)
    fv = max(0.0, floor["K"]-Sx)*floor["q"] if floor else 0.0
    net = prem+(Sx*held-basis)-floorPaid+floorBack+fv
    print("%-24s %8s %11s %11s %11s %12s %6s"%(label, format(int(sh),","),
          "$%s"%format(int(floorPaid),","), "$%s"%format(int(floorBack+fv),","),
          "$%s"%format(int(net),","), "$%s"%format(int(dd),","), rolls))

def suite(sub, title):
    print("\n%s"%title)
    print("%-24s %8s %11s %11s %11s %12s %6s"%("floor","shares","paid","recovered","net","worst DD","rolls"))
    print("-"*90)
    walk(sub, 0, 0, "none")
    for dys,lab in ((30,"1 month"),(91,"3 months"),(182,"6 months"),(365,"12 months")):
        walk(sub, dys, 0.10, "%s, 10%% OTM"%lab)

end=[i for i,d in enumerate(FRI) if d>="2022-10-14"][0]
suite(FRI[max(0,end-HOR):end], "CRASH, no recovery  (2021-05 .. 2022-10)")
q=[i for i,d in enumerate(FRI) if d>="2024-05-24"][0]
suite(FRI[q:q+HOR], "RALLY  (2024-05 .. 2025-10)")
