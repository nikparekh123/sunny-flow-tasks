# -*- coding: utf-8 -*-
"""PART 3: streaks, and does the red-day edge hold up across eras."""
import json, math, datetime, statistics as st
exec(open("tlt_dip2.py").read().split("ret=lambda")[0].split('print("PART 2')[0])

ret=lambda i: C[i]/C[i-1]-1
def streak(i):                       # how many red days in a row up to and including i
    n=0
    while n<i and C[i-n]/C[i-n-1]-1<0: n+=1
    return n

print("PART 3  Where in a losing streak should the size go?\n")
print("%-38s %6s %9s %9s %10s"%("arm","events","basis","vs tape","shr/week"))
print("-"*78)
A=[("flat on every red day (baseline)", lambda i: ret(i)<0, lambda i:775),
   ("first red day of a streak only",   lambda i: streak(i)==1, lambda i:1500),
   ("second red day onward only",       lambda i: streak(i)>=2, lambda i:1500),
   ("third red day onward only",        lambda i: streak(i)>=3, lambda i:2600),
   ("decay 100/70/40/20 by streak day", lambda i: ret(i)<0, lambda i:775*[1,.7,.4,.2][min(streak(i),4)-1]),
   ("build 40/70/100/130 by streak day",lambda i: ret(i)<0, lambda i:775*[.4,.7,1,1.3][min(streak(i),4)-1])]
for lab,t,s in A:
    r=sim(t,s)
    print("%-38s %6d %9.2f %+9.2f %10.0f"%(lab,r['ev'],r['basis'],r['vtape'],r['pace']))

print("\nPART 4  Does the red-day edge survive in every era?\n")
print("%-14s %14s %14s %10s"%("period","cadence vs tape","red day vs tape","red wins by"))
print("-"*58)
ERA=[("2004-2009",70,1600),("2010-2015",1600,3100),("2016-2021",3100,4600),("2022-2026",4600,len(D)-40)]
for lab,a,b in ERA:
    f=sim(lambda i: datetime.date.fromisoformat(D[i]).weekday()==4, lambda i:1861, a, b)
    g=sim(lambda i: ret(i)<0, lambda i:775, a, b)
    print("%-14s %+14.2f %+14.2f %10.2f"%(lab,f['vtape'],g['vtape'],f['vtape']-g['vtape']))
