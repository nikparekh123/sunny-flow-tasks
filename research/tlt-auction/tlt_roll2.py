# -*- coding: utf-8 -*-
"""Same test, but sized to the SAME accumulation pace instead of the same contract count.

48 contracts on every expiry is not the same trade as 48 on Friday, it is roughly three
times the trade. Holding the delta budget fixed is what makes the two schedules
comparable: same expected shares delivered per week, so the only question left is which
one pays more premium for delivering them.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045
WEEKLY_DELTA=1861            # the planner's current budget

tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
days=sorted(tlt)
lr=[math.log(tlt[days[i+1]]/tlt[days[i]]) for i in range(len(days)-1)]
def volAt(d):
    i=days.index(d); w=lr[max(0,i-63):i]
    return max(0.04, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.10
def d1(S,K,T,v): return (math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T))
def putpx(S,K,T,v):
    if T<=0: return max(0.0,K-S)
    a=d1(S,K,T,v); return K*math.exp(-R*T)*ND.cdf(-(a-v*math.sqrt(T)))-S*ND.cdf(-a)
def putdelta(S,K,T,v): return ND.cdf(-d1(S,K,T,v)) if T>0 else (1.0 if S<K else 0.0)
def strike(S): return round(S*2)/2

def run(win, sched):
    nodes=[d for d in win if datetime.date.fromisoformat(d).weekday() in sched]
    prem=0.0; got=0; paid=0.0; rolls=0; dsold=0.0; peak=0.0
    for a,b in zip(nodes, nodes[1:]):
        S=tlt[a]; K=strike(S); v=volAt(a)
        T=(datetime.date.fromisoformat(b)-datetime.date.fromisoformat(a)).days/365
        dl=putdelta(S,K,T,v)
        span=(datetime.date.fromisoformat(b)-datetime.date.fromisoformat(a)).days
        want=WEEKLY_DELTA*span/7.0                 # this leg's share of the budget
        ct=max(1, round(want/(dl*100)))            # size to the pace, not to a fixed count
        prem += putpx(S,K,T,v)*100*ct; rolls+=1; dsold+=dl*100*ct
        peak=max(peak, K*100*ct)                   # cash on the line at once
        if tlt[b] < K: got+=ct*100; paid+=K*ct*100
    return prem, got, paid, rolls, dsold, peak

FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4]
MWF={0,2,4}; F={4}
rows=[]
for s in range(70, len(FRI)-3):
    a=FRI[s]; c=FRI[s+2]
    win=days[days.index(a):days.index(c)+1]
    if len(win)<9 or len(win)>12: continue
    end=tlt[c]; r={}
    for nm,sc in (("every",MWF),("fri",F)):
        p,g,pd,n,dl,pk=run(win,sc)
        r[nm]=(p, p+(g*end-pd), g, n, dl, pk)
    rows.append((a,end,r))

mean=lambda k,i: sum(r[2][k][i] for r in rows)/len(rows)
med =lambda k,i: st.median([r[2][k][i] for r in rows])
print("Sized to %d delta per week.  %d two-week windows.\n"%(WEEKLY_DELTA,len(rows)))
print("%-30s %13s %13s"%("","EVERY EXPIRY","FRIDAY ONLY"))
def line(lab,f): print("%-30s %13s %13s"%(lab,f("every"),f("fri")))
line("rolls per window",      lambda k:"%.1f"%mean(k,3))
line("contracts per roll",    lambda k:"%.0f"%(mean(k,4)/mean(k,3)/50))
line("delta sold per window", lambda k:format(round(mean(k,4)),","))
line("cash on the line, peak", lambda k:"$%s"%format(round(mean(k,5)),","))
line("PREMIUM, mean",         lambda k:"$%s"%format(round(mean(k,0)),","))
line("PREMIUM, median",       lambda k:"$%s"%format(round(med(k,0)),","))
line("shares assigned, mean", lambda k:format(round(mean(k,2)),","))
line("net incl. assigned, med",lambda k:"$%s"%format(round(med(k,1)),","))

pw=sum(1 for r in rows if r[2]["every"][0]>r[2]["fri"][0])
print("\nevery-expiry pays more premium in %d of %d windows (%.0f%%)"%(pw,len(rows),100*pw/len(rows)))
print("premium per 1,000 delta sold:   every $%.0f    friday $%.0f"%(
    1000*mean("every",0)/mean("every",4), 1000*mean("fri",0)/mean("fri",4)))

# --- the counter-argument: does spreading the dates buy less dispersion? ---
import statistics as S2
print("\nDISPERSION of net, and cash at today's 82.01 rather than the historical mean")
for k,ct in (("every",13),("fri",37)):
    n=[r[2][k][1] for r in rows]; n.sort()
    q=lambda p:n[int(p*(len(n)-1))]
    print("  %-6s sd $%-9s p05 $%-10s p95 $%-10s  peak cash today $%s"%(
        k, format(round(S2.pstdev(n)),","), format(round(q(.05)),","),
        format(round(q(.95)),","), format(round(82.01*100*ct),",")))
