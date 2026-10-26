# -*- coding: utf-8 -*-
"""Forward scenario test, Nik's own path (8 Oct 2026). NOT a backtest.

TLT: -10% to Apr 2027, +20% Apr-Dec 2027, +20% through 2028 (ends Jan 2029 = LEAP expiry).
IWM: -20% to Apr 2027, +17.5% to Oct 2027, +15% to Apr 2028, +20% to Jan 2029.
Daily moves are drawn in 5-day blocks from each fund's own last 5 years, then bent to
hit Nik's waypoints exactly, so the wiggle looks like the fund but the trend is his.
Fed: 8 meetings a year; the meeting day's move is doubled and option prices run +20%
the week before and fall back after. Weekly option price = 20-day actual vol x a
'richness' ratio that starts at today's (TLT 1.28, IWM 1.26) and fades to 1.05.
Book: 1,000 TLT (or 300 IWM, about the same money) + 2 LEAPs per 100 shares (Jan
2029 ATM) + 3 calls per 100 shares. Margin 3.03% on shares + LEAP cost. Assignment
is settled as a roll (pay the in-the-money amount). 400 paths each."""
import json,math,random,statistics as st,datetime,sys
from statistics import NormalDist
ND=NormalDist().cdf
R=0.037; MR=0.0303
def bs(S,K,T,v,q):
    if T<=1e-6: return max(0.0,S-K)
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-q+v*v/2)*T)/sq
    return S*math.exp(-q*T)*ND(d1)-K*math.exp(-R*T)*ND(d1-sq)
def solve(p,S,K,T,q):
    lo,hi=0.01,3
    for _ in range(80):
        m=(lo+hi)/2
        if bs(S,K,T,m,q)<p: lo=m
        else: hi=m
    return m
# trading calendar from 8 Oct 2026 to 19 Jan 2029
d=datetime.date(2026,10,8); CAL=[]
while d<=datetime.date(2029,1,19):
    if d.weekday()<5: CAL.append(d)
    d+=datetime.timedelta(days=1)
N=len(CAL)-1
FOMC=set()
for y in (2026,2027,2028):
    for m,dd in ((1,28),(3,18),(4,29),(6,17),(7,29),(9,16),(10,28),(12,9)):
        x=datetime.date(y,m,dd)
        while x.weekday()>=5: x+=datetime.timedelta(days=1)
        if CAL[0]<=x<=CAL[-1]: FOMC.add(CAL.index(x))
def idx(y,m,dd):
    x=datetime.date(y,m,dd); return min(range(len(CAL)),key=lambda i:abs((CAL[i]-x).days))
TK={"TLT":dict(S=76.92,q=0.0504,ratio=1.28,leap=(75,7.92),sh=1000,step=0.5,
               legs=[(idx(2027,4,8),0.90),(idx(2027,12,31),1.20),(N,1.20)]),
    "IWM":dict(S=277.70,q=0.0098,ratio=1.26,leap=(275,49.32),sh=300,step=1.0,
               legs=[(idx(2027,4,8),0.80),(idx(2027,10,8),1.175),(idx(2028,4,7),1.15),(N,1.20)])}
TL=(CAL[-1]-CAL[0]).days/365
for t,x in TK.items():
    c=[b["c"] for b in json.load(open(f"{t}_hist.json"))["bars"]]
    x["lr"]=[math.log(c[i+1]/c[i]) for i in range(len(c)-1)]
    x["liv"]=solve(x["leap"][1],x["S"],x["leap"][0],TL,x["q"])
def make_path(x,rng):
    lr=x["lr"]; out=[]
    while len(out)<N:
        i=rng.randrange(len(lr)-5); out+=lr[i:i+5]
    out=out[:N]
    for i in FOMC: out[i]*=2.0
    # bend each leg to hit the waypoint
    a=0; P=[x["S"]]; lvl=x["S"]
    for end,mult in x["legs"]:
        seg=out[a:end]; target=math.log(mult); adj=(target-sum(seg))/len(seg)
        for r in seg: lvl*=math.exp(r+adj); P.append(lvl)
        a=end
    return P
