# -*- coding: utf-8 -*-
"""NET over time, not just at the horizon.

Every earlier test reported one number at week 72. This walks the same paths and
marks the book each month per docs/PNL_GLOSSARY.md:

  REALIZED   = stock sold - stock bought (closed only) + premium on expired/closed
               options - cost paid on closed options
  UNREALIZED = (spot - buy price) x shares held + premium on still-open shorts, marked
  NET        = REALIZED + UNREALIZED

Assigned short call: the shares are sold AT THE STRIKE and that stock sale carries the
realized P&L. The call's premium is not re-realized on the option side (glossary rule).
"""
import json, math, datetime, statistics
from statistics import NormalDist
exec(open("nvda_calls_atm.py").read().split("wins=[i for i")[0].replace('todo=sorted(need-set(OB))','todo=[]'))

def walk(sub,dl,cov,mode):
    sh=0.0; lots=[]                      # FIFO (qty, price)
    prem_real=0.0; cost_real=0.0; stock_real=0.0; debit=0.0
    puts=[]; calls=[]; snaps=[]
    lots.append([float(START),float(close[sub[0]["d"]])])   # opening block at spot
    sh=float(START)
    for i,r in enumerate(sub):
        d,exp,S,v,T=r["d"],r["exp"],r["S"],r["v"],7/365
        for l in list(puts):
            if l["exp"]<=d:
                Sx=close[l["exp"]]
                prem_real+=l["prem"]*100*l["ct"]           # premium realised at expiry
                if Sx<l["K"]:
                    sh+=l["ct"]*100; lots.append([float(l["ct"]*100),float(l["K"])])
                puts.remove(l)
        for l in list(calls):
            if l["exp"]<=d:
                Sx=close[l["exp"]]
                prem_real+=l["prem"]*100*l["ct"]
                if Sx>l["K"]:
                    if mode=="roll": debit+=(Sx-l["K"])*l["ct"]*100
                    else:
                        take=min(sh,l["ct"]*100); sh-=take; left=take
                        while left>0 and lots:                     # FIFO out at the strike
                            q,pxx=lots[0]; use=min(q,left)
                            stock_real+=(l["K"]-pxx)*use
                            lots[0][0]-=use; left-=use
                            if lots[0][0]<=1e-9: lots.pop(0)
                calls.remove(l)
        per=min(max(0.0,TARGET-sh)/max(1,HOR-i),2*BASE)*mafac(S,ma[d])
        K,m=px(exp,"P",r["kp"],d,(0,-2.5,2.5,-5,5))
        if K:
            pd_=pdelta(S,K,T,v); ct=max(0,round(per/(pd_*100))) if pd_>0 else 0
            if ct: puts.append({"K":K,"ct":ct,"exp":exp,"prem":m})
        if cov>0:
            room=max(0,math.floor((sh*cov-sum(l["ct"]*100 for l in calls))/100))
            if room:
                Kc,mc=px(exp,"C",r["kc%d"%int(dl*100)],d,(0,2.5,5,-2.5,-5))
                if Kc: calls.append({"K":Kc,"ct":room,"exp":exp,"prem":mc})
        basis=sum(q*p for q,p in lots); heldq=sum(q for q,_ in lots)
        unreal_sh=S*heldq-basis
        open_prem=sum(l["prem"]*100*l["ct"] for l in puts+calls)   # received, still open
        net=prem_real-cost_real+stock_real-debit+unreal_sh+open_prem
        snaps.append(dict(wk=i+1,net=net,sh=sh,prem=prem_real,debit=debit,
                          stock_real=stock_real,unreal=unreal_sh))
    return snaps

sub=rows[0:HOR]
arms=[("no calls",0.50,0.0,"none"),("ATM 30%, rolled",0.50,0.30,"roll"),("ATM 30%, assigned",0.50,0.30,"assign")]
S0,S1=close[sub[0]["d"]],close[sub[-1]["d"]]
print("window %s -> %s   spot %.2f -> %.2f  (%+.0f%%)"%(sub[0]["d"],sub[-1]["d"],S0,S1,100*(S1/S0-1)))
res={n:walk(sub,d,c,m) for n,d,c,m in arms}
print("\nNET by month (week 4 = month 1)")
print("%-7s %6s %14s %14s %16s"%("month","spot","no calls","ATM rolled","ATM assigned"))
for mth in range(1,19):
    wk=mth*4
    if wk>len(sub): break
    S=close[sub[wk-1]["d"]]
    row=[res[n][wk-1]["net"] for n,_,_,_ in arms]
    print("%-7d %6.0f %14s %14s %16s"%(mth,S,*["$%s"%format(int(x),",") for x in row]))
print("\nshares held")
print("%-7s %14s %14s %16s"%("month","no calls","ATM rolled","ATM assigned"))
for mth in (3,6,9,12,15,18):
    wk=mth*4
    if wk>len(sub): break
    print("%-7d %14s %14s %16s"%(mth,*[format(int(res[n][wk-1]["sh"]),",") for n,_,_,_ in arms]))
