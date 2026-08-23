import json,datetime
H=json.load(open("tlt_hist.json")); close={b["d"]:b["c"] for b in H["bars"]}; days=sorted(close)
listed=json.load(open("expiries.json"))["listed"]           # real TLT expiry dates
L=[d for d in listed]
def occ(exp,cp,k): return "O:TLT%s%s%08d"%(datetime.date.fromisoformat(exp).strftime("%y%m%d"),cp,int(round(k*1000)))
def dte(a,b): return (datetime.date.fromisoformat(b)-datetime.date.fromisoformat(a)).days

# Roll-on-expiry: every arm is continuously written. Only the target tenor differs,
# so frequency and tenor move together exactly as they do in the real programme.
ARMS={"EVERY_EXP":2,"WEEKLY":7,"BIWEEKLY":14,"MONTHLY":30}
plan={};need=set()
START="2024-09-09"   # first date all three weekday expiries exist
for arm,tgt in ARMS.items():
    rolls=[];cur=START
    while True:
        # nearest listed expiry to the target tenor, strictly after the write date
        # Tenors past ~10 days can only use FRIDAY expiries: TLT lists its Mon/Wed
        # weeklies about a week or two ahead, so a 30-day Mon/Wed contract does not
        # exist to be written. This is market structure, not a data gap.
        pool=L if tgt<10 else [e for e in L if datetime.date.fromisoformat(e).weekday()==4]
        fwd=[e for e in pool if dte(cur,e)>=1]
        if not fwd: break
        exp=min(fwd,key=lambda e:(abs(dte(cur,e)-tgt),dte(cur,e)))
        if dte(cur,exp)<1: break
        if exp>days[-1]: break
        if cur not in close: # write date must be a trading day
            nxt=[d for d in days if d>=cur]
            if not nxt: break
            cur=nxt[0]; continue
        S=close[cur]
        base=round(S*2)/2.0
        ks=sorted({base+o for o in (-1.0,-0.5,0.0,0.5,1.0)} | {float(round(S))})
        rolls.append({"d":cur,"exp":exp,"S":S,"ks":ks,"dte":dte(cur,exp)})
        for k in ks:
            need.add(occ(exp,"C",k)); need.add(occ(exp,"P",k))
        cur=exp
    plan[arm]=rolls
    ds=[r["dte"] for r in rolls]
    print("%-10s rolls %4d  median dte %4.1f  %s -> %s"%(arm,len(rolls),sorted(ds)[len(ds)//2],rolls[0]["d"],rolls[-1]["exp"]))
json.dump({"plan":plan,"need":sorted(need)},open("plan.json","w"))
print("contracts needed",len(need))
