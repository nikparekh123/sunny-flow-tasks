# -*- coding: utf-8 -*-
"""Does the rate need to chase a shortfall?

The engine sizes on (quarter budget / 13) x price dial x conviction, and never looks
at whether shares actually arrived. This asks whether it should, because the event
that starves delivery -- a rally -- is the same event the price dial slows down for.
Three arms over every 72-week window in the data, so the answer is not one lucky path.
"""
import json, math, datetime, statistics
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

def pdelta(S,K,T,v):
    if T<=0 or v<=0: return 1.0 if S<K else 0.0
    return N.cdf(-((math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))))
def nextfri(d):
    t=datetime.date.fromisoformat(d)+datetime.timedelta(days=7); t=t.isoformat()
    later=[x for x in days if x>=t]
    return later[0] if later else None

# the live engine's MA100 bands, ascending
BANDS=[(-11.2,2.50),(-3.3,1.50),(0,1.00),(float('inf'),0.60)]
def mafac(S,m):
    p=(S/m-1)*100
    for hi,f in BANDS:
        if p<hi: return f
    return 0.60

START,TARGET,HOR=1500,15000,72
BASE=(TARGET-START)/HOR                      # 187.5 delta/wk, the plan's rate

def run(fris,mode):
    sh=float(START); paid=0.0; openp=[]; maxout=0.0; maxct=0; dry=0; worstdry=0
    for i,d in enumerate(fris):
        exp=nextfri(d)
        if not exp: break
        for leg in list(openp):
            if leg["exp"]<=d:
                if close[leg["exp"]]<leg["K"]:
                    sh+=leg["ct"]*100; paid+=leg["K"]*leg["ct"]*100
                openp.remove(leg)
        S,v,T=close[d],rv[d],7/365
        wksleft=max(1,HOR-i)
        need=max(0.0,TARGET-sh)
        if   mode=="fixed":    per=BASE
        elif mode=="chase":    per=need/wksleft
        elif mode=="chase2x":  per=min(need/wksleft,2*BASE)
        per*=mafac(S,ma[d])
        K=round(S*0.99/2.5)*2.5
        dl=pdelta(S,K,T,v)
        ct=max(0,round(per/(dl*100))) if dl>0 else 0
        if ct>0:
            openp.append({"K":K,"ct":ct,"exp":exp}); maxct=max(maxct,ct)
            maxout=max(maxout,sum(l["K"]*100*l["ct"] for l in openp))
    return dict(shares=round(sh),basis=paid/max(1,sh-START),peak=maxout,maxct=maxct)

# --- the dry spells, on price alone: weeks a 1% OTM put delivered nothing -------
runs=[];cur=0
for d in FRI:
    exp=nextfri(d)
    if not exp: break
    K=round(close[d]*0.99/2.5)*2.5
    if close[exp]<K:
        if cur: runs.append(cur)
        cur=0
    else: cur+=1
if cur: runs.append(cur)
runs.sort(reverse=True)
tot=len([d for d in FRI if nextfri(d)])
print("== delivery, %d weekly writes at 1%% OTM =="%tot)
print("weeks assigned      : %d (%.0f%%)"%(tot-sum(runs),100*(tot-sum(runs))/tot))
print("longest dry spell   : %d weeks"%runs[0])
print("dry spells >= 4 wks : %s"%([r for r in runs if r>=4] or "none"))
print("top 8 spells        : %s"%runs[:8])

print("\n== 72-week windows, start 1,500 -> target 15,000 ==")
wins=[i for i in range(0,len(FRI)-HOR)]
print("windows: %d  (%s .. %s)"%(len(wins),FRI[0],FRI[wins[-1]]))
hdr="%-9s %8s %8s %8s %9s %7s"%("arm","median","worst","best","peak cash","max ct")
print(hdr); print("-"*len(hdr))
for mode in ("fixed","chase","chase2x"):
    rs=[run(FRI[i:i+HOR],mode) for i in wins]
    sh=sorted(r["shares"] for r in rs)
    print("%-9s %8s %8s %8s %9s %7d"%(mode,
        format(sh[len(sh)//2],","),format(sh[0],","),format(sh[-1],","),
        "$%.1fM"%(max(r["peak"] for r in rs)/1e6),max(r["maxct"] for r in rs)))
    bs=sorted(r["basis"] for r in rs)
    print("%-9s %8s  basis median $%.2f   (worst $%.2f)"%("","",bs[len(bs)//2],bs[-1]))
