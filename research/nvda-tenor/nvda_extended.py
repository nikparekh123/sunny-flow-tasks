# -*- coding: utf-8 -*-
"""When NVDA is EXTENDED, should the engine write less, wait, or reach further out?

Today the dial answers only the first: above MA100 it writes 0.60x and still sells
1% out. Nik's point is that 0.60x of a bad trade is still a bad trade. Three levers
tested against the same share path rules:
  A. a harsher above-mean factor, down to a full stop
  B. a second, deeper band for VERY extended (>8% above the mean)
  C. reaching further out of the money while extended, instead of writing less
"""
import json, math, statistics as st
exec(open("nvda_regime.py").read().split("# ── validation")[0])

def walkX(sub, aboveFac, veryFac, veryPct, otmWhenHigh):
    sh = float(START); lots = [[float(START), float(close[sub[0]])]]
    prem = 0.0; puts = []; peak = 0.0; dd = 0.0
    for i, d in enumerate(sub):
        exp = nf(d)
        if not exp: break
        S, v, T = close[d], rv[d]*IVMULT, 7/365
        for l in list(puts):
            if l["exp"] <= d:
                prem += l["p"]*100*l["ct"]
                if close[l["exp"]] < l["K"]:
                    sh += l["ct"]*100; lots.append([float(l["ct"]*100), float(l["K"])])
                puts.remove(l)
        vs = (S/ma[d] - 1) * 100
        f = mafac(S, ma[d])
        if vs >= veryPct: f = veryFac
        elif vs >= 0:     f = aboveFac
        per = min(max(0.0, TARGET-sh)/max(1, HOR-i), 2*BASE) * f
        otm = otmWhenHigh if vs >= 0 else 0.01
        K = round(S*(1-otm)/2.5)*2.5
        pd_ = pdelta(S, K, T, v); ct = max(0, round(per/(pd_*100))) if pd_ > 0 else 0
        if ct: puts.append({"K": K, "ct": ct, "exp": exp, "p": bs(S, K, T, v, "P")})
        basis = sum(q*p for q, p in lots); held = sum(q for q, _ in lots)
        mtm = S*held - basis + prem
        peak = max(peak, mtm); dd = min(dd, mtm - peak)
    Sx = close[sub[-1]]
    basis = sum(q*p for q, p in lots); held = sum(q for q, _ in lots)
    return dict(sh=sh, net=prem + (Sx*held - basis), dd=dd,
                bp=(basis/held) if held else 0)

wins = [i for i in range(0, len(FRI)-HOR)]
print("%d windows x %d weeks\n" % (len(wins), HOR))
print("%-34s %9s %10s %11s %12s" % ("arm", "shares", "basis", "net", "worst DD"))
print("-"*80)
ARMS = [
  ("above 0.60x  (today)",              0.60, 0.60, 999, 0.01),
  ("above 0.40x",                       0.40, 0.40, 999, 0.01),
  ("above 0.20x",                       0.20, 0.20, 999, 0.01),
  ("above 0.60x, STOP over +8%",        0.60, 0.00,   8, 0.01),
  ("above 0.60x, 0.20x over +8%",       0.60, 0.20,   8, 0.01),
  ("above: keep 0.60x, sell 3% out",    0.60, 0.60, 999, 0.03),
  ("above: keep 0.60x, sell 5% out",    0.60, 0.60, 999, 0.05),
]
for label, af, vf, vp, otm in ARMS:
    rs = [walkX(FRI[i:i+HOR], af, vf, vp, otm) for i in wins]
    n = len(rs)//2
    sh = sorted(r["sh"] for r in rs); nt = sorted(r["net"] for r in rs)
    bp = sorted(r["bp"] for r in rs); dd = sorted(r["dd"] for r in rs)
    print("%-34s %9s %10s %11s %12s" % (label, format(int(sh[n]), ","), "$%.2f" % bp[n],
          "$%s" % format(int(nt[n]), ","), "$%s" % format(int(dd[n]), ",")))
