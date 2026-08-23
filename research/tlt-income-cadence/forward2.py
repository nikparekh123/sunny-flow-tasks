import math,random,statistics
from statistics import NormalDist
N=NormalDist(); random.seed(11)
S0=82.05; COST0=82.48; BLOCK=10000
IV=0.11; R=0.045; DAYS=122                 # 2026-08-24 -> 2026-12-24
def bs(S,K,T,v,cp):
    if T<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return (S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2)) if cp=="C" \
      else (K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1))
def bridge(Tend,n,vol):
    dt=1/252.0; x=math.log(S0); xT=math.log(Tend); p=[S0]
    for i in range(1,n+1):
        x += (xT-x)/(n-i+1) + vol*math.sqrt(dt)*random.gauss(0,1) - (vol*vol/2)*dt
        p.append(math.exp(x))
    p[-1]=Tend; return p

def run(term,tenor,full_put,paths=500,floor_on=True):
    """full_put=True  -> sell 100 puts every cycle (the literal sleeve leg)
       full_put=False -> sell puts only to refill the block back to 10,000"""
    steps=max(1,DAYS//tenor); out=[]
    for _ in range(paths):
        p=bridge(term,steps,0.10)
        sh=BLOCK; cost_out=BLOCK*COST0        # cash basis of shares owned
        prem=0.0; share_cash=0.0
        fl_n=(BLOCK//100)*2 if floor_on else 0
        fl_k=round(S0*2)/2
        floor_cost=bs(S0,fl_k,DAYS/365,IV,"P")*fl_n*100 if floor_on else 0.0
        for i in range(steps):
            S=p[i]; Sx=p[i+1]; K=round(S*2)/2; T=tenor/365
            nc=max(0,sh//100)
            npu=(BLOCK//100) if full_put else max(0,(BLOCK-sh)//100)
            prem += (bs(S,K,T,IV,"C")*nc + bs(S,K,T,IV,"P")*npu)*100
            if Sx>K:
                if nc: share_cash += K*nc*100; sh -= nc*100          # called away at K
            elif Sx<K:
                if npu: share_cash -= K*npu*100; cost_out += K*npu*100; sh += npu*100
        floor_pay = max(0.0,fl_k-term)*fl_n*100 if floor_on else 0.0
        share_pnl = share_cash + sh*term - cost_out
        out.append({"prem":prem,"floor":floor_pay-floor_cost,"share":share_pnl,
                    "tot":prem+floor_pay-floor_cost+share_pnl,"sh":sh})
    return {k:statistics.median(x[k] for x in out) for k in ("prem","floor","share","tot","sh")}

def usd(x): return ("-$" if x<-0.5 else "$")+"{:,.0f}".format(abs(x))
print("TLT INCOME, four months to 24 Dec. Start 10,000 shares at $82.48, spot $82.05.")
print("Sell ATM calls and puts, let them exercise, never buy back.")
print("Floor: 200 ATM four-month puts, bought at the start. Median of 500 paths.\n")
for full,lbl in ((False,"PUTS REFILL THE BLOCK  (block stays near 10,000)"),
                 (True ,"FULL 100-PUT LEG       (block doubles when TLT falls)")):
    print("== %s =="%lbl)
    print("%5s %13s %12s %13s %13s %11s"%("TLT","credit","floor net","share P&L","TOTAL","shares end"))
    for term in range(78,86):
        r=run(term,7,full)
        print("%5d %13s %12s %13s %13s %11s"%(term,usd(r["prem"]),usd(r["floor"]),
              usd(r["share"]),usd(r["tot"]),"{:,.0f}".format(r["sh"])))
    print()
