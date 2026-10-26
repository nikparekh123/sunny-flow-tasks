"""Forward test, TSLA, built from REAL weeks (Nik, 18 Oct 2026). Model research, not advice.
Same setup as forward.py (with both fixes). Each 3-month path is TSLA's actual weeks since Oct 2024 in
random order, keeping each day's real overnight gap and intraday move: Safe = the calmest third of
weeks, Moderate = all weeks, Wild = the most volatile third. No scaling. Option prices at Friday's
implied volatility x 0.8 / 1 / 1.5. Exercised shares bought back at that close, or the next open.
Usage: python3 forward_real.py"""
import json, math, random, datetime as dt, statistics as stt
from forward import *
PUT_N = 15     # puts bought (Nik 18 Oct: test 10 at the money, 6 months out)
RULE = None    # (5-day rise that triggers, 'step' | 'all10' | 'skip')
def path_run2(P, px, ivk, rebuy):
    """px: [(open, close)] per day; rebuy: 'close' (same close) or 'open' (next morning)."""
    t = P['t']; S = P['S0']; otm = NAMES[t]; slots = P['slots']; sset = set(slots)
    legs = {'shares': 0.0, 'calls sold': 0.0, 'calls bought': 0.0, 'puts bought': 0.0}
    shorts = {}; n_sold = 0
    for j, s in enumerate(P['sold']):                    # day 1: real quotes, sold at mid less half the gap
        legs['calls sold'] += 1000 * s['p'] * (1 - s['hs']) - 6.5; shorts[s['e']] = dict(K=s['K'], iv=s['iv']); n_sold += 1
    pu = P['put']; legs['puts bought'] -= PUT_N * 100 * pu['p'] * (1 + pu['hs']) + PUT_N * 0.65
    cl = dict(e=P['call']['e'], K=P['call']['K'], iv0=P['call']['iv'], n=0)
    def ivf(i, base):
        ramp = min(1.0, (i + 1) / 10); return base * (1 + (ivk - 1) * ramp)
    def cb_counts(Sx, i, day):
        base = lambda x: 1000.0 - sum(1000 * bs(x, s_['K'], yrs(day, e), ivf(i, s_['iv']))[1] for e, s_ in shorts.items() if e > day)
        dl = lambda x: 100 * bs(x, cl['K'], yrs(day, cl['e']), ivf(i, cl['iv0']))[1]
        m = P['move']; b_dn, b_up, a_dn, a_up = base(Sx * (1 - m)), base(Sx * (1 + m)), dl(Sx * (1 - m)), dl(Sx * (1 + m))
        cb = lambda n: min(b_dn + n * a_dn, b_up + n * a_up)
        n0 = max(0, round(max(-b_dn / a_dn if a_dn > 0 else 0, -b_up / a_up if a_up > 0 else 0)))
        return cb, min((n for n in (n0 - 1, n0, n0 + 1) if n >= 0), key=lambda n: abs(cb(n)))
    cbf, n = cb_counts(S, -1, DAY0)
    legs['calls bought'] -= n * 100 * P['call']['p'] * (1 + P['call']['hs']) + 0.65 * n; cl['n'] = n
    hs_s, hs_c = P['hs_short'], P['call']['hs']
    week_last = {max(x for x in slots if D(x).isocalendar()[:2] == D(s).isocalendar()[:2]) for s in slots}
    S_prev = S
    for i, day in enumerate(days):
        S = px[i][1]
        if day in shorts:
            s = shorts.pop(day)
            if S > s['K']:          # exercised: shares go at K; bought back at this close, or at the next open
                buy = px[i + 1][0] if rebuy == 'open' and i + 1 < len(px) else S
                legs['calls sold'] -= (buy - s['K']) * 1000 + 5
        if day in sset:
            k = slots.index(day)
            for e in slots[k + 3:k + 4]:
                T = yrs(day, e); iv = ivf(i, P['iv_short'])
                atm = n_sold % 3 == 0; n_sold += 1
                prev = ([P['pre5'][j] for j in range(5)] + [c for _, c in px[:i]])[-5]    # the close 5 sessions back
                if RULE and S / prev - 1 >= RULE[0]:                                      # further out after a big up week
                    if RULE[1] == 'skip': continue
                    K = S * (1 + (otm if atm else 0.10)) if RULE[1] == 'step' else S * 1.10
                else: K = S if atm else S * (1 + otm)
                p = bs(S, K, T, iv)[0]; legs['calls sold'] += 1000 * p * (1 - hs_s) - 6.5; shorts[e] = dict(K=K, iv=P['iv_short'])
        if (D(cl['e']) - D(day)).days <= 10:            # roll the calls bought
            v = bs(S, cl['K'], yrs(day, cl['e']), ivf(i, cl['iv0']))[0]
            legs['calls bought'] += cl['n'] * 100 * v * (1 - hs_c) - 0.65 * cl['n']
            ne = (D(day) + dt.timedelta(days=30)); ne = ne + dt.timedelta(days=(4 - ne.weekday()) % 7)
            cl = dict(e=ne.isoformat(), K=S, iv0=P['call']['iv'], n=0)
            cbf, n = cb_counts(S, i, day); p = bs(S, S, yrs(day, cl['e']), ivf(i, cl['iv0']))[0]
            legs['calls bought'] -= n * 100 * p * (1 + hs_c) + 0.65 * n; cl['n'] = n
        elif day in week_last:
            if bs(S, cl['K'], yrs(day, cl['e']), ivf(i, cl['iv0']))[1] < 0.20:     # fix 1: re-strike
                v = bs(S, cl['K'], yrs(day, cl['e']), ivf(i, cl['iv0']))[0]
                legs['calls bought'] += cl['n'] * 100 * v * (1 - hs_c) - 0.65 * cl['n']
                ne = (D(day) + dt.timedelta(days=30)); ne = ne + dt.timedelta(days=(4 - ne.weekday()) % 7)
                cl = dict(e=ne.isoformat(), K=S, iv0=P['call']['iv'], n=0)
            cbf, n = cb_counts(S, i, day)
            if not (-150 <= cbf(cl['n']) <= 150):
                p = bs(S, cl['K'], yrs(day, cl['e']), ivf(i, cl['iv0']))[0]; dn = n - cl['n']
                legs['calls bought'] -= dn * 100 * p * (1 + (hs_c if dn > 0 else -hs_c)) + 0.65 * abs(dn); cl['n'] = n
    i = len(days) - 1; day = days[-1]
    legs['calls sold'] -= sum(1000 * bs(S, s['K'], yrs(day, e), ivf(i, s['iv']))[0] for e, s in shorts.items() if e > day)
    legs['calls bought'] += cl['n'] * 100 * bs(S, cl['K'], yrs(day, cl['e']), ivf(i, cl['iv0']))[0]
    if pu['e'] > day:      # a longer put still has time left at the end: sold at its value less half the gap
        legs['puts bought'] += PUT_N * 100 * pput(S, pu['K'], yrs(day, pu['e']), ivf(i, pu['iv'])) * (1 - pu['hs']) - PUT_N * 0.65
    else: legs['puts bought'] += PUT_N * 100 * max(0, pu['K'] - S)
    legs['shares'] = 1000 * (S - P['S0'])
    return legs, S / P['S0'] - 1


