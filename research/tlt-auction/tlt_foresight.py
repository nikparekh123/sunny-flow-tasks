# -*- coding: utf-8 -*-
"""Is it worth slowing down because you expect rates to rise?

Nik: "I don't want to buy 10K shares now if we expect two rate increases in 4 months."
Coherent -- hikes push yields up, TLT down, so waiting buys cheaper. The measured
problem is that expected policy is already in the 30-year (fed funds -> 30y is
R2 0.01). So this tests the UPPER BOUND: an arm that KNOWS the yield 4 months out
and brakes when it is about to rise. If perfect foresight does not pay, a view
cannot.
"""
exec(open("tlt_bands.py").read().split("wins=[i for i")[0])

FWD = 84  # ~4 months of sessions
fwdY = {}
for i, d in enumerate(days):
    j = min(i+FWD, len(days)-1)
    fwdY[d] = y30[days[j]]

def fRel(d): return fYieldRel(d)
def fOracle(d, thresh, brake):
    """slow down when the 30y is about to be materially HIGHER (TLT lower)"""
    rise = (fwdY[d] - y30[d]) * 100
    return fYieldRel(d) * (brake if rise >= thresh else 1.0)

wins = [i for i in range(0, len(FRI)-HOR)]
print("%d windows · brake fires when the 30y is about to rise by N bp over ~4 months\n" % len(wins))
print("%-40s %9s %9s %11s %12s" % ("arm", "shares", "basis", "net", "worst DD"))
print("-"*86)
def run(label, fn):
    rs = [walk(FRI[i:i+HOR], fn) for i in wins]; n = len(rs)//2
    sh = sorted(r["sh"] for r in rs); nt = sorted(r["net"] for r in rs)
    bp = sorted(r["bp"] for r in rs); dd = sorted(r["dd"] for r in rs)
    print("%-40s %9s %9s %11s %12s" % (label, format(int(sh[n]),","), "$%.2f"%bp[n],
          "$%s"%format(int(nt[n]),","), "$%s"%format(int(dd[n]),",")))
    return sh[n], bp[n], nt[n]
run("yield vs 250d mean (no foresight)", fRel)
for th in (25, 50):
    for br, lab in ((0.5, "half"), (0.0, "stop")):
        run("ORACLE: %s when +%dbp coming" % (lab, th), lambda d, t=th, b=br: fOracle(d, t, b))
print()
hits = sum(1 for d in FRI if (fwdY[d]-y30[d])*100 >= 25)
print("  the 30y rose 25bp+ over the next 4 months on %d of %d Fridays (%.0f%%)" % (hits, len(FRI), 100*hits/len(FRI)))
