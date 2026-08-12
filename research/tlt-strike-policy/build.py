import json,math,datetime,statistics
from statistics import NormalDist
H=json.load(open("tlt_hist.json")); bars=H["bars"]
close={b["d"]:b["c"] for b in bars}; days=sorted(close)
R=0.045; N=NormalDist()

# realised vol, 20d, annualised — used ONLY to place the strike at a target delta.
# The premium itself always comes from the real option bar, so there is no
# circular-IV trap: nothing is priced and settled with the same assumption.
rv={}
for i in range(21,len(days)):
    w=days[i-21:i+1]
    lr=[math.log(close[w[j+1]]/close[w[j]]) for j in range(len(w)-1)]
    rv[days[i]]=statistics.stdev(lr)*math.sqrt(252)

def strike_for(S,T,v,delta,kind):
    d1 = N.inv_cdf(delta) if kind=="C" else -N.inv_cdf(delta)
    K = S*math.exp((R+v*v/2)*T - d1*v*math.sqrt(T))
    return round(K*2)/2.0               # half-strikes: at 8% vol on 7 days, one sigma
                                        # is ~$1, so whole strikes collapse the three
                                        # policies onto the same contract

# roll every Friday, expiry the next Friday
rolls=[]
for d in days:
    dd=datetime.date.fromisoformat(d)
    if dd.weekday()!=4: continue
    exp=dd+datetime.timedelta(days=7)
    if d not in rv: continue
    rolls.append((d,exp.isoformat()))
rolls=[r for r in rolls if r[0]>=days[22]]

PUTS={"OTM":0.25,"ATM":0.50,"ITM":0.75}
CALLS={"far":0.15,"atm":0.50}
plan={}; need=set()
for d,exp in rolls:
    S=close[d]; v=rv[d]; T=7/365
    row={"S":S,"v":v,"exp":exp,"put":{},"call":{}}
    for nm,dl in PUTS.items():
        K=strike_for(S,T,v,dl,"P"); row["put"][nm]=K
        need.add("O:TLT%s P%08d".replace(" ","")%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000))))
    for nm,dl in CALLS.items():
        K=strike_for(S,T,v,dl,"C"); row["call"][nm]=K
        need.add("O:TLT%sC%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),int(round(K*1000))))
    plan[d]=row
json.dump({"plan":plan,"need":sorted(need)},open("plan.json","w"))
print("rolls",len(rolls),rolls[0][0],"->",rolls[-1][0])
print("contracts needed",len(need))
print("vol range %.1f%% - %.1f%%"%(min(rv.values())*100,max(rv.values())*100))
s=plan[rolls[-1][0]]
print("sample last roll: S=%.2f v=%.1f%% puts %s calls %s"%(s["S"],s["v"]*100,s["put"],s["call"]))
