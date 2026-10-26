# -*- coding: utf-8 -*-
"""PUTS ONLY. How far ahead should each daily slice reach for its expiry?

Nik's idea: a slice written Monday into Friday is a 4-day contract, Wednesday into
Friday is 2 days, Friday into Friday is nothing. So instead of everyone aiming at the
same Friday, each write reaches N expiries ahead, and the book naturally holds a
rotation of expiry dates.

Expiries are the Mon/Wed/Fri grid both tickers list.
  N=1  the very next expiry        N=2  the one after that       N=3  third out ...

Cash-capped at $400,000 of open commitment for BOTH tickers, sliced a fifth a day, so
NVDA and TLT are compared on the same money rather than the same contract count.
No calls anywhere in this.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; CAP=400_000.0; SLICE=CAP/5

def load(p, start):
    b=json.load(open(p))["bars"]
    D=[x["d"] for x in b]; RAW=[x["c"] for x in b]
    ret=[RAW[i+1]/RAW[i]-1 for i in range(len(RAW)-1)]
    return D, ret, start

def bsput(S,K,T,v):
    if T<=0: return max(0.0,K-S), (1.0 if S<K else 0.0)
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)

def run(D, ret, start, nth, step, lo, hi, trig='daily', ctCap=0, ctSlice=0):
    N=len(D); WD=[datetime.date.fromisoformat(x).weekday() for x in D]
    lr=[math.log(1+x) for x in ret]
    EXP=[i for i in range(N) if WD[i] in (0,2,4)]          # Mon / Wed / Fri
    P=[start]*N
    for i in range(lo+1,min(hi+1,N)): P[i]=P[i-1]*(1+ret[i-1])
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.08, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.30
    def nthExp(i,n):
        if n<=0:
            f=[j for j in range(i+1,N) if WD[j]==4]
            return f[0] if f else None
        c=[j for j in EXP if j>i]
        return c[n-1] if len(c)>=n else None
    prem=cost=0.0; sh=0; open_=[]; commit=[]; ten=[]; wrote=0
    for i in range(lo,hi):
        for L in list(open_):
            if L[0]<=i:
                if P[L[0]]<L[1]: sh+=L[2]*100; cost+=L[1]*L[2]*100
                open_.remove(L)
        out=sum(l[1]*100*l[2] for l in open_)
        commit.append(out)
        if WD[i]>4: continue
        if trig=='red2':
            if i-lo<2 or ret[i-1]>=0 or ret[i-2]>=0: continue
        elif trig=='fri':
            if WD[i]!=4: continue
        j=nthExp(i,nth)
        if j is None or j>=hi: continue
        S=P[i]; K=round(S/step)*step
        if ctCap:
            openCt=sum(l[2] for l in open_)
            ct=min(ctSlice, max(0, ctCap-openCt))
        else:
            free=max(0.0, CAP-out)
            room=min(SLICE, free)
            ct=int(room//(K*100))
            if ct==0 and free>=K*100: ct=1
        if ct<=0: continue
        T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365
        px,_=bsput(S,K,T,vol(i))
        prem+=px*100*ct; open_.append((j,K,ct)); wrote+=1
        ten.append((datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days)
    yrs=(hi-lo)/252
    tape=st.mean(P[lo:hi])
    basis=(cost-prem)/sh if sh else 0
    return dict(prem=prem/yrs, invest=st.mean(commit), basis=basis, tape=tape, cap=CAP,
                vs=100*(basis-tape)/tape if sh else 0, ten=st.mean(ten) if ten else 0,
                fills=sh/yrs, wrote=wrote/yrs)

WIN=504
def agg(D,ret,start,step,nth,trig,cap,sl):
    N=len(D); out=[]
    for s0 in range(70,N-WIN-40,25):
        out.append(run(D,ret,start,nth,step,s0,s0+WIN,trig,cap,sl))
    m=lambda k: st.mean([o[k] for o in out])
    return dict(prem=m('prem'), invest=m('invest'), basis=m('basis'), vs=m('vs'), ten=m('ten'))

D,ret,_ = load("nvda_long.json",225.0)
print("NVDA with the LIVE constraint: 15 contracts max open, 3 a day.\n")
print("  %-34s %7s %13s %13s %16s"%("expiry each slice reaches for","tenor","premium/yr","avg invested","avg price paid"))
print("  "+"-"*88)
for lab,n in (("nearest Friday  (live now)",0),("2 expiries out",2),("3 expiries out",3),("4 expiries out",4)):
    r=agg(D,ret,225.0,2.5,n,"daily",15,3)
    print("  %-34s %5.0f d %13s %13s %10s (%+.1f%%)"%(lab,round(r['ten']),
        "$"+format(round(r['prem']),","), "$"+format(round(r['invest']),","),
        "$"+format(r['basis'],",.2f"), r['vs']))
print()
print("  If a longer contract just fills the 15-contract cap and stops you writing,")
print("  premium goes DOWN not up, and the cash-capped test was misleading.")
