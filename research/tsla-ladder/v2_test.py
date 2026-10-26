"""Version 2, no shares (Nik, 18 Oct 2026). Model research, not advice.
33 LEAPs (~2 years, ~75 delta, held); 11-month calls sold at ~30 delta (start 15); weekly calls: three
sets always open (Mon/Wed/Fri), each expiry day 10 sold on the next expiry, rotating 1.5% / 4% / 7% out;
a weekly call that finishes in the money is bought back at its expiry close. Each Friday: 11-month lots
up 50%+ are closed and replaced by new 30-delta ones; then 11-month calls are sold or bought back so
'could be' (the lower net delta after an instant 5% move) sits in 0..+300 (aim +150). No puts.
(1) Real TSLA quotes 2 Feb - 16 Oct 2026. (2) Forward 3 months on real TSLA weeks (same 500 paths as
further_out.py), weeklies at 41% implied volatility (TSLA's 2026 median outside earnings) x 0.8 / 1 / 1.5.
Usage: python3 v2_test.py"""
import json, math, os, statistics as stt
from ladder_b import Q, data, bs, iv_of, yrs, D, DATA
from struct_test import by_delta, monthly
ROT = (0.015, 0.04, 0.07); NLEAP = 33; IVW = 0.41

def fridays(sl): return {max(x for x in sl if D(x).isocalendar()[:2] == D(s).isocalendar()[:2]) for s in sl}

def manage(day, S, lots, delta_of, value_of, new_lot, base_dn, base_up, legs, buy_px, sell_px):
    """Take profit at 50%, then keep 'could be' in 0..300 by selling more / buying back 11-month calls."""
    for lot in [l for l in lots if l['n'] > 0 and value_of(l) <= 0.5 * l['p']]:
        legs['long_sold'] -= lot['n'] * 100 * buy_px(lot) + 0.65 * lot['n']
        nl = new_lot(); nl['n'] = lot['n']; legs['long_sold'] += nl['n'] * 100 * nl['sp'] - 0.65 * nl['n']
        lot['n'] = 0; lots.append(nl)
    lots[:] = [l for l in lots if l['n'] > 0]
    cb = lambda extra, x_dn, x_up: min(base_dn - sum(l['n'] * 100 * delta_of(l, S * 0.95) for l in lots) - extra * x_dn,
                                       base_up - sum(l['n'] * 100 * delta_of(l, S * 1.05) for l in lots) - extra * x_up)
    if not (0 <= cb(0, 0, 0) <= 300):
        nl = new_lot(); x_dn, x_up = 100 * delta_of(nl, S * 0.95), 100 * delta_of(nl, S * 1.05)
        if cb(0, 0, 0) > 300:                                    # too long: sell more
            k = min(range(0, 400), key=lambda k: abs(cb(k, x_dn, x_up) - 150))
            if k: nl['n'] = k; legs['long_sold'] += k * 100 * nl['sp'] - 0.65 * k; lots.append(nl)
        else:                                                    # too short: buy back, newest first
            for l in sorted(lots, key=lambda l: l['d'], reverse=True):
                ld, lu = 100 * delta_of(l, S * 0.95), 100 * delta_of(l, S * 1.05)
                while l['n'] > 0 and cb(0, 0, 0) < 150:
                    legs['long_sold'] -= 100 * buy_px(l) + 0.65; l['n'] -= 1
                if cb(0, 0, 0) >= 150: break
            lots[:] = [l for l in lots if l['n'] > 0]

