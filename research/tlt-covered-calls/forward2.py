# -*- coding: utf-8 -*-
"""Fewer calls / further out, and shares vs long calls (Nik, 7 Oct 2026).

Same 12-month scenarios as forward.py, option prices fading back to realised
+0.5pt over ~2 months. The weekly smile is the live Oct 14 chain (7 Oct closes),
so far-out calls are priced at what they actually fetch, not at the ATM vol.
LEAPs priced off their own 7 Oct closes; at year end revalued at the same vol.
Everything funded on margin at 3.03%.
"""
import math,random,statistics as st
from statistics import NormalDist
ND=NormalDist().cdf
S0=76.92; R=0.037; Q=0.0504; MR=0.0303; DAYS=252
def bs(S,K,T,v):
    if T<=0: return max(0,S-K)
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-Q+v*v/2)*T)/sq
    return S*math.exp(-Q*T)*ND(d1)-K*math.exp(-R*T)*ND(d1-sq)
def delta(S,K,T,v):
    sq=v*math.sqrt(T); d1=(math.log(S/K)+(R-Q+v*v/2)*T)/sq; return math.exp(-Q*T)*ND(d1)
def solve(px,K,T,S=S0):
    lo,hi=0.005,1.5
    for _ in range(80):
        m=(lo+hi)/2
        if bs(S,K,T,m)<px: lo=m
        else: hi=m
    return m
# live weekly smile, Oct 14 expiry, by strike distance above spot
W={77:0.54,77.5:0.36,78:0.19,78.5:0.11,79:0.06,79.5:0.04,80:0.03}
SM=[(K/S0-1, solve(p,K,7/365)) for K,p in W.items()]
ATM_IV=solve(0.575,77.0,7/365)
def smile(m):      # vol premium over ATM at moneyness m
    if m<=SM[0][0]: return SM[0][1]-ATM_IV
    for (a,va),(b,vb) in zip(SM,SM[1:]):
        if m<=b: return va+(vb-va)*(m-a)/(b-a)-ATM_IV
    return SM[-1][1]-ATM_IV
T29=(2029-2026)*365/365+ (19-280)/365   # 19 Jan 2029
T29=834/365
LEAP={75:7.92,60:17.80}
LIV={k:solve(p,k,T29) for k,p in LEAP.items()}
SCEN=[("Calm, flat",0.00,0.10),("Fed eases +15%",0.15,0.13),("QE +30%",0.30,0.18),("Inflation -15%",-0.15,0.15)]
def path(drift,vol,rng):
    mu=math.log(1+drift)/DAYS; s=vol/math.sqrt(DAYS); S=[S0]
    for _ in range(DAYS): S.append(S[-1]*math.exp(mu-s*s/2+s*rng.gauss(0,1)))
    adj=(S0*(1+drift)/S[-1])**(1/DAYS)
    return [x*adj**i for i,x in enumerate(S)]
def overlay(S,vol,lines):
    """lines: list of (start_day, contracts, $ above the ATM strike)"""
    c=0.0
    for start,n,off in lines:
        if not n: continue
        for t in range(start,DAYS-5,5):
            K=round(S[t]*2)/2
            if K<S[t]-0.25: K+=0.5
            K+=off
            atm=vol+0.005+(ATM_IV-vol-0.005)*math.exp(-t/40)
            iv=max(0.03,atm+smile(K/S[t]-1))
            p=bs(S[t],K,7/365,iv)
            c+=n*100*(p-0.01)-n*0.65-n*100*max(0,S[t+5]-K)
    return c
def hold(S,kind):
    """15,000 share-equivalents of cover. kind: shares / L75 / L60"""
    sh=15000 if kind=="shares" else 5000
    v=sh*(S[-1]-S0)+sh*S0*(Q-MR)
    if kind!="shares":
        k=int(kind[1:]); p0=LEAP[k]; p1=bs(S[-1],k,T29-1,LIV[k])
        v+=10000*(p1-p0)-10000*p0*MR
    return v
OVER={
 "No calls":                      [],
 "150 calls, plan (ATM/+$0.5)":   [(0,50,0),(2,50,0.5),(4,50,0.5)],
 "150 calls, $1 up":              [(0,50,1),(2,50,1),(4,50,1)],
 "150 calls, $2 up":              [(0,50,2),(2,50,2),(4,50,2)],
 "100 calls, plan strikes":       [(2,50,0.5),(4,50,0.5)],
 "100 calls, $1 up":              [(2,50,1),(4,50,1)],
 "50 calls, ATM":                 [(0,50,0)],
 "50 calls, $1 up":               [(0,50,1)],
}
N=1500
def table(kinds,overs):
    rows={}
    for si,(nm,dr,vol) in enumerate(SCEN):
        rng=random.Random(11+si); paths=[path(dr,vol,rng) for _ in range(N)]
        for kd in kinds:
            base=[hold(S,kd) for S in paths]
            for o in overs:
                tot=sorted(b+overlay(S,vol,OVER[o]) for b,S in zip(base,paths))
                rows.setdefault((kd,o),[]).append((st.median(tot),tot[N//10]))
    return rows
if __name__=="__main__":
    print(f"weekly IV: ATM {ATM_IV*100:.1f}%, smile "+" ".join(f"{K}:{v*100:.1f}" for (m,v),K in zip(SM,W)))
    print("LEAP IV "+" ".join(f"{k}C {v*100:.1f}% delta {delta(S0,k,T29,v):.2f}" for k,v in LIV.items()))
    rows=table(["shares"],list(OVER))
    print("\nA. 15,000 SHARES: median 12-month P&L (shares + dividends - margin + calls)")
    print(f"{'':30}"+"".join(f"{s[0]:>17}" for s in SCEN))
    for (kd,o),v in rows.items():
        print(f"{o:30}"+"".join(f"{m:>+17,.0f}" for m,_ in v))
    import sys
    pick=sys.argv[1:] or ["No calls","150 calls, plan (ATM/+$0.5)","100 calls, $1 up"]
    rows=table(["shares","L75","L60"],pick)
    print("\nB. SHARES vs LONG CALLS for the extra 10,000 (median, and bad-case 10th pct)")
    print(f"{'':44}"+"".join(f"{s[0]:>24}" for s in SCEN))
    nmK={"shares":"15k shares","L75":"5k sh + 100 Jan29 75C","L60":"5k sh + 100 Jan29 60C"}
    for (kd,o),v in rows.items():
        print(f"{nmK[kd]+' | '+o:44}"+"".join(f"{m:>+12,.0f} ({lo:>+9,.0f})" for m,lo in v))
