"""Study 1, forward test (Nik, 17 Oct 2026): how much delta should NKE keep?
Today's NKE book on the itm-puts engine (12 months, 300 made-up paths per
scenario, real chains for day one): 60 LEAPs (Jan 2028 30C), 25 hedge puts ~8%
in the money (March, rolled), 13 weekly puts 2% out, upside 5 three-month calls
~15% out (rolled) + 15 one-year calls ~30% out, weekly calls by our rule
(a third at the money, 20% in an earnings week, the rest 0.6 SD, 1 SD after a
15%+ month). The arm sets the DELTA FLOOR: each Friday sell only as many calls
(up to 60) as keep net delta at least that share of the 6,000 LEAP shares.
Run from research/itm-puts:  python3 -I ../target-study/nke_forward.py"""
import sys, os, json, numpy as np
sys.path.insert(0, os.getcwd())
from block import *

ARMS = [('sell all 60', None), ('keep 10%', 0.10), ('keep 20%', 0.20), ('keep 30%', 0.30), ('keep 40%', 0.40)]
SC = ['flat', 'up 15%', 'bull +40%', 'jump 30% in 1m', 'down 15%', 'crash 30% in 2m', 'no view']
book = dict(long_n=25, itm=0.08, tenor=5, short_n=13, put_rule=('otm', 0.02), call_n=60, call_atm=1 / 3, call_z=0.6,
            qtr_n=5, year_n=15)
out = {}
for lab, fl in ARMS:
    p = B(**book, delta_floor=fl)
    row = {}
    for s in SC:
        pnl, dn, _ = run('NKE', s, p, n=300)
        tot = pnl['total']; calls = pnl['calls']
        row[s] = dict(total=float(np.mean(tot) if s == 'no view' else np.median(tot)),
                      calls=float(np.mean(calls) if s == 'no view' else np.median(calls)),
                      dl=float(np.mean(dn) / 6000 * 100))
    out[lab] = row
    print(lab, {s: (round(row[s]['total'] / 1000, 1), round(row[s]['dl'])) for s in SC}, flush=True)
json.dump(out, open('../target-study/data/nke_forward_' + os.environ.get('RHO_MODE', 'fade') + '.json', 'w'), indent=1)
