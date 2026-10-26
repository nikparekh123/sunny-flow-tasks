"""Nik, 17 Oct 2026: sell MORE calls than LEAPs, about 80 at 1 sigma on 60 LEAPs
(20 uncovered). Real NKE year (rolled every Friday, mids, $0.65) and the forward
test (today's NKE book on the itm-puts engine). Usage: see the two blocks below."""
import json, math, os, sys, io, contextlib, runpy
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
if sys.argv[1:] == ['real']:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): g = runpy.run_path(os.path.join(HERE, 'playbook_replay.py'))
    D, settle, iv_of, reads = g['D'], g['settle'], g['iv_of'], g['reads']
    W = json.load(open(os.path.join(DATA, 'nke_weeklies.json')))
    for n, z in ((80, 1.0), (60, 1.0), (60, 0.8), (60, 0.6)):
        pnl = []
        for s_ in sorted(W):
            w = W[s_]; S = reads(s_)['S']; e = w['expiry']; T = max(1, (D(e) - D(s_)).days) / 365
            CQ = {float(k): (b + a) / 2 for k, (b, a) in w['C'].items() if a > 0}
            katm = min(CQ, key=lambda k: abs(k - S)); v = iv_of(CQ[katm], S, katm, T) or 0.35
            ks = sorted(k for k in CQ if k >= S + z * S * v * math.sqrt(T)); K = ks[0] if ks else max(CQ)
            pnl.append(n * 100 * (CQ[K] - max(0, settle(e) - K)) - 0.65 * n)
        print(f"real year | {n} calls at {z} sigma: ${sum(pnl):>9,.0f}  losing weeks {sum(1 for x in pnl if x < 0):2d}  worst ${min(pnl):>8,.0f}")
else:
    sys.path.insert(0, os.getcwd())
    from block import *
    import numpy as np
    book = dict(long_n=25, itm=0.08, tenor=5, short_n=13, put_rule=('otm', 0.02), qtr_n=5, year_n=15)
    SC = ['flat', 'up 15%', 'bull +40%', 'jump 30% in 1m', 'down 15%', 'crash 30% in 2m', 'no view']
    out = {}
    for lab, kw in (('80 at 1 sigma', dict(call_n=80, call_atm=0.0, call_z=1.0)), ('60 at 1 sigma', dict(call_n=60, call_atm=0.0, call_z=1.0)),
                    ("60 today's rule", dict(call_n=60, call_atm=1 / 3, call_z=0.6))):
        row = {}
        for s in SC:
            pnl, dn, _ = run('NKE', s, B(**book, **kw), n=300)
            agg = np.mean if s == 'no view' else np.median
            row[s] = dict(total=float(agg(pnl['total'])), p5=float(np.percentile(pnl['total'], 5)), short=float(np.mean(dn < 0)))
        out[lab] = row
        print(lab, {s: (round(r['total'] / 1000, 1), round(r['p5'] / 1000, 1), round(r['short'] * 100)) for s, r in row.items()}, flush=True)
    json.dump(out, open(os.path.join(DATA, 'over80_' + os.environ.get('RHO_MODE', 'fade') + '.json'), 'w'), indent=1)
