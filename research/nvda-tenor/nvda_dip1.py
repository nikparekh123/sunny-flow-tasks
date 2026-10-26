# -*- coding: utf-8 -*-
"""NVDA PART 1: does a red day mean anything, and does a streak mean more?

This is the test that decides whether the TLT dip gate has any business on NVDA.
TLT's whole edge came from mean reversion: it bounces after red days, harder the
longer the slide runs. A momentum stock does the opposite, and if NVDA trends then
buying the second red day is buying into a decline rather than a discount.

Buckets are scaled to NVDA, which moves roughly three times as much as TLT in a day.
"""
import json, math, statistics as st
b=json.load(open("nvda_long.json"))["bars"]
d=[x["d"] for x in b]; C=[x["c"] for x in b]
r=[C[i+1]/C[i]-1 for i in range(len(C)-1)]      # r[i] is the return ON day i+1
print("NVDA %s to %s, %d sessions.  Daily sd %.2f%% (TLT is 0.55%%).\n"%(
      d[0],d[-1],len(r),100*st.pstdev(r)))

def fwd(i,n):
    w=r[i:i+n]
    return st.pstdev(w)*math.sqrt(252) if len(w)==n else None

BUCK=[(-9,-0.04,"down over 4%"),(-0.04,-0.02,"down 2 to 4%"),(-0.02,-0.01,"down 1 to 2%"),
      (-0.01,0,"down 0 to 1%"),(0,0.01,"up 0 to 1%"),(0.01,0.02,"up 1 to 2%"),(0.02,9,"up over 2%")]
print("%-18s %7s %12s %14s"%("today's move","days","fwd 5d vol","NEXT DAY"))
for lo,hi,lab in BUCK:
    v=[];nx=[]
    for i in range(len(r)-6):
        if lo<=r[i]<hi:
            a=fwd(i+1,5)
            if a: v.append(a)
            nx.append(r[i+1])
    print("%-18s %7d %11.1f%% %+13.3f%%"%(lab,len(v),100*st.mean(v),100*st.mean(nx)))
base=st.mean([v for i in range(len(r)-6) if (v:=fwd(i+1,5))])
print("unconditional fwd 5d vol %.1f%%,  unconditional next day %+.4f%%"%(100*base,100*st.mean(r)))

print("\nTHE DECIDING TEST  what follows N red days in a row")
print("%-24s %8s %14s %14s"%("","n","next day","next 5 days"))
for n in range(1,6):
    nx=[];n5=[]
    for i in range(n,len(r)-6):
        if all(r[i-k]<0 for k in range(n)):
            nx.append(r[i+1]); n5.append(C[min(i+6,len(C)-1)]/C[i+1]-1)
    print("  %d red day%s in a row   %8d %+13.4f%% %+13.4f%%"%(n,"s" if n>1 else " ",len(nx),100*st.mean(nx),100*st.mean(n5)))
print("  %-22s %8d %+13.4f%%"%("baseline, any day",len(r),100*st.mean(r)))

print("\nSame thing on TLT for contrast")
t={x["d"]:x["c"] for x in json.load(open("../tlt-auction/tlt.json"))["bars"]}
td=sorted(t); tc=[t[x] for x in td]
tr=[tc[i+1]/tc[i]-1 for i in range(len(tc)-1)]
for n in range(1,5):
    nx=[tr[i+1] for i in range(n,len(tr)-1) if all(tr[i-k]<0 for k in range(n))]
    print("  %d red in a row -> next day %+.4f%%  (TLT baseline %+.4f%%)"%(n,100*st.mean(nx),100*st.mean(tr)))
