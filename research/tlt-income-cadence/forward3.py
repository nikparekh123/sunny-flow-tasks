import math,random,statistics
from statistics import NormalDist
N=NormalDist(); random.seed(11)
S0=82.05; COST0=82.48; BLOCK=10000; IV=0.11; R=0.045; DAYS=122
def bs(S,K,T,v,cp):
    if T<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return (S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2)) if cp=="C" \
      else (K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1))
def bridge(Tend,n,vol):
    dt=1/252.0; x=math.log(S0); xT=math.log(Tend); p=[S0]
    for i in range(1,n+1):
        x += (xT-x)/(n-i+1) + vol*math.sqrt(dt)*random.gauss(0,1) - (vol*vol/2)*dt
        p.append(math.exp(x)); 
    p[-1]=Tend; return p

def run(term,tenor,full_put,paths=500,floor_on=True):
    steps=max(1,DAYS//tenor); out=[]
    for _ in range(paths):
        p=bridge(term,steps,0.10)
        sh=BLOCK
        credit=0.0          # option premium collected, kept, never marked
        sharecash=0.0       # cash in/out from shares moving at exercise
        # floor = shares/100 + puts sold, Nik's rule
        fl_n=((BLOCK//100)+((BLOCK//100) if full_put else 0)) if floor_on else 0
        fl_k=round(S0*2)/2
        fcost=bs(S0,fl_k,DAYS/365,IV,"P")*fl_n*100 if floor_on else 0.0
        for i in range(steps):
            S=p[i]; Sx=p[i+1]; K=round(S*2)/2; T=tenor/365
            nc=max(0,sh//100)
            npu=(BLOCK//100) if full_put else max(0,(BLOCK-sh)//100)
            credit += (bs(S,K,T,IV,"C")*nc + bs(S,K,T,IV,"P")*npu)*100
            if Sx>K and nc:  sharecash += K*nc*100;  sh -= nc*100
            elif Sx<K and npu: sharecash -= K*npu*100; sh += npu*100
        fpay = max(0.0,fl_k-term)*fl_n*100 if floor_on else 0.0
        # share P&L = what the shares did, against the original basis
        share_pnl = sharecash + sh*term - BLOCK*COST0
        out.append({"credit":credit,"floor":fpay-fcost,"share":share_pnl,
                    "tot":credit+fpay-fcost+share_pnl,"sh":sh})
    return {k:statistics.median(x[k] for x in out) for k in ("credit","floor","share","tot","sh")}

def usd(x): return ("-$" if x<-0.5 else "$")+"{:,.0f}".format(abs(x))
print("TLT INCOME, four months to 24 Dec. Start 10,000 shares at $82.48 (basis $824,800), spot $82.05.")
print("Sell ATM calls and puts, let them EXERCISE, never buy back. Median of 500 realistic paths.")
print("Floor = shares/100 + puts sold, ATM four-month, bought at the start.")
print("One contract costs %s, so 100 = %s and 200 = %s.\n"%(usd(bs(S0,82.0,DAYS/365,IV,"P")*100),usd(bs(S0,82.0,DAYS/365,IV,"P")*100*100),usd(bs(S0,82.0,DAYS/365,IV,"P")*200*100)))
for full,lbl in ((False,"A. PUTS ONLY REFILL THE BLOCK"),(True,"B. FULL 100-PUT LEG EVERY CYCLE")):
    print("== %s =="%lbl)
    print("%5s %12s %12s %12s %12s %10s %12s"%("TLT","credit","floor net","share P&L","TOTAL","shares","vs holding"))
    for term in range(78,86):
        r=run(term,7,full)
        hold=BLOCK*(term-COST0)
        print("%5d %12s %12s %12s %12s %10s %12s"%(term,usd(r["credit"]),usd(r["floor"]),
              usd(r["share"]),usd(r["tot"]),"{:,.0f}".format(r["sh"]),usd(r["tot"]-hold)))
    print()
print("Reference: doing nothing at all, just holding the 10,000 shares.")
print("%5s %13s"%("TLT","hold-only"))
for term in range(78,86): print("%5d %13s"%(term,usd(BLOCK*(term-COST0))))
