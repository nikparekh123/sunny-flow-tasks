# -*- coding: utf-8 -*-
"""Does AVGO bounce after red days the way NVDA does? That decides everything else."""
import json, math, statistics as st
def load(p):
    b=json.load(open(p))["bars"]; return [x["d"] for x in b],[x["c"] for x in b]
def rets(C): return [C[i+1]/C[i]-1 for i in range(len(C)-1)]

out={}
for name,p in (("NVDA","nvda_long.json"),("AVGO","avgo_long.json")):
    D,C=load(p); r=rets(C)
    base=st.mean(r)
    rows=[]
    for n in range(1,5):
        nx=[r[i+1] for i in range(n,len(r)-1) if all(r[i-k]<0 for k in range(n))]
        rows.append((n,len(nx),st.mean(nx),st.mean(nx)/base))
    out[name]=(base,rows,st.pstdev(r),C[-1]/C[0]-1)

print("What happens the DAY AFTER a run of red days.\n")
print("Positive means the stock tends to go UP, so you sold your put into a bounce.\n")
for name in ("NVDA","AVGO"):
    base,rows,sd,tot=out[name]
    print("%s   daily swing %.2f%%   rose %.0f%% over the period   normal day %+.3f%%"%(
        name,100*sd,100*tot,100*base))
    for n,cnt,m,mult in rows:
        print("    after %d red day%s  (%4d times)   next day %+.3f%%   = %.1fx a normal day"%(
            n,"s" if n>1 else " ",cnt,100*m,mult))
    print()