def real_weeks():
    o = json.load(open(os.path.join(DATA, 'TSLA_ohlc.json'))); ds = sorted(d for d in o if d >= '2024-10-01'); wk = {}
    for p, d in zip(ds, ds[1:]):
        wk.setdefault(dt.date.fromisoformat(d).isocalendar()[:2], []).append((math.log(o[d]['o'] / o[p]['c']), math.log(o[d]['c'] / o[d]['o'])))
    weeks = [v for v in wk.values() if len(v) >= 4]
    weeks.sort(key=lambda w: sum((a + b) ** 2 for a, b in w) / len(w)); n = len(weeks)
    pools = {'Safe': weeks[:n // 3], 'Moderate': weeks, 'Wild': weeks[2 * n // 3:]}
    # Drift removed per pool (as in forward.py): the wild third of real weeks leans up, which would
    # turn 'Wild' into a rally. Taken off the intraday part so the real overnight gaps stay as they were.
    for k, pool in pools.items():
        mu = sum(a + b for w in pool for a, b in w) / sum(len(w) for w in pool)
        pools[k] = [[(a, b - mu) for a, b in w] for w in pool]
    return pools

if __name__ == '__main__':
    P = setup('TSLA'); W = real_weeks(); rng = random.Random(11); out = {}
    IVK = {'Safe': 0.8, 'Moderate': 1.0, 'Wild': 1.5}
    for sc, pool in W.items():
        paths = []
        for _ in range(NPATH):
            days_ = []
            while len(days_) < len(days): days_ += rng.choice(pool)
            S = P['S0']; px = []
            for on, intr in days_[:len(days)]:
                o_ = S * math.exp(on); S = o_ * math.exp(intr); px.append((o_, S))
            paths.append(px)
        out[sc] = {}
        for rebuy in ('close', 'open'):
            rs = sorted(((sum(l.values()), l, px[-1][1] / P['S0'] - 1, px) for px in paths for l, _ in [path_run2(P, px, IVK[sc], rebuy)]), key=lambda x: x[0])
            med, bad = rs[len(rs) // 2], rs[len(rs) // 10]
            out[sc][rebuy] = dict(typical=dict(legs=med[1], total=med[0], move=med[2]), bad=dict(legs=bad[1], total=bad[0], move=bad[2]),
                                  mean=stt.mean(r[0] for r in rs), worst=rs[0][0],
                                  bad_path=[round(c, 2) for _, c in bad[3]][4::5], typical_path=[round(c, 2) for _, c in med[3]][4::5])
            avg = {a: stt.mean(r[1][a] for r in rs) for a in rs[0][1]}
            out[sc][rebuy]['avg_legs'] = avg; out[sc][rebuy]['median'] = med[0]; out[sc][rebuy]['p10'] = bad[0]
            mv = sorted(r[2] for r in rs)
            print(f"{sc:8s} rebuy {rebuy:5s} AVG " + ' '.join(f"{a} {v/1000:7.1f}K" for a, v in avg.items()) + f" | avg total {sum(avg.values())/1000:7.1f}K middle {med[0]/1000:7.1f}K bad1in10 {bad[0]/1000:7.1f}K worst {rs[0][0]/1000:7.1f}K | moves 10/50/90% {mv[len(mv)//10]*100:5.1f}/{mv[len(mv)//2]*100:5.1f}/{mv[len(mv)*9//10]*100:5.1f}%", flush=True)
    json.dump(out, open(os.path.join(DATA, 'forward_real.json'), 'w'), indent=1)
