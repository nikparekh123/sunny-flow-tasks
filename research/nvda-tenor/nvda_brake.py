# -*- coding: utf-8 -*-
"""What does an earnings brake cost, and what does it buy?

The engine damps conviction 12 points before a heavy event and NVDA's conviction
weight is ZERO, so today the brake does literally nothing. Before wiring a real one,
measure it: the earnings test already concluded PLAY THROUGH -- the option side net
-$808 over eight prints and skipping forfeited 8% of the year's accumulation. A brake
is a partial skip, so it inherits that arithmetic and has to earn its keep on risk.
"""
import json, math, statistics as st
from statistics import NormalDist
exec(open("nvda_regime.py").read().split("# ── validation")[0])   # bars, bs, walk helpers

EARN = ['2024-08-28','2024-11-20','2025-02-26','2025-05-28',
        '2025-08-27','2025-11-19','2026-02-25','2026-05-27']
def daysToEarn(d):
    later = [e for e in EARN if e >= d]
    if not later: return 999
    a = datetime.date.fromisoformat(d); b = datetime.date.fromisoformat(later[0])
    return (b - a).days

def walkBrake(sub, brakeMult, brakeDays):
    sh = float(START); lots = [[float(START), float(close[sub[0]])]]
    prem = 0.0; puts = []; peak = 0.0; trough = 0.0
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
        per = min(max(0.0, TARGET-sh)/max(1, HOR-i), 2*BASE) * mafac(S, ma[d])
        if daysToEarn(d) <= brakeDays: per *= brakeMult          # the brake
        K = round(S*0.99/2.5)*2.5
        pd_ = pdelta(S, K, T, v); ct = max(0, round(per/(pd_*100))) if pd_ > 0 else 0
        if ct: puts.append({"K": K, "ct": ct, "exp": exp, "p": bs(S, K, T, v, "P")})
        basis = sum(q*p for q, p in lots); held = sum(q for q, _ in lots)
        mtm = S*held - basis + prem
        peak = max(peak, mtm); trough = min(trough, mtm - peak)   # worst drawdown from peak
    Sx = close[sub[-1]]
    basis = sum(q*p for q, p in lots); held = sum(q for q, _ in lots)
    return dict(sh=sh, net=prem + (Sx*held - basis), dd=trough,
                basisPer=(basis/held) if held else 0)

wins = [i for i in range(0, len(FRI)-HOR) if FRI[i+HOR-1] >= EARN[0] and FRI[i] <= EARN[-1]]
print("%d windows x %d weeks. Brake applies in the N days BEFORE each print.\n" % (len(wins), HOR))
print("%-22s %9s %10s %11s %12s" % ("arm", "shares", "basis", "net", "worst DD"))
print("-"*68)
for label, mult, bd in (("no brake", 1.0, 0),
                          ("0.50x, 5d before", 0.5, 5),
                          ("0.25x, 5d before", 0.25, 5),
                          ("pause, 5d before", 0.0, 5),
                          ("0.50x, 10d before", 0.5, 10),
                          ("pause, 10d before", 0.0, 10)):
    rs = [walkBrake(FRI[i:i+HOR], mult, bd) for i in wins]
    sh = sorted(r["sh"] for r in rs); nt = sorted(r["net"] for r in rs)
    bp = sorted(r["basisPer"] for r in rs); dd = sorted(r["dd"] for r in rs)
    n = len(rs)//2
    print("%-22s %9s %10s %11s %12s" % (label, format(int(sh[n]), ","), "$%.2f" % bp[n],
          "$%s" % format(int(nt[n]), ","), "$%s" % format(int(dd[n]), ",")))
