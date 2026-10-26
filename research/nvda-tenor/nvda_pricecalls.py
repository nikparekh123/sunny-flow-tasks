# -*- coding: utf-8 -*-
"""Let the PRICE decide how hard you sell upside.

Nik: "Being bullish at 150 is different than at 220 and at 110. If I can pick up NVDA
at 120 I am happy to hold a while and sell 3% OTM vs ATM."

That is the MA100 dial the put engine already runs, mirrored onto the calls. Extended
above the mean, cap hard and take income, because that is where upside is least likely
and shares are dearest. Well below the mean, back off or stop, because those are the
shares worth keeping.

Compared against the best FIXED settings from the previous sweep.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; START=225.0; SH0=1000; TARGET=27500; WKS=104; CEIL=400000
b=json.load(open("nvda_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
def nxt(i,m):
    j=i+1
    while j<N:
        if WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=m: return j
        j+=1
    return None
def bs(S,K,T,v,put):
    a=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); sq=v*math.sqrt(T)
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)

# gap above the MA100, in %, -> (call strike offset, coverage %)
DIAL=[( 15,  0.00, 40),      # far above the mean: cap hard, upside is least likely here
      (  8,  0.03, 30),
      (  0,  0.06, 20),
      ( -5,  0.10, 12),
      (-99,  None,  0)]      # cheap: these are the shares worth keeping, no calls
def dialFor(g):
    for hi,off,cov in DIAL:
        if g>=hi: return off,cov
    return None,0

def sim(lo,hi,mode,fixOff=0.06,fixCov=15):
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.15, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.45
    def ma(i):
        w=[px(k) for k in range(max(lo,i-100),i)]
        return st.mean(w) if w else px(i)
    def streak(i,up):
        n=0
        while n<i-lo and ((ret[i-n-1]>0) if up else (ret[i-n-1]<0)): n+=1
        return n
    sh=SH0; prem=0.0; openP=[]; openC=[]
    for i in range(lo,hi):
        for L in list(openP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100
                openP.remove(L)
        for L in list(openC):
            if L[0]<=i:
                if px(L[0])>L[1]: sh-=L[2]*100
                openC.remove(L)
        wkLeft=max(1,WKS-(i-lo)/5); S=px(i); v=vol(i)
        if streak(i,False)>=2:
            j=nxt(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                K=S*0.99; p,dl=bs(S,K,T,v,True)
                ct=int(max(0.0,(TARGET-sh)/wkLeft)/(dl*100)) if dl>0 else 0
                out=sum(l[1]*100*l[2] for l in openP)
                ct=min(ct,int(max(0,CEIL-out)/(K*100)))
                if ct>0: prem+=p*100*ct; openP.append((j,K,ct))
        if streak(i,True)>=2:
            gap=100*(S/ma(i)-1)
            off,cov = dialFor(gap) if mode=="dial" else (fixOff,fixCov)
            if off is None or cov<=0: continue
            j=nxt(i,5)
            if j and j<hi:
                T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
                K=S*(1+off); p,dl=bs(S,K,T,v,False)
                oc=sum(l[2] for l in openC)
                ct=min(int(sh*(cov/100.0)/100.0)-oc, max(0,(sh-oc*100)//100))
                if ct>0: prem+=p*100*ct; openC.append((j,K,ct))
    return sh,prem,px(hi-1)/START-1
WIN=520;STEP=25
ARMS=[("no calls at all",            "fix", None, 0),
      ("fixed +6% OTM, 15% cover",   "fix", 0.06, 15),
      ("fixed +10% OTM, 15% cover",  "fix", 0.10, 15),
      ("fixed ATM, 15% cover",       "fix", 0.00, 15),
      ("PRICE DIAL (ATM high, none low)","dial", None, None)]
print("Start 1,000, target 27,500 in 104wk.  %d windows.\n"%len(range(70,N-WIN-40,STEP)))
print("%-34s %12s %11s %12s %11s"%("arm","end shares","premium","bearish shr","bearish $"))
print("-"*86)
for lab,mode,off,cov in ARMS:
    E=[];PR=[];DR=[]
    for s in range(70,N-WIN-40,STEP):
        sh,pr,dr=sim(s,s+WIN,mode,off if off is not None else 0.0, cov if cov is not None else 0)
        E.append(sh);PR.append(pr);DR.append(dr)
    dn=[(e,p) for e,p,x in zip(E,PR,DR) if x<0.5]
    print("%-34s %12s %11s %12s %11s"%(lab,format(round(st.mean(E)),","),
        "$"+format(round(st.mean(PR)/1000),",")+"k",
        format(round(st.mean([q[0] for q in dn])),","),
        "$"+format(round(st.mean([q[1] for q in dn])/1000),",")+"k"))