def real(fill):
    d = data('TSLA'); C = d['closes']; exps = d['exps']; M = Q('TSLA')
    SELL = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    BUY = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    sl = [s for s, _ in d['slots'] if '2026-02-02' <= s <= '2026-10-16']; fr = fridays(sl)
    legs = dict(weekly=0.0, leaps=0.0, long_sold=0.0); shorts = {}; n = 0; lots = []; trades = 0
    S0 = C[sl[0]]; L = by_delta(M, exps, sl[0], S0, 720, 0.75, 540)
    legs['leaps'] -= NLEAP * 100 * BUY(*L['q']) + 0.65 * NLEAP
    def lot_q(l, day): return M.hist(l['e'], l['K'], l['d']).get(day)
    for i, day in enumerate(sl):
        S = C[day]
        if day in shorts:
            K = shorts.pop(day)
            if S > K: legs['weekly'] -= (S - K) * 1000 + 6.5
        for e in (sl[1:4] if i == 0 else sl[i + 3:i + 4]):
            q = {float(k): v for k, v in d['q'].get(f'{day}|{e}', {}).items() if v[0] > 0} or M.chain(e, day)
            if not q: n += 1; continue
            ks = sorted(q); K = next((k for k in ks if k >= S * (1 + ROT[n % 3])), ks[-1]); n += 1
            legs['weekly'] += SELL(*q[K]) * 1000 - 6.5; shorts[e] = K
            shorts.setdefault('_d', {})[e] = (K, day)
        def new_lot():
            X = by_delta(M, exps, day, S, 330, 0.30, 270)
            v = iv_of(sum(X['q']) / 2, S, X['K'], yrs(day, X['e'])) or 0.45
            return dict(e=X['e'], K=X['K'], d=day, p=sum(X['q']) / 2, sp=SELL(*X['q']), iv=v, n=0)
        if i == 0:
            nl = new_lot(); nl['n'] = 15; legs['long_sold'] += 15 * 100 * nl['sp'] - 9.75; lots.append(nl)
        if day in fr or i == 0:
            def iv_now(e, K, a, fb):
                q = M.hist(e, K, a).get(day); return (iv_of(sum(q) / 2, S, K, yrs(day, e)) if q else None) or fb
            ivL = iv_now(L['e'], L['K'], sl[0], 0.48)
            base = lambda x: NLEAP * 100 * bs(x, L['K'], yrs(day, L['e']), ivL)[1] - sum(
                1000 * bs(x, K, yrs(day, e), iv_now(e, K, shorts['_d'][e][1], 0.42))[1] for e, K in shorts.items() if e != '_d' and e > day)
            delta_of = lambda l, x: bs(x, l['K'], yrs(day, l['e']), iv_now(l['e'], l['K'], l['d'], l['iv']))[1]
            value_of = lambda l: (sum(lot_q(l, day)) / 2) if lot_q(l, day) else l['p']
            buy_px = lambda l: BUY(*lot_q(l, day)) if lot_q(l, day) else l['p']
            before = sum(l['n'] for l in lots)
            manage(day, S, lots, delta_of, value_of, new_lot, base(S * 0.95), base(S * 1.05), legs, buy_px, SELL)
            trades += sum(l['n'] for l in lots) != before
    end = sl[-1]; S1 = C[end]
    for e, K in shorts.items():
        if e != '_d' and e > end:
            q = M.hist(e, K, shorts['_d'][e][1]).get(end); legs['weekly'] -= 1000 * (BUY(*q) if q else max(0, S1 - K))
    legs['leaps'] += NLEAP * 100 * SELL(*M.hist(L['e'], L['K'], sl[0]).get(end)) - 0.65 * NLEAP
    for l in lots:
        q = lot_q(l, end); legs['long_sold'] -= l['n'] * 100 * (BUY(*q) if q else l['p']) + 0.65 * l['n']
    M.save()
    return legs, dict(S0=S0, S1=S1, leap=f"{L['e']} ${L['K']:g} at {sum(L['q'])/2:.2f}", lots_end=[(l['e'], l['K'], l['n']) for l in lots])

