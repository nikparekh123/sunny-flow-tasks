# -*- coding: utf-8 -*-
"""FORWARD test of the call split on the book names (Nik, 9 Oct 2026). Not a backtest.
Four made-up years per name: keeps falling -25%, sideways, his thesis (-10% over 3
months, then up to +20% for the year), strong rally +40%. Daily moves are drawn in
5-day blocks from each name's own history and bent to hit the path. Earnings every
13 weeks: that day's move is one of the name's 8 biggest past days, and option prices
run 1.5x into it. Weekly option price = 20-day actual vol x richness, starting at
today's (live chain IV / 30-day actual, capped 1.4) and fading to 1.05 over ~2 months.
Every arm writes one Friday-to-Friday call per LEAP; earnings weeks drop the at-the-
money share to 20% in the split arms (the sheet's rule). Result: the calls' P&L as %
of the stock's value over the year. 300 paths per name per scenario."""
import json,math,random,statistics as st
from statistics import NormalDist
ND=NormalDist().cdf; R=0.037
def bs(S,K,T,v):
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R+v*v/2)*T)/sq
    return S*ND(d1)-K*math.exp(-R*T)*ND(d1-sq)
LIVE=json.load(open("live_iv.json"))
NAMES=["NKE","BABA","NFLX","LULU","FIS","PEP","KR"]
D=252
SC=[("Keeps falling -25%",[(D,0.75)]),("Sideways",[(D,1.0)]),
    ("Your thesis: -10% then +20%",[(63,0.90),(D,1.20/0.90)]),("Strong rally +40%",[(D,1.40)])]
def dyn(m):
    if m<=-0.10: return 0.2
    if m<0.05: return 0.3
    if m<0.15: return 0.5
    return 0.6
def arm_split(arm,m,earn):
    if arm=="all ATM": return [("atm",1.0,0)]
    if arm=="old (dynamic, 1 SD)": a=0.2 if earn else dyn(m); return [("atm",a,0),("otm",1-a,1.0)]
    if arm=="fixed 30/70, 1 SD": a=0.2 if earn else 0.3; return [("atm",a,0),("otm",1-a,1.0)]
    a=0.2 if earn else 1/3; out=1.0 if m>=0.15 else 0.6
    return [("atm",a,0),("otm",1-a,out)]
ARMS=["old (dynamic, 1 SD)","fixed 30/70, 1 SD","NEW (1/3 ATM, 0.6 SD)","all ATM"]
def run():
    res={(s,a):[] for s,_ in SC for a in ARMS}; per={}
    for t in NAMES:
        c=[x["c"] for x in json.load(open(f"{t}_hist.json"))["bars"]]
        lr=[math.log(c[i+1]/c[i]) for i in range(len(c)-1)]
        big=sorted(lr,key=abs)[-8:]
        rv30=st.pstdev(lr[-21:])*math.sqrt(252)
        rich0=min(1.4,LIVE[t]["iv"]/rv30); S0=LIVE[t]["S"]
        step=0.5 if S0<100 else 1.0
        rng=random.Random(hash(t)%1000)
        for sname,legs in SC:
            for _ in range(300):
                ret=[]
                while len(ret)<D:
                    i=rng.randrange(len(lr)-5); ret+=lr[i:i+5]
                ret=ret[:D]; off=rng.randrange(13)
                earn_days={off*5+2+65*q for q in range(4) if off*5+2+65*q<D}
                for e in earn_days: ret[e]=rng.choice(big)
                P=[S0]; a=0; lvl=S0
                for end,mult in legs:
                    seg=ret[a:end]; adj=(math.log(mult)-sum(seg))/len(seg)
                    for r in seg: lvl*=math.exp(r+adj); P.append(lvl)
                    a=end
                acc={x:0.0 for x in ARMS}
                for t0 in range(0,D-5,5):
                    S=P[t0]; w=[math.log(P[i+1]/P[i]) for i in range(max(0,t0-20),t0)]
                    rv=st.pstdev(w)*math.sqrt(252) if len(w)>5 else rv30
                    rich=1.05+(rich0-1.05)*math.exp(-t0/40)
                    earn=any(t0<=e<t0+5 for e in earn_days)
                    iv=max(0.08,rv*rich*(1.5 if earn else 1.0)); T=7/365
                    sd=S*iv*math.sqrt(T); m=S/P[max(0,t0-21)]-1
                    katm=math.ceil(S/step-1e-9)*step
                    for arm in ARMS:
                        for kind,sh,out in arm_split(arm,m,earn):
                            k=katm if kind=="atm" else max(katm+step,round((S+out*sd)/step)*step)
                            acc[arm]+=sh*((bs(S,k,T,iv)-0.01)-max(0,P[t0+5]-k))/S0
                for arm in ARMS:
                    res[(sname,arm)].append(acc[arm]*100); per.setdefault((t,sname,arm),[]).append(acc[arm]*100)
    return res,per
res,per=run()
print(f"{'calls P&L, % of stock value, 1 year':38}"+"".join(f"{s:>30}" for s,_ in SC))
for a in ARMS:
    print(f"  {a:36}"+"".join(f"{st.median(res[(s,a)]):>+20.1f}% (bad {sorted(res[(s,a)])[len(res[(s,a)])//10]:+5.1f}%)" for s,_ in SC))
print("\nNKE only")
for a in ARMS:
    print(f"  {a:36}"+"".join(f"{st.median(per[('NKE',s,a)]):>+20.1f}%{'':13}" for s,_ in SC))
print("\nNEW minus OLD, median by name (thesis scenario):",
      {t: round(st.median(per[(t,SC[2][0],ARMS[2])])-st.median(per[(t,SC[2][0],ARMS[0])]),1) for t in NAMES})
