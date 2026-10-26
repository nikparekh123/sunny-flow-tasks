"""Nik's posted TSLA structure (18 Oct 2026). Model research, not advice.
1,000 shares; weekly calls: three sets always open (Mon/Wed/Fri), each expiry day 10 sold on the next
expiry, new sales rotating 1.5% / 4% / 7% out; exercised shares bought back the next morning;
20 LEAPs ~2 years out at ~75 delta, held; 15 calls sold ~11 months out at ~30 delta, held; no puts.
(1) Real TSLA quotes Feb-Oct 2026. (2) Forward 3 months on real TSLA weeks (Safe / Moderate / Wild,
same 500 paths as further_out.py), entered after earnings: weeklies at 45% implied volatility (x0.8 / 1 /
1.5), the LEAPs and the 11-month calls at Nik's 16 Oct prices. Usage: python3 struct_test.py"""
import json, math, os, statistics as stt
from ladder_b import Q, data, bs, iv_of, yrs, D, DATA
ROT = (0.015, 0.04, 0.07)
IVW = 0.45
monthly = lambda x: 15 <= D(x).day <= 21 and D(x).weekday() == 4 or 14 <= D(x).day <= 20 and D(x).weekday() == 3

def by_delta(M, exps, day, S, days_out, target, min_days):
    for e in sorted([x for x in exps if (D(x) - D(day)).days >= min_days], key=lambda x: (not monthly(x), abs((D(x) - D(day)).days - days_out)))[:8]:
        ch = M.chain(e, day); dl = {}
        for k, (b, a) in ch.items():
            v = iv_of((b + a) / 2, S, k, yrs(day, e))
            if v: dl[k] = bs(S, k, yrs(day, e), v)[1]
        if dl:
            K = min(dl, key=lambda k: abs(dl[k] - target)); return dict(e=e, K=K, q=ch[K], delta=dl[K])

def real(fill):
    d = data('TSLA'); C = d['closes']; exps = d['exps']; M = Q('TSLA')
    O = json.load(open(os.path.join(DATA, 'TSLA_ohlc.json'))); ds = sorted(C)
    SELL = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    BUY = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    sl = [s for s, _ in d['slots'] if '2026-02-02' <= s <= '2026-10-16']
    legs = dict(shares=0.0, weekly=0.0, leaps=0.0, long_sold=0.0); shorts = {}; n = 0; log = []
    S0 = C[sl[0]]
    L = by_delta(M, exps, sl[0], S0, 720, 0.75, 540); X = by_delta(M, exps, sl[0], S0, 330, 0.30, 270)
    legs['leaps'] -= 20 * 100 * BUY(*L['q']) + 13; legs['long_sold'] += 15 * 100 * SELL(*X['q']) - 9.75
    log.append(f"2 Feb TSLA {S0}: buy 20 x {L['e']} ${L['K']:g} (delta {L['delta']:.2f}) at {sum(L['q'])/2:.2f}; sell 15 x {X['e']} ${X['K']:g} (delta {X['delta']:.2f}) at {sum(X['q'])/2:.2f}")
    for i, day in enumerate(sl):
        S = C[day]
        if day in shorts:
            s = shorts.pop(day)
            if S > s['K']:
                nxt = ds[ds.index(day) + 1] if ds.index(day) + 1 < len(ds) else day
                buy = O[nxt]['o'] if nxt in O and nxt != day else S
                legs['weekly'] -= (buy - s['K']) * 1000 + 5
        for e in (sl[1:4] if i == 0 else sl[i + 3:i + 4]):
            q = {float(k): v for k, v in d['q'].get(f'{day}|{e}', {}).items() if v[0] > 0} or M.chain(e, day)
            if not q: n += 1; continue
            ks = sorted(q); pct = ROT[n % 3]; n += 1
            K = next((k for k in ks if k >= S * (1 + pct)), ks[-1])
            legs['weekly'] += SELL(*q[K]) * 1000 - 6.5; shorts[e] = dict(K=K, d=day)
    end = sl[-1]; S1 = C[end]
    for e, s in shorts.items():
        if e > end:
            q = M.hist(e, s['K'], s['d']).get(end); legs['weekly'] -= 1000 * (BUY(*q) if q else max(0, S1 - s['K']))
    qL = M.hist(L['e'], L['K'], sl[0]).get(end); qX = M.hist(X['e'], X['K'], sl[0]).get(end)
    legs['leaps'] += 20 * 100 * SELL(*qL) - 13; legs['long_sold'] -= 15 * 100 * BUY(*qX) + 9.75
    legs['shares'] = 1000 * (S1 - S0)
    log.append(f"16 Oct TSLA {S1}: LEAP worth {sum(qL)/2:.2f}, 11-month call worth {sum(qX)/2:.2f}")
    M.save(); return legs, log

