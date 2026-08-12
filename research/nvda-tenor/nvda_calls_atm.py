# -*- coding: utf-8 -*-
"""ATM but fewer, against far-but-many.

Nik's structure: on 5,000 shares sell 15-20 ATM calls, not 25 at 4% out. The claim
is that ATM collects enough per contract that you need fewer of them, and the shares
you leave uncapped are free for a wild run. That is a DIFFERENT trade from the one
collar2 and nvda_calls_acc tested, and the tension is obvious: an ATM call finishes
in the money about half the time, so the roll debit arrives far more often.

Share path endogenous, calls rolled (never assigned -- nvda_calls_acc showed assigning
destroys the programme regardless of strike).
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
def kcall(S,v,T,dl): return round(S*math.exp((R+v*v/2)*T-N.inv_cdf(dl)*v*math.sqrt(T))/2.5)*2.5
DELTAS=(0.50,0.40,0.30)
need=set(); rows=[]
for d in FRI:
    exp=nextfri(d)
    if not exp: break
    S,v,T=close[d],rv[d],7/365
    r={"d":d,"exp":exp,"S":S,"v":v,"kp":round(S*0.99/2.5)*2.5}
    for dl in DELTAS:
        r["kc%d"%int(dl*100)]=kcall(S,v,T,dl)
        for o in (0,2.5,5,-2.5,-5): need.add(occ(exp,"C",r["kc%d"%int(dl*100)]+o))
    for o in (0,-2.5,2.5,-5,5): need.add(occ(exp,"P",r["kp"]+o))
    rows.append(r)
try: OB=json.load(open("nvda_optc.json"))
except Exception: OB={}
todo=sorted(need-set(OB)); print("rolls",len(rows),"| to fetch",len(todo),flush=True)
K_="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/opt-history"
for i in range(0,len(todo),60):
    rq=urllib.request.Request(U,data=json.dumps({"contracts":todo[i:i+60],"from":"2024-06-01","to":"2026-08-12"}).encode(),
        headers={"Authorization":"Bearer "+K_,"apikey":K_,"Content-Type":"application/json"})
    try: OB.update(json.load(urllib.request.urlopen(rq,timeout=400)).get("bars") or {})
    except Exception as e: print("  chunk",i,"failed",e,flush=True)
    if i and i%600==0: json.dump(OB,open("nvda_optc.json","w")); print("  ",i,"/",len(todo),flush=True)
    time.sleep(0.25)
json.dump(OB,open("nvda_optc.json","w")); print("cached",len(OB),flush=True)

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

def run(sub,dl,cov):
    sh=float(START); paid=prem=debit=0.0; puts=[]; calls=[]; itm=0; tot=0; capped=[]
    for i,r in enumerate(sub):
        d,exp,S,v,T=r["d"],r["exp"],r["S"],r["v"],7/365
        for l in list(puts):
            if l["exp"]<=d:
                if close[l["exp"]]<l["K"]: sh+=l["ct"]*100; paid+=l["K"]*l["ct"]*100
                puts.remove(l)
        for l in list(calls):
            if l["exp"]<=d:
                Sx=close[l["exp"]]
                if Sx>l["K"]: debit+=(Sx-l["K"])*l["ct"]*100; itm+=1
                tot+=1; calls.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*mafac(S,ma[d])
        K,m=px(exp,"P",r["kp"],d,(0,-2.5,2.5,-5,5))
        if K:
            pd_=pdelta(S,K,T,v); ct=max(0,round(per/(pd_*100))) if pd_>0 else 0
            if ct: prem+=m*100*ct; puts.append({"K":K,"ct":ct,"exp":exp})
        if cov>0:
            room=max(0,math.floor((sh*cov-sum(l["ct"]*100 for l in calls))/100))
            if room:
                Kc,mc=px(exp,"C",r["kc%d"%int(dl*100)],d,(0,2.5,5,-2.5,-5))
                if Kc:
                    prem+=mc*100*room; calls.append({"K":Kc,"ct":room,"exp":exp})
                    capped.append(sum(l["ct"]*100 for l in calls)/max(1,sh))
    net=paid-prem+debit
    return dict(sh=round(sh),basis=net/max(1,sh-START),prem=prem,debit=debit,
                itm=itm/max(1,tot),cap=statistics.mean(capped) if capped else 0)

wins=[i for i in range(0,len(rows)-HOR)]
print("\n== %d windows x %d weeks · calls ROLLED · share path endogenous =="%(len(wins),HOR))
h="%-22s %8s %9s %10s %11s %9s %8s"%("structure","shares","basis","net prem","roll debit","ITM rate","capped")
print(h); print("-"*len(h))
def show(label,dl,cov):
    rs=[run(rows[i:i+HOR],dl,cov) for i in wins]
    sh=sorted(r["sh"] for r in rs); bs=sorted(r["basis"] for r in rs)
    p=statistics.median(r["prem"] for r in rs); dq=statistics.median(r["debit"] for r in rs)
    print("%-22s %8s %9s %10s %11s %8.0f%% %7.0f%%"%(label,format(sh[len(sh)//2],","),
      "$%.2f"%bs[len(bs)//2],"$%s"%format(int(p-dq),","),"$%s"%format(int(dq),","),
      100*statistics.mean(r["itm"] for r in rs),100*statistics.mean(r["cap"] for r in rs)))
show("no calls",0.50,0.0)
for cov in (0.20,0.30,0.40):
    show("ATM (0.50d) @ %d%%"%(cov*100),0.50,cov)
for cov in (0.30,0.50):
    show("0.40d @ %d%%"%(cov*100),0.40,cov)
for cov in (0.25,0.50):
    show("0.30d (4%% out) @ %d%%"%(cov*100),0.30,cov)