def forward():
    import further_out as FO, forward_real as FR
    P = FO.P; days = FR.days; slots = P['slots']; sset = set(slots); fr = fridays([s for s in slots if s <= days[-1]])
    LEAP = dict(K=300, e='2028-01-21', p=108.0); XC = dict(K=500, e='2027-09-17', p=24.50)
    for c in (LEAP, XC): c['iv'] = iv_of(c['p'], P['S0'], c['K'], yrs('2026-10-16', c['e']))
    hs_w, hs_l = P['hs_short'], 0.01; out = {}
    for sc, ps in FO.PATHS.items():
        ivk = FO.IVK[sc]; res = []
        for px in ps:
            ivf = lambda i, base: base * (1 + (ivk - 1) * min(1.0, (i + 1) / 10))
            legs = dict(weekly=0.0, leaps=-NLEAP * 100 * LEAP['p'] * (1 + hs_l) - 0.65 * NLEAP, long_sold=0.0)
            shorts = {}; n = 0; S = P['S0']
            lots = [dict(e=XC['e'], K=XC['K'], d='2026-10-16', p=XC['p'], sp=XC['p'] * (1 - hs_l), iv=XC['iv'], n=15)]
            legs['long_sold'] += 15 * 100 * XC['p'] * (1 - hs_l) - 9.75
            for e in slots[:3]:
                K = S * (1 + ROT[n % 3]); n += 1
                legs['weekly'] += 1000 * bs(S, K, yrs('2026-10-16', e), IVW)[0] * (1 - hs_w) - 6.5; shorts[e] = K
            for i, day in enumerate(days):
                S = px[i][1]
                if day in shorts:
                    K = shorts.pop(day)
                    if S > K: legs['weekly'] -= (S - K) * 1000 + 6.5
                if day in sset:
                    k = slots.index(day)
                    for e in slots[k + 3:k + 4]:
                        K = S * (1 + ROT[n % 3]); n += 1
                        legs['weekly'] += 1000 * bs(S, K, yrs(day, e), ivf(i, IVW))[0] * (1 - hs_w) - 6.5; shorts[e] = K
                if day in fr:
                    ivX = ivf(i, XC['iv'])
                    def new_lot():
                        T = yrs(day, XC['e']); lo, hi = S, S * 3                 # strike at 30 delta
                        for _ in range(40):
                            m = (lo + hi) / 2; lo, hi = (m, hi) if bs(S, m, T, ivX)[1] > 0.30 else (lo, m)
                        p = bs(S, lo, T, ivX)[0]; return dict(e=XC['e'], K=lo, d=day, p=p, sp=p * (1 - hs_l), iv=XC['iv'], n=0)
                    base = lambda x: NLEAP * 100 * bs(x, LEAP['K'], yrs(day, LEAP['e']), ivf(i, LEAP['iv']))[1] - sum(
                        1000 * bs(x, K, yrs(day, e), ivf(i, IVW))[1] for e, K in shorts.items() if e > day)
                    delta_of = lambda l, x: bs(x, l['K'], yrs(day, l['e']), ivX)[1]
                    value_of = lambda l: bs(S, l['K'], yrs(day, l['e']), ivX)[0]
                    buy_px = lambda l: value_of(l) * (1 + hs_l)
                    manage(day, S, lots, delta_of, value_of, new_lot, base(S * 0.95), base(S * 1.05), legs, buy_px, None)
            i = len(days) - 1; day = days[-1]
            legs['weekly'] -= sum(1000 * bs(S, K, yrs(day, e), ivf(i, IVW))[0] for e, K in shorts.items() if e > day)
            legs['leaps'] += NLEAP * 100 * bs(S, LEAP['K'], yrs(day, LEAP['e']), ivf(i, LEAP['iv']))[0] * (1 - hs_l) - 0.65 * NLEAP
            legs['long_sold'] -= sum(l['n'] * 100 * bs(S, l['K'], yrs(day, l['e']), ivf(i, XC['iv']))[0] * (1 + hs_l) + 0.65 * l['n'] for l in lots)
            res.append(legs)
        tot = sorted(sum(l.values()) for l in res)
        out[sc] = dict(avg_legs={k: stt.mean(l[k] for l in res) for k in res[0]}, avg=stt.mean(tot), mid=tot[len(tot) // 2], bad=tot[len(tot) // 10], worst=tot[0])
    return out

if __name__ == '__main__':
    R = {}
    for fill in ('mid', 'worse'):
        legs, info = real(fill); R['real_' + fill] = dict(legs=legs, info=info)
        print('REAL', fill, {k: round(v) for k, v in legs.items()}, 'total', round(sum(legs.values())), info, flush=True)
    F = forward(); R['forward'] = F
    for sc, o in F.items():
        print(f"FWD {sc:8s} " + ' '.join(f"{k} {v/1000:7.1f}K" for k, v in o['avg_legs'].items()) + f" | avg {o['avg']/1000:6.1f}K middle {o['mid']/1000:6.1f}K bad {o['bad']/1000:7.1f}K worst {o['worst']/1000:7.1f}K", flush=True)
    json.dump(R, open(os.path.join(DATA, 'v2_test.json'), 'w'), indent=1)
