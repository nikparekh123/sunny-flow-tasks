"""All ten names x the combination tables. Writes data/results.json."""
import sys, os, json, time
from block import *
NAMES = sys.argv[1:] or ['NKE', 'LULU', 'BABA', 'NFLX', 'ADBE', 'INTU', 'SPCX', 'TSLA', 'PYPL', 'APP']
def mk(t, long_r=0, short_r=0, put_rule=('otm', 0.02), call_r=1.0, call_z=0.6, qtr_r=0, year_r=0, floor=None):
    nL = LEAP[t][0]
    return B(long_n=nL * long_r, short_n=nL * short_r, put_rule=put_rule, call_n=nL * call_r, call_z=call_z,
             qtr_n=nL * qtr_r, year_n=nL * year_r, delta_floor=floor)
H = dict(long_r=1/2, short_r=1/4)
TABLES = [
    ('puts', 'How many puts to buy (and sell half that many each week)', [
        ('Today: no puts', {}), ('Buy 1/3, sell 1/6', dict(long_r=1/3, short_r=1/6)), ('Buy 1/2, sell 1/4', H), ('Buy 1/2, sell none', dict(long_r=1/2))]),
    ('putstrike', 'Where to sell the weekly puts (buying 1/2, selling 1/4)', [
        ('At the money', dict(H, put_rule=('atm',))), ('2% out', H), ('5% out', dict(H, put_rule=('otm', 0.05))),
        ('0.6 SD out', dict(H, put_rule=('sd', 0.6))), ('1 SD out', dict(H, put_rule=('sd', 1.0))), ('30% ATM + 70% at 0.6 SD', dict(H, put_rule=('split', 0.3, 0.6)))]),
    ('callstrike', 'Where to sell the calls (30% at the money, the rest out)', [
        ('Rest at 0.6 SD', H), ('Rest at 1 SD', dict(H, call_z=1.0))]),
    ('callcount', 'How many calls to sell', [
        ('All', H), ('80%', dict(H, call_r=0.8)), ('70%', dict(H, call_r=0.7)), ('60%', dict(H, call_r=0.6)),
        ('Only while delta stays above +20%', dict(H, floor=0.2))]),
    ('extra', 'Extra upside for a big jump', [
        ('None', H), ('Quarterly 15% OTM calls, 1/6', dict(H, qtr_r=1/6)), ('Quarterly 15% OTM calls, 1/3', dict(H, qtr_r=1/3)),
        ('1-year 30% OTM calls, 1/6', dict(H, year_r=1/6)), ('1-year 30% OTM calls, 1/3', dict(H, year_r=1/3))]),
]
def key(d): return json.dumps(d, sort_keys=True)
def avg9(r): return float(np.mean([r[s] for s in SCENS]))
OUT = 'data/results_hold.json' if os.environ.get('RHO_MODE') == 'hold' else 'data/results.json'
out = json.load(open(OUT)) if len(sys.argv) > 1 else {}
for t in NAMES:
    t0 = time.time(); memo = {}
    def get(d):
        k = key(d)
        if k not in memo:
            r = summary(t, mk(t, **d)); r['avg'] = avg9(r); memo[k] = r
        return memo[k]
    res = {'spot': SPOT[t], 'leap': list(LEAP[t]), 'held': PRM[t]['held'], 'tables': []}
    for tid, title, cols in TABLES:
        res['tables'].append({'id': tid, 'title': title, 'cols': [{'name': nm, 'spec': d, 'r': get(d)} for nm, d in cols]})
    # best combination: among hedged choices that at least halve today's 30%-crash loss, the best average on the no-view paths
    base_crash = get({})['crash 30% in 2m']
    def ok(d):
        r = get(d); c = r['crash 30% in 2m']
        return d.get('long_r', 0) > 0 and (c >= 0.5 * base_crash if base_crash < 0 else c >= base_crash)
    def pick(cands):
        good = [d for d in cands if ok(d)]
        return max(good, key=lambda d: get(d)['no view']) if good else max(cands, key=lambda d: get(d)['crash 30% in 2m'])
    T_ = {tb[0]: [d for _, d in tb[2]] for tb in TABLES}
    best = dict(pick([d for d in T_['puts'] if d.get('long_r')]))
    for tid, fields in (('putstrike', ['put_rule']), ('callstrike', ['call_z']), ('callcount', ['call_r', 'floor']), ('extra', ['qtr_r', 'year_r'])):
        w = pick(T_[tid])
        for f in fields:
            if f in w: best[f] = w[f]
    if best.get('short_r', 0) == 0: best.pop('put_rule', None)
    cands = [best] + [d for tb in TABLES for _, d in tb[2] if d.get('long_r')]
    fin = pick(cands)
    res['best'] = {'spec': fin, 'r': get(fin), 'combined_spec': best, 'combined_r': get(best)}
    out[t] = res
    json.dump(out, open(OUT, 'w'))
    print(t, 'done', round(time.time() - t0), 's', 'best', fin, {s: round(get(fin)[s] / 1000, 1) for s in ('flat', 'crash 30% in 2m', 'no view')}, 'today', {s: round(get({})[s] / 1000, 1) for s in ('flat', 'crash 30% in 2m', 'no view')}, flush=True)
