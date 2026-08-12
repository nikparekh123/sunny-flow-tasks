# -*- coding: utf-8 -*-
"""Does letting calls assign actually cost you? Across regimes, not just rallies.

Every window in nvda_hist is a rally (min drift +22%), so "assignment costs you" was
drawn from data where holding shares wins by construction. This uses 2018-2026 -- which
contains real -37% and -16% windows -- with MODELLED option prices, validated first
against the real-mark window.
"""
import json, math, datetime, statistics
from statistics import NormalDist
H=json.load(open("nvda_long.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist()
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)
ma={days[i]: sum(close[d] for d in days[i-99:i+1])/100 for i in range(99,len(days))}
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv and d in ma]
def nf(d):
    t=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    l=[x for x in days if x>=t]; return l[0] if l else None
IVMULT=1.05                      # implied sits a touch over realised; see README
def bs(S,K,T,v,cp):
    if T<=0 or v<=0: return max(0.0,(S-K) if cp=="C" else (K-S))
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    if cp=="C": return S*N.cdf(d1)-K*math.exp(-R*T)*N.cdf(d2)
    return K*math.exp(-R*T)*N.cdf(-d2)-S*N.cdf(-d1)
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
def kcall(S,v,T,dl): return round(S*math.exp((R+v*v/2)*T-N.inv_cdf(dl)*v*math.sqrt(T))/2.5)*2.5
BANDS=[(-11.2,2.50),(-3.3,1.50),(0,1.00),(float('inf'),0.60)]
def mafac(S,m):
    p=(S/m-1)*100
    for hi,f in BANDS:
        if p<hi: return f
    return 0.60
START,TARGET,HOR=1500,15000,72
BASE=(TARGET-START)/HOR

def walk(sub,cov,mode,dl=0.50):
    sh=float(START); lots=[[float(START),float(close[sub[0]])]]
    prem=0.0; debit=0.0; stock_real=0.0; puts=[]; calls=[]
    for i,d in enumerate(sub):
        exp=nf(d)
        if not exp: break
        S,v,T=close[d],rv[d]*IVMULT,7/365
        for l in list(puts):
            if l["exp"]<=d:
                prem+=l["p"]*100*l["ct"]
                if close[l["exp"]]<l["K"]:
                    sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        for l in list(calls):
            if l["exp"]<=d:
                Sx=close[l["exp"]]; prem+=l["p"]*100*l["ct"]
                if Sx>l["K"]:
                    if mode=="roll": debit+=(Sx-l["K"])*l["ct"]*100
                    else:
                        take=min(sh,l["ct"]*100); sh-=take; left=take
                        while left>1e-9 and lots:
                            q,pz=lots[0]; use=min(q,left)
                            stock_real+=(l["K"]-pz)*use; lots[0][0]-=use; left-=use
                            if lots[0][0]<=1e-9: lots.pop(0)
                calls.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*mafac(S,ma[d])
        K=round(S*0.99/2.5)*2.5
        pd_=pdelta(S,K,T,v); ct=max(0,round(per/(pd_*100))) if pd_>0 else 0
        if ct: puts.append({"K":K,"ct":ct,"exp":exp,"p":bs(S,K,T,v,"P")})
        if cov>0:
            room=max(0,math.floor((sh*cov-sum(l["ct"]*100 for l in calls))/100))
            if room:
                Kc=kcall(S,v,T,dl)
                calls.append({"K":Kc,"ct":room,"exp":exp,"p":bs(S,Kc,T,v,"C")})
    Sx=close[sub[-1]]
    basis=sum(q*p for q,p in lots); heldq=sum(q for q,_ in lots)
    openp=sum(l["p"]*100*l["ct"] for l in puts+calls)
    return dict(net=prem-debit+stock_real+(Sx*heldq-basis)+openp, sh=sh, prem=prem, debit=debit)

# ── validation: the modelled engine on the real-mark window ────────────────────
val=[f for f in FRI if f>="2024-05-24"]
if len(val)>HOR:
    a=walk(val[:HOR],0.0,"none"); b=walk(val[:HOR],0.30,"assign")
    print("VALIDATION vs real marks (window from %s)"%val[0])
    print("  no calls  modelled NET $%-12s  real-mark NET $840,038   shares %s vs 13,800"%(
        format(int(a['net']),","),format(int(a['sh']),",")))
    print("  assigned  modelled NET $%-12s  real-mark NET $263,561   shares %s vs 1,000"%(
        format(int(b['net']),","),format(int(b['sh']),",")))
print()
rowsw=[]
for i in range(0,len(FRI)-HOR):
    sub=FRI[i:i+HOR]
    dr=close[sub[-1]]/close[sub[0]]-1
    rowsw.append((sub[0],dr,walk(sub,0.0,"none"),walk(sub,0.30,"assign"),walk(sub,0.30,"roll")))
def band(lo,hi,label):
    g=[r for r in rowsw if lo<=r[1]<hi]
    if not g: return
    def med(k): return statistics.median(r[k]['net'] for r in g)
    print("%-16s %4d %8s %13s %13s %13s"%(label,len(g),
      "%+.0f%%"%(100*statistics.median(r[1] for r in g)),
      "$%s"%format(int(med(2)),","),"$%s"%format(int(med(3)),","),"$%s"%format(int(med(4)),",")))
print("MEDIAN NET by regime, 72-week windows 2018-2026 (modelled prices)")
print("%-16s %4s %8s %13s %13s %13s"%("regime","n","drift","no calls","ATM assigned","ATM rolled"))
band(-1,0,"falling"); band(0,0.25,"flat to +25%"); band(0.25,0.75,"+25 to +75%"); band(0.75,99,"above +75%")