def iv_at(x,P,t):
    w=[math.log(P[i+1]/P[i]) for i in range(max(0,t-20),t)]
    rv=st.pstdev(w)*math.sqrt(252) if len(w)>5 else 0.15
    ratio=x["ratio"] if MODE=="stay" else 1.15 if MODE=="mid" else 1.05+(x["ratio"]-1.05)*math.exp(-t/40)
    fomc=1.2 if any(t<=f<t+6 for f in FOMC) else 1.0
    return max(0.05,rv*ratio*fomc), rv
def dyn(m):
    if m<=-0.10: return 0.2
    if m<0.05: return 0.3
    if m<0.15: return 0.5
    return 0.6
def calls(x,P,plan):
    sh=x["sh"]; step=x["step"]; tot=0.0; ph=[0.0]*len(x["legs"])
    ends=[e for e,_ in x["legs"]]
    def phase(t): return next(i for i,e in enumerate(ends) if t<e)
    def strike(S,v,kind,T):
        if kind=="atm": k=math.ceil(S/step-1e-9)*step
        elif kind=="p1": k=round(S*1.01/step)*step
        else: k=round(S*(1+v*math.sqrt(T))/step)*step
        return max(k,math.ceil(S/step-1e-9)*step)
    if plan=="none": return 0.0,ph
    if plan=="ladder": lines=[(0,3,[("atm",1)]),(1,4,[("p1",1)]),(2,6,[("p1",1)])]; n_line=sh*1.0
    else: lines=[(4,5,None)]; n_line=sh*3.0
    for off,td,mix in lines:
        t=off
        while t+td<=N:
            S=P[t]; iv,rv=iv_at(x,P,t); T=td*7/5/365
            if mix is None:
                m=P[t]/P[max(0,t-21)]-1
                a={"atm":1.0,"nike":0.3,"dyn":dyn(m),"sd":0.0}[plan]
                mix=[("atm",a),("sd",1-a)] if a<1 else [("atm",1)]
                cur=mix; mix=None
            else: cur=mix
            for kind,sharepart in cur:
                k=strike(S,rv,kind,T); n=n_line*sharepart
                v=n*(bs(S,k,T,iv,x["q"])-0.01)-n/100*0.65-n*max(0,P[t+td]-k)
                tot+=v; ph[phase(t)]+=v
            t+=td
    return tot,ph
PLANS=[("No calls","none"),("Your plan (ATM 3d, +1% 6d, +1% 8d)","ladder"),("All ATM weekly","atm"),
       ("NKE 30/70 at 1 SD","nike"),("NKE dynamic","dyn"),("All at 1 SD","sd")]
MODE=sys.argv[1] if len(sys.argv)>1 else "fade"
for t,x in TK.items():
    pass
    rng=random.Random(42); paths=[make_path(x,rng) for _ in range(400)]
    S0=x["S"]; sh=x["sh"]; K,lp=x["leap"]; money=sh*S0+2*sh*lp
    yrs=TL
    base=[sh*(P[-1]-S0)+sh*S0*x["q"]*yrs+2*sh*(max(0,P[-1]-K)-lp)-money*MR*yrs for P in paths]
    print(f"\n{t}: {S0} -> {paths[0][-1]:.2f} by Jan 2029, {sh:,} shares + {2*sh//100} LEAPs + {3*sh//100} calls, money in ${money:,.0f}")
    print(f"   no calls: shares {sh*(paths[0][-1]-S0):+,.0f}, LEAPs {2*sh*(max(0,paths[0][-1]-K)-lp):+,.0f}, dividends-margin {sh*S0*x['q']*yrs-money*MR*yrs:+,.0f}")
    names=["drop" if m<1 else f"+{(m-1)*100:.1f}%" for _,m in x["legs"]]
    for nm,pl in PLANS:
        r=[calls(x,P,pl) for P in paths]; c=sorted(a for a,_ in r)
        tot=st.median(b+a for b,(a,_) in zip(base,r))
        phs=[st.median(p[i] for _,p in r) for i in range(len(names))]
        print(f"   {nm:36} total {tot:+9,.0f} ({tot/money*100:+4.0f}%)  calls {st.median(c):+9,.0f} [{c[40]:+,.0f} .. {c[360]:+,.0f}]  by phase: "+" ".join(f"{n} {v:+,.0f}" for n,v in zip(names,phs)))
