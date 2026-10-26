# -*- coding: utf-8 -*-
"""48 at-the-money puts, rolled every expiry versus rolled Friday-only.

Both arms hold at most 48 contracts open at once, so both sit inside the same
$400,000 ceiling. The only difference is how often the clock resets: Mon/Wed/Fri
against Friday-to-Friday. Same trailing-vol surface prices both, and the real
closes decide assignment.

2004 TLT had no Monday or Wednesday weeklies. Pricing them off the same surface
as the Friday contract is the assumption this test rests on, and it is the one
thing here that is modelled rather than observed.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; CT=48; SH=CT*100

tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
days=sorted(tlt)
lr=[math.log(tlt[days[i+1]]/tlt[days[i]]) for i in range(len(days)-1)]
def volAt(d):
    i=days.index(d); w=lr[max(0,i-63):i]
    return max(0.04, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.10
def putpx(S,K,T,v):
    if T<=0: return max(0.0,K-S)
    d1=(math.log(S/K)+(R+v*v/2)*T)/(v*math.sqrt(T)); d2=d1-v*math.sqrt(T)
    return K*math.exp(-R*T)*ND.cdf(-d2)-S*ND.cdf(-d1)
def strike(S): return round(S*2)/2          # nearest 0.50

def run(win, sched):
    """sched: weekday set the arm may write on and expire into."""
    nodes=[d for d in win if datetime.date.fromisoformat(d).weekday() in sched]
    prem=0.0; got=0; paid=0.0; rolls=0
    for a,b in zip(nodes, nodes[1:]):
        S=tlt[a]; K=strike(S)
        T=(datetime.date.fromisoformat(b)-datetime.date.fromisoformat(a)).days/365
        prem += putpx(S,K,T,volAt(a))*100*CT; rolls+=1
        if tlt[b] < K: got+=SH; paid+=K*SH   # assigned at the strike
    return prem, got, paid, rolls

FRI=[d for d in days if datetime.date.fromisoformat(d).weekday()==4]
MWF={0,2,4}; F={4}
rows=[]
for s in range(70, len(FRI)-3):             # every two-week window in the history
    a=FRI[s]; c=FRI[s+2]
    win=days[days.index(a):days.index(c)+1]
    if len(win)<9 or len(win)>12: continue
    end=tlt[c]
    r={}
    for nm,sc in (("every",MWF),("fri",F)):
        p,g,pd,n=run(win,sc)
        eq = g*end-pd                        # mark on whatever was assigned
        r[nm]=(p, p+eq, g, n)
    rows.append((a,end,r))

print("48 ATM puts.  Every two-week window in TLT's history, %d of them.\n"%len(rows))
print("%-28s %12s %12s"%("","EVERY EXPIRY","FRIDAY ONLY"))
def col(f,fmt="%12s"):
    return "".join(fmt%f(r,k) for k in ("every","fri"))
med=lambda k,i: st.median([r[2][k][i] for r in rows])
mean=lambda k,i: sum(r[2][k][i] for r in rows)/len(rows)
print("%-28s"%"rolls per window"      + col(lambda r,k:"%.0f"%r[2][k][3]  if 0 else "%.1f"%mean(k,3)))
print("%-28s"%"premium, median"       + col(lambda r,k:"$%s"%format(round(med(k,0)),",")))
print("%-28s"%"premium, mean"         + col(lambda r,k:"$%s"%format(round(mean(k,0)),",")))
print("%-28s"%"shares assigned, mean" + col(lambda r,k:format(round(mean(k,2)),",")))
print("%-28s"%"NET incl. assigned, med"+col(lambda r,k:"$%s"%format(round(med(k,1)),",")))
print("%-28s"%"NET incl. assigned, mean"+col(lambda r,k:"$%s"%format(round(mean(k,1)),",")))

w=sum(1 for r in rows if r[2]["every"][1]>r[2]["fri"][1])
print("\nevery-expiry beats Friday-only on NET in %d of %d windows (%.0f%%)"%(w,len(rows),100*w/len(rows)))
d=sorted(r[2]["every"][1]-r[2]["fri"][1] for r in rows)
q=lambda p: d[int(p*(len(d)-1))]
print("difference   p05 $%s   median $%s   p95 $%s"%tuple(format(round(q(p)),",") for p in (.05,.5,.95)))
print("worst window $%s     best window $%s"%(format(round(d[0]),","),format(round(d[-1]),",")))

sp=0.01
print("\nspread at 1c per contract: every $%s  vs friday $%s   (net of it, every-expiry keeps $%s)"%(
  format(round(mean("every",3)*CT*sp*100),","), format(round(mean("fri",3)*CT*sp*100),","),
  format(round(mean("every",1)-mean("fri",1)-(mean("every",3)-mean("fri",3))*CT*sp*100),",")))
