"""Puts: 15 at the money 3 months out (today) vs 10 at the money 6 months out (Nik, 18 Oct 2026).
Model research, not advice. (1) Real-weeks forward test, same 500 paths per version as further_out.py,
next-morning buy-back; the 6-month puts are sold back at their value after the 3 months. (2) Real TSLA
puts Feb-Oct 2026: 6-month puts either held to expiry, or rolled with 3 months left (sold, new 6-month
bought), each round at the money. Usage: python3 puts_test.py"""
import json, math, statistics as stt
import further_out as FO, forward_real as FR
from sim import theta, D, yrs
def put_chain(e, day):
    q = {}
    for c in theta(f"/v3/option/history/eod?symbol=TSLA&expiration={e.replace('-', '')}&right=put&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
        for x in c.get('data', []):
            if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[float(c['contract']['strike'])] = (x['bid'], x['ask'])
    return q
def put_iv(px_, S, K, T):
    lo, hi = 0.01, 5
    for _ in range(60):
        m = (lo + hi) / 2; lo, hi = (m, hi) if FR.pput(S, K, T, m) < px_ else (lo, m)
    return (lo + hi) / 2
# forward: today's 15 x Jan-2027 vs 10 x Apr-2027 (6 months) at the money, real 16 Oct quotes
P = FO.P; q6 = put_chain('2027-04-16', '2026-10-16'); K6 = min(q6, key=lambda k: abs(k - P['S0'])); b, a = q6[K6]
put6 = dict(e='2027-04-16', K=K6, p=(b + a) / 2, iv=put_iv((b + a) / 2, P['S0'], K6, yrs('2026-10-16', '2027-04-16')), hs=(a - b) / 2 / ((a + b) / 2))
print('6-month put', put6, 'cost of 10', round(1000 * put6['p']), '| 3-month put', P['put'], 'cost of 15', round(1500 * P['put']['p']))
FR.RULE = None; res = {}
for lab, n, pu in (('15 x 3 months', 15, P['put']), ('10 x 6 months', 10, put6)):
    FR.PUT_N = n; P2 = dict(P, put=pu); res[lab] = {}
    for sc, ps in FO.PATHS.items():
        rs = [FR.path_run2(P2, px, FO.IVK[sc], 'open')[0] for px in ps]
        tot = sorted(sum(l.values()) for l in rs)
        res[lab][sc] = dict(avg=stt.mean(tot), puts=stt.mean(l['puts bought'] for l in rs), bad=tot[len(tot) // 10], worst=tot[0])
    print(lab, {sc: {k: round(v / 1000, 1) for k, v in r.items()} for sc, r in res[lab].items()}, flush=True)
# real Feb-Oct 2026
d = json.load(open('data/TSLA.json')); C = d['closes']; exps = d['exps']
monthly = lambda x: 15 <= D(x).day <= 21 and D(x).weekday() == 4 or 14 <= D(x).day <= 20 and D(x).weekday() == 3
def buy(day):
    S = C[day]
    for e in sorted([x for x in exps if monthly(x) and (D(x) - D(day)).days >= 150], key=lambda x: abs((D(x) - D(day)).days - 182))[:4]:
        q = put_chain(e, day)
        if q: K = min(q, key=lambda k: abs(k - S)); return dict(d=day, S=S, e=e, K=K, b=q[K][0], a=q[K][1])
def value(l, day):
    if day >= l['e']: v = max(0, l['K'] - C[max(x for x in C if x <= l['e'])]); return v, v
    q = put_chain(l['e'], day).get(l['K']); return (sum(q) / 2, q[0]) if q else (None, None)
END = '2026-10-16'; ds = sorted(C)
for mode in ('hold to expiry', 'roll with 3 months left'):
    day = '2026-02-02'; tm = tb = 0; log = []
    while True:
        l = buy(day); stop = l['e'] if mode == 'hold to expiry' else max(x for x in exps if (D(l['e']) - D(x)).days >= 91 and x <= l['e'])
        sell_day = min(stop, END); sell_day = max(x for x in ds if x <= sell_day)
        vm, vb = value(l, sell_day)
        pm = 1000 * (vm - (l['b'] + l['a']) / 2) - 13; pb = 1000 * (vb - l['a']) - 13; tm += pm; tb += pb
        log.append(f"{l['d']} TSLA {l['S']:.0f}: 10 x {l['e']} ${l['K']:g} at {(l['b'] + l['a']) / 2:.2f} -> {sell_day} worth {vm:.2f}: {pm:+,.0f}")
        if sell_day >= END or stop > END: break
        day = min(x for x in ds if x >= stop)
    res['real ' + mode] = dict(mid=tm, ba=tb, log=log)
    print(mode, round(tm), round(tb)); [print('   ', x) for x in log]
json.dump(res, open('data/puts_test.json', 'w'), indent=1)
