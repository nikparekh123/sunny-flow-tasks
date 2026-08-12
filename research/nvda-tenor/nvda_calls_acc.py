# -*- coding: utf-8 -*-
"""Do calls fight the accumulation target?

nvda_collar2 answered a DIFFERENT question: it held the share path fixed and rolled
every call, so the block could never leave and the only cost was the roll debit. That
is the right test of "does the overwrite pay for the floor" and the wrong one for
"should I write calls while building a block", because the thing that would hurt --
shares called away that must then be re-bought -- was defined out of existence.

Here the share path is ENDOGENOUS: the accumulation runs the live model (bounded
chase, MA100 dial, weekly 1% OTM puts) and calls are allowed to take shares.
"""
import json, math, datetime, statistics, urllib.request, time
from statistics import NormalDist
H=json.load(open("nvda_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}
days=sorted(close); R,N=0.045,NormalDist()
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)
ma={days[i]: sum(close[d] for d in days[i-99:i+1])/100 for i in range(99,len(days))}
FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4 and d in rv and d in ma]
def nextfri(d):
    t=(datetime.date.fromisoformat(d)+datetime.timedelta(days=7)).isoformat()
    l=[x for x in days if x>=t]; return l[0] if l else None
def occ(exp,cp,K): return "O:NVDA%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(K*1000)))
def kput(S):  return round(S*0.99/2.5)*2.5
def kcall(S,v,T,dl):
    d1=N.inv_cdf(dl)                      # MINUS -- the sign bug the collar run caught
    return round(S*math.exp((R+v*v/2)*T-d1*v*math.sqrt(T))/2.5)*2.5
CALL_DELTA=0.30

need=set(); rows=[]
for d in FRI:
    exp=nextfri(d)
    if not exp: break
    S,v,T=close[d],rv[d],7/365
    kp,kc=kput(S),kcall(S,v,T,CALL_DELTA)
    rows.append({"d":d,"exp":exp,"S":S,"v":v,"kp":kp,"kc":kc})
    for o in (0,-2.5,2.5,-5,5):  need.add(occ(exp,"P",kp+o))
    for o in (0,2.5,5,-2.5,-5):  need.add(occ(exp,"C",kc+o))
try: OB=json.load(open("nvda_optc.json"))
except Exception: OB={}
todo=sorted(need-set(OB)); print("rolls",len(rows),"| contracts to fetch",len(todo),flush=True)
K_="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
for i in range(0,len(todo),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K_,"apikey":K_,"Content-Type":"application/json"})
    try:
        r=json.load(urllib.request.urlopen(rq,timeout=400)); OB.update(r.get("bars") or {})
    except Exception as e: print("  chunk",i,"failed",e,flush=True)
    if i%600==0: print("  fetched",i,"/",len(todo),flush=True); json.dump(OB,open("nvda_optc.json","w"))
    time.sleep(0.25)
json.dump(OB,open("nvda_optc.json","w"))
print("cached contracts",len(OB),flush=True)

mark={}
for c,bl in OB.items():
    for b in bl or []: mark[(c,b["d"])]=b["c"]
def px(exp,cp,K,d,offs):
    for o in offs:
        m=mark.get((occ(exp,cp,K+o),d))
        if m and m>0: return K+o,m
    return None,None
BANDS=[(-11.2,2.50),(-3.3,1.50),(0,1.00),(float('inf'),0.60)]
def mafac(S,m):
    p=(S/m-1)*100
    for hi,f in BANDS:
        if p<hi: return f
    return 0.60
def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
START,TARGET,HOR=1500,15000,72
BASE=(TARGET-START)/HOR
COVER=0.50

def run(sub,mode):
    sh=float(START); paid=prem=debit=proceeds=0.0; called=0.0
    puts=[]; calls=[]
    for i,r in enumerate(sub):
        d,exp,S,v,T=r["d"],r["exp"],r["S"],r["v"],7/365
        for l in list(puts):
            if l["exp"]<=d:
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; paid+=l["K"]*l["ct"]*100
                puts.remove(l)
        for l in list(calls):
            if l["exp"]<=d:
                Sx=close[l["exp"]]
                if Sx>l["K"]:
                    if mode=="roll": debit+=(Sx-l["K"])*l["ct"]*100          # keep the block
                    else:
                        take=min(sh,l["ct"]*100); sh-=take; called+=take      # let it go
                        proceeds+=l["K"]*take
                calls.remove(l)
        # --- puts: the live sizing rule ---
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*mafac(S,ma[d])
        K,m=px(exp,"P",r["kp"],d,(0,-2.5,2.5,-5,5))
        if K:
            dl=pdelta(S,K,T,v)
            ct=max(0,round(per/(dl*100))) if dl>0 else 0
            if ct: prem+=m*100*ct; puts.append({"K":K,"ct":ct,"exp":exp})
        # --- calls: covered by shares actually held, less what is already written ---
        if mode!="none":
            room=max(0,math.floor((sh*COVER-sum(l["ct"]*100 for l in calls))/100))
            if room:
                Kc,mc=px(exp,"C",r["kc"],d,(0,2.5,5,-2.5,-5))
                if Kc: prem+=mc*100*room; calls.append({"K":Kc,"ct":room,"exp":exp})
    net=paid-prem+debit-proceeds
    return dict(sh=round(sh),called=round(called),prem=round(prem),debit=round(debit),
                basis=net/max(1,sh-START) if sh>START else float('nan'),net=round(net))

wins=[i for i in range(0,len(rows)-HOR)]
print("\n== %d windows of %d weeks, start 1,500 -> target 15,000, calls %.2f delta @ %d%% cover =="
      %(len(wins),HOR,CALL_DELTA,COVER*100))
h="%-16s %9s %9s %11s %11s %10s"%("arm","med shares","called","med basis","premium","roll debit")
print(h); print("-"*len(h))
for mode,label in (("none","no calls"),("roll","calls, rolled"),("assign","calls, assigned")):
    rs=[run(rows[i:i+HOR],mode) for i in wins]
    sh=sorted(r["sh"] for r in rs); bs=sorted(r["basis"] for r in rs)
    print("%-16s %9s %9s %11s %11s %10s"%(label,
        format(sh[len(sh)//2],","),format(int(statistics.median(r["called"] for r in rs)),","),
        "$%.2f"%bs[len(bs)//2],
        "$%s"%format(int(statistics.median(r["prem"] for r in rs)),","),
        "$%s"%format(int(statistics.median(r["debit"] for r in rs)),",")))