def forward():
    import further_out as FO, forward_real as FR
    P = FO.P; days = FR.days; slots = P['slots']; sset = set(slots)
    LEAP = dict(K=300, e='2028-01-21', p=108.0); XC = dict(K=500, e='2027-09-17', p=24.50)
    for c in (LEAP, XC): c['iv'] = iv_of(c['p'], P['S0'], c['K'], yrs('2026-10-16', c['e']))
    hs_w, hs_l = P['hs_short'], 0.01
    out = {}
    for sc, ps in FO.PATHS.items():
        ivk = FO.IVK[sc]; res = []
        for px in ps:
            ivf = lambda i, base: base * (1 + (ivk - 1) * min(1.0, (i + 1) / 10))
            legs = dict(shares=0.0, weekly=0.0, leaps=-20 * 100 * LEAP['p'] * (1 + hs_l) - 13, long_sold=15 * 100 * XC['p'] * (1 - hs_l) - 9.75)
            shorts = {}; n = 0; S = P['S0']
            first = slots[:3]
            for e in first:
                K = S * (1 + ROT[n % 3]); n += 1
                legs['weekly'] += 1000 * bs(S, K, yrs('2026-10-16', e), IVW)[0] * (1 - hs_w) - 6.5; shorts[e] = K
            for i, day in enumerate(days):
                S = px[i][1]
                if day in shorts:
                    K = shorts.pop(day)
                    if S > K:
                        buy = px[i + 1][0] if i + 1 < len(px) else S
                        legs['weekly'] -= (buy - K) * 1000 + 5
                if day in sset:
                    k = slots.index(day)
                    for e in slots[k + 3:k + 4]:
                        K = S * (1 + ROT[n % 3]); n += 1
                        legs['weekly'] += 1000 * bs(S, K, yrs(day, e), ivf(i, IVW))[0] * (1 - hs_w) - 6.5; shorts[e] = K
            i = len(days) - 1; day = days[-1]
            legs['weekly'] -= sum(1000 * bs(S, K, yrs(day, e), ivf(i, IVW))[0] for e, K in shorts.items() if e > day)
            legs['leaps'] += 20 * 100 * bs(S, LEAP['K'], yrs(day, LEAP['e']), ivf(i, LEAP['iv']))[0] * (1 - hs_l) - 13
            legs['long_sold'] -= 15 * 100 * bs(S, XC['K'], yrs(day, XC['e']), ivf(i, XC['iv']))[0] * (1 + hs_l) + 9.75
            legs['shares'] = 1000 * (S - P['S0'])
            res.append(legs)
        tot = sorted(sum(l.values()) for l in res); sh = sorted(l['shares'] for l in res)
        out[sc] = dict(avg_legs={k: stt.mean(l[k] for l in res) for k in res[0]}, avg=stt.mean(tot), mid=tot[len(tot) // 2],
                       bad=tot[len(tot) // 10], worst=tot[0], sh_avg=stt.mean(sh), sh_bad=sh[len(sh) // 10])
    return out

if __name__ == '__main__':
    R = {}
    for fill in ('mid', 'worse'):
        legs, log = real(fill); R['real_' + fill] = legs
        print('REAL', fill, {k: round(v) for k, v in legs.items()}, 'total', round(sum(legs.values())))
        if fill == 'mid': print('  ' + '\n  '.join(log))
    F = forward(); R['forward'] = F
    for sc, o in F.items():
        print(f"FWD {sc:8s} " + ' '.join(f"{k} {v/1000:7.1f}K" for k, v in o['avg_legs'].items()) + f" | avg {o['avg']/1000:6.1f}K middle {o['mid']/1000:6.1f}K bad {o['bad']/1000:7.1f}K worst {o['worst']/1000:7.1f}K | shares-only avg {o['sh_avg']/1000:5.1f}K bad {o['sh_bad']/1000:6.1f}K")
    json.dump(R, open(os.path.join(DATA, 'struct_test.json'), 'w'), indent=1)
