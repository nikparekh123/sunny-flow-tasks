# -*- coding: utf-8 -*-
"""Does a weak 30-year auction predict TLT? Tested before it is allowed to move size.

The NVDA conviction families shipped at weight ZERO because none of six candidates
cleared the noise. This is the seventh candidate and gets the same bar: a tercile
spread has to beat its own standard error before it earns a weight.
"""
import json, statistics as st
bars=json.load(open("tlt.json"))["bars"]; close={b["d"]:b["c"] for b in bars}
days=sorted(close); idx={d:i for i,d in enumerate(days)}
auc=[a for a in json.load(open("auctions.json")) if a.get("bid_to_cover_ratio")]
for a in auc:
    a["bc"]=float(a["bid_to_cover_ratio"])
    # the API returns the STRING 'null' on older rows, not JSON null
    def f(k):
        v=a.get(k)
        try: return float(v)
        except (TypeError, ValueError): return 0.0
    ta=f("total_accepted"); ind=f("indirect_bidder_accepted")
    a["ind"]=100*ind/ta if ta else None
auc.sort(key=lambda a:a["auction_date"])

def fwd(d,n):
    later=[x for x in days if x>=d]
    if not later: return None
    i=idx[later[0]]
    if i+n>=len(days): return None
    return 100*(close[days[i+n]]/close[days[i]]-1)

rows=[]
for a in auc:
    r={"d":a["auction_date"],"bc":a["bc"],"ind":a["ind"]}
    for n in (1,5,21): r["f%d"%n]=fwd(a["auction_date"],n)
    if all(r["f%d"%n] is not None for n in (1,5,21)): rows.append(r)
print("usable auctions: %d  (%s .. %s)\n"%(len(rows),rows[0]["d"],rows[-1]["d"]))

def terciles(key,label):
    ok=[r for r in rows if r[key] is not None]
    ok.sort(key=lambda r:r[key])
    k=len(ok)//3
    lo,hi=ok[:k],ok[-k:]
    print("%s — weak tercile n=%d (%.2f–%.2f)  vs  strong n=%d (%.2f–%.2f)"%(
        label,len(lo),lo[0][key],lo[-1][key],len(hi),hi[0][key],hi[-1][key]))
    print("   %-8s %9s %9s %9s %9s"%("horizon","weak","strong","spread","se"))
    for n in (1,5,21):
        a=[r["f%d"%n] for r in lo]; b=[r["f%d"%n] for r in hi]
        sp=st.mean(a)-st.mean(b)
        se=(st.pstdev(a)**2/len(a)+st.pstdev(b)**2/len(b))**0.5
        flag="" if abs(sp)<=2*se else "  <- clears 2se"
        print("   %-8s %+8.2f%% %+8.2f%% %+8.2f%% %8.2f%%%s"%("%dd"%n,st.mean(a),st.mean(b),sp,se,flag))
    print()
terciles("bc","BID-TO-COVER")
terciles("ind","INDIRECT BIDDER %")
base=[r["f21"] for r in rows]
print("baseline: TLT 21d after ANY 30-year auction  %+.2f%%  (sd %.2f, n=%d)"%(st.mean(base),st.pstdev(base),len(base)))
