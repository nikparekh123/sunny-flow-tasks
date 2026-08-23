import math,random,statistics
from statistics import NormalDist
N=NormalDist(); random.seed(11)
S0=82.05; COST0=82.48; BLOCK=10000; IV=0.11; R=0.045
TD=85                      # trading days, 24 Aug -> 24 Dec
def bs(S,K,T,v,cp):
    if T<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return (S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2)) if cp=="C" \
      else (K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1))
def bridge(Tend,n,vol=0.10):
    dt=1/252.0; x=math.log(S0); xT=math.log(Tend); p=[S0]
    for i in range(1,n+1):
        x += (xT-x)/(n-i+1) + vol*math.sqrt(dt)*random.gauss(0,1) - (vol*vol/2)*dt
        p.append(math.exp(x))
    p[-1]=Tend; return p
def k_near(S):                       # nearest half-dollar, ties UP  (82.01->82, 84.25->84.5)
    return math.floor(S*2+0.5)/2.0
def k_above(S):                      # first half-dollar strictly above spot (82.01->82.5)
    k=math.floor(S*2)/2.0
    return k+0.5 if k<=S else k

def run(term,call_td,put_gap,strike_fn,paths=500,put_ct=100,floor_on=True,spread=0.01):
    out=[]
    for _ in range(paths):
        p=bridge(term,TD)
        sh=BLOCK; credit=0.0; sharecash=0.0; cost=0.0
        fl_n=(BLOCK//100 + put_ct) if floor_on else 0
        fl_k=k_near(S0)
        fcost=bs(S0,fl_k,TD/252,IV,"P")*fl_n*100 if floor_on else 0.0
        ev={}                                        # trading-day -> list of legs settling
        t=0
        while t<TD:
            S=p[t]
            ce=min(TD,t+call_td); pe=min(TD,t+call_td+put_gap)
            nc=max(0,sh//100)
            if nc:
                Kc=strike_fn(S)
                credit += bs(S,Kc,(ce-t)/252,IV,"C")*nc*100
                cost += nc*spread*100
                ev.setdefault(ce,[]).append(("C",Kc,nc))
                sh -= 0                                # shares only move at expiry
            Kp=k_near(S)
            credit += bs(S,Kp,(pe-t)/252,IV,"P")*put_ct*100
            cost += put_ct*spread*100
            ev.setdefault(pe,[]).append(("P",Kp,put_ct))
            t+=call_td
            for d in sorted(k for k in ev if k<=t):
                for typ,K,n in ev.pop(d):
                    Sx=p[d]
                    if typ=="C" and Sx>K:
                        n=min(n,sh//100)
                        if n>0: sharecash += K*n*100; sh -= n*100
                    elif typ=="P" and Sx<K:
                        sharecash -= K*n*100; sh += n*100
        for d in sorted(ev):
            for typ,K,n in ev[d]:
                Sx=p[min(d,TD)]
                if typ=="C" and Sx>K:
                    n=min(n,sh//100)
                    if n>0: sharecash += K*n*100; sh -= n*100
                elif typ=="P" and Sx<K: sharecash -= K*n*100; sh += n*100
        fpay=max(0.0,fl_k-term)*fl_n*100 if floor_on else 0.0
        share=sharecash+sh*term-BLOCK*COST0
        out.append({"credit":credit,"cost":cost,"floor":fpay-fcost,"share":share,
                    "tot":credit-cost+fpay-fcost+share,"sh":sh})
    return {k:statistics.median(x[k] for x in out) for k in ("credit","cost","floor","share","tot","sh")}

def usd(x): return ("-$" if x<-0.5 else "$")+"{:,.0f}".format(abs(x))
print("Calls weekly on shares held. 100 puts every week, one expiry further out (Fri call, Mon put).")
print("Floor = shares/100 + 100 puts sold. Start 10,000 at $82.48, spot $82.05. Median of 500 paths.\n")
for fn,lbl in ((k_near,"CALL AT NEAREST STRIKE   (82.01 -> 82.00)"),
               (k_above,"CALL AT NEXT STRIKE ABOVE (82.01 -> 82.50)")):
    print("== %s =="%lbl)
    print("%5s %12s %12s %12s %12s %10s %12s"%("TLT","credit","floor net","share P&L","TOTAL","shares","vs holding"))
    for term in range(78,86):
        r=run(term,5,1,fn)
        print("%5d %12s %12s %12s %12s %10s %12s"%(term,usd(r["credit"]),usd(r["floor"]),
              usd(r["share"]),usd(r["tot"]),"{:,.0f}".format(r["sh"]),usd(r["tot"]-BLOCK*(term-COST0))))
    print()
