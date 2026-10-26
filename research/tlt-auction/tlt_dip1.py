# -*- coding: utf-8 -*-
"""PART 1: is a down day actually worth more, and is the IV bump earned?

No stored TLT IV history, so this tests the thing IV is a forecast OF: realised
volatility over the days that follow. If vol genuinely rises after a red day then the
option you sell that afternoon is priced richer for a reason, and the premium pickup
Nik sees on IBKR is real rather than noise.
"""
import json, math, statistics as st
tlt={b["d"]:b["c"] for b in json.load(open("tlt.json"))["bars"]}
d=sorted(tlt); c=[tlt[x] for x in d]
r=[c[i+1]/c[i]-1 for i in range(len(c)-1)]          # r[i] is the return ON day i+1

def fwdvol(i,n):
    w=r[i:i+n]
    return st.pstdev(w)*math.sqrt(252) if len(w)==n else None

BUCK=[(-9,-0.02,"down over 2%"),(-0.02,-0.01,"down 1 to 2%"),(-0.01,-0.005,"down 0.5 to 1%"),
      (-0.005,0,"down 0 to 0.5%"),(0,0.005,"up 0 to 0.5%"),(0.005,9,"up over 0.5%")]
print("PART 1  What follows a day of each size.  TLT 2003-2026, %d days.\n"%len(r))
print("%-20s %7s %12s %12s %12s"%("today's move","days","fwd 5d vol","fwd 10d vol","next-day ret"))
allv=[v for i in range(len(r)-10) if (v:=fwdvol(i+1,5))]
base=st.mean(allv)
for lo,hi,lab in BUCK:
    v5=[];v10=[];nx=[]
    for i in range(len(r)-11):
        if lo<=r[i]<hi:
            a,b=fwdvol(i+1,5),fwdvol(i+1,10)
            if a: v5.append(a)
            if b: v10.append(b)
            nx.append(r[i+1])
    print("%-20s %7d %11.1f%% %11.1f%% %+11.3f%%"%(lab,len(v5),100*st.mean(v5),100*st.mean(v10),100*st.mean(nx)))
print("\nunconditional 5d forward vol %.1f%%"%(100*base))

# does a red day mean revert or keep falling? this decides whether waiting for red
# gets you a cheaper entry or just an entry before more downside.
print("\nPART 1b  After a red day, and after N red days in a row")
for n in range(1,5):
    nx=[]
    for i in range(n,len(r)-1):
        if all(r[i-k]<0 for k in range(n)): nx.append(r[i+1])
    print("  %d red day%s in a row -> next day %+.4f%%   (base %+.4f%%)  n=%d"%(
        n,"s" if n>1 else " ",100*st.mean(nx),100*st.mean(r),len(nx)))
