import math,random,statistics
from statistics import NormalDist
N=NormalDist(); random.seed(11)
S0=82.05; COST0=82.48; SH0=10000; TARGET=10000
IV=0.11; R=0.045; DAYS=122            # 2026-08-24 -> 2026-12-24
def bs(S,K,T,v,cp):
    if T<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    if cp=="C": return S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2)
    return K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1)
def bridge(T_end,n,vol):
    """Brownian bridge: realistic wiggle, pinned to the terminal price."""
    dt=1/252.0; path=[S0]; x=math.log(S0); xT=math.log(T_end)
    for i in range(1,n+1):
        rem=n-i+1
        drift=(xT-x)/rem
        x+= drift + vol*math.sqrt(dt)*random.gauss(0,1) - (vol*vol/2)*dt
        path.append(math.exp(x))
    path[-1]=T_end
    return path

def run(term,tenor,paths=400,floor_on=True):
    steps=DAYS//tenor
    tot=[]
    for _ in range(paths):
        p=bridge(term,steps,0.10)
        sh=SH0; basis=COST0; cash=0.0; called=0; putto=0
        # the floor: ATM 4-month, sized shares/100 + puts sold, bought once at the start
        fl_n = (SH0//100) + (SH0//100) if floor_on else 0
        fl_k = round(S0*2)/2
        cash -= bs(S0,fl_k,DAYS/365,IV,"P")*fl_n*100 if floor_on else 0
        for i in range(steps):
            S=p[i]; Sx=p[i+1]; K=round(S*2)/2; T=tenor/365
            nc=max(0,sh//100)                       # one call per 100 shares held
            npu=max(0,sh//100)                      # one put per 100 shares held
            cash += (bs(S,K,T,IV,"C")*nc + bs(S,K,T,IV,"P")*npu)*100
            if Sx>K and nc:                          # call exercises: shares leave at K
                cash += K*nc*100; called+=nc*100; sh-=nc*100
            elif Sx<K and npu:                       # put exercises: shares arrive at K
                cost=K*npu*100; cash-=cost; putto+=npu*100
                basis=(basis*sh+cost)/(sh+npu*100) if sh+npu*100 else K
                sh+=npu*100
        if floor_on: cash += max(0.0,fl_k-term)*fl_n*100
        equity = sh*term
        start_val = SH0*COST0
        tot.append({"pnl":cash+equity-start_val,"sh":sh,"called":called,"putto":putto})
    return {k:statistics.median(x[k] for x in tot) for k in ("pnl","sh","called","putto")}

def usd(x): return ("-$" if x<0 else "$")+"{:,.0f}".format(abs(x))
print("Start: 10,000 shares at $82.48, spot $82.05. Four months to 24 Dec.")
print("Sell 1 ATM call + 1 ATM put per 100 shares, let them exercise, never buy back.")
print("Floor on: 200 ATM 4-month puts. Median of 400 realistic paths per price.\n")
for tenor,nm in ((7,"WEEKLY 7d"),(2,"EVERY EXPIRY 2d")):
    print("== %s =="%nm)
    print("%6s %12s %12s %12s %10s"%("TLT","total P&L","shares end","called away","put to you"))
    for term in range(78,86):
        r=run(term,tenor)
        print("%6d %12s %12s %12s %10s"%(term,usd(r["pnl"]),"{:,.0f}".format(r["sh"]),
              "{:,.0f}".format(r["called"]),"{:,.0f}".format(r["putto"])))
    print()
