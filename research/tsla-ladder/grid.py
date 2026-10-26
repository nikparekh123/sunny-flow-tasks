"""Calls-bought grid on TSLA (Nik, 18 Oct 2026). Model research, not advice.
Shares and calls sold fixed as agreed: 1,000 shares; 10 calls on each of the next three
Mon/Wed/Fri expiries, every third sale at the money, the others 5% out. Only the calls bought
vary:
  structure  single 1m / 3m / 6m / 1y; mixes 1m+1y, 1m+3m, 3m+1y split 50/50, 25/75, 75/25
             by delta; core + adjuster (1y core fixed at 50% or 75% of the delta needed when
             it is bought, only 1m calls traded)
  strike     80 delta, at the money, 35 delta, 20 delta
  band       'could be' kept 0..300 (aim 150), -300..600 (aim 150), 350..650 (aim 500), -150..150 (aim 0)
  re-sizing  every expiry day, or once a week (the week's last expiry day)
Each leg rolls with a third of its life left. Fills at mid; the top 5 re-run at bid/ask.
Usage: python3 grid.py"""
import json, math, os, itertools
from ladder_b import Q, data, bs, iv_of, yrs, D, START, END, DATA
TENOR = {'1m': (30, 20, 10), '3m': (91, 60, 30), '6m': (182, 120, 60), '1y': (365, 240, 120)}
STRIKE = {'d80': 0.80, 'atm': None, 'd35': 0.35, 'd20': 0.20}
BANDS = {'0..300': (0, 300, 150), '-300..600': (-300, 600, 150), '350..650': (350, 650, 500), '-150..150': (-150, 150, 0)}
STRUCT = {'1m': [('1m', 1)], '3m': [('3m', 1)], '6m': [('6m', 1)], '1y': [('1y', 1)]}
for a, b in (('1m', '1y'), ('1m', '3m'), ('3m', '1y')):
    for w in (0.5, 0.25, 0.75): STRUCT[f'{a}+{b} {int(w * 100)}/{int((1 - w) * 100)}'] = [(a, w), (b, 1 - w)]
STRUCT['1y core 50% + 1m'] = 'core50'; STRUCT['1y core 75% + 1m'] = 'core75'
OTM = 0.05
RULE = None    # (5-day rise that triggers, 'step' | 'all10' | 'skip')
IVCHECK = False   # sell a weekly call only if that expiry's at-the-money implied vol > realised (20 sessions, earnings left out)
EARN = ['2025-10-22', '2026-01-28', '2026-04-22', '2026-07-22']    # TSLA reports, after the close (Nasdaq)
SKIPPED = []
def hv20_ex(C, day):
    ds = sorted(x for x in C if x <= day); skip = set()
    for e in EARN:
        if e in C: skip.add(e); nx = [x for x in ds if x > e]; skip.update(nx[:1])
    r = [math.log(C[ds[j]] / C[ds[j - 1]]) for j in range(len(ds) - 1, 0, -1) if ds[j] not in skip][:20]
    m = sum(r) / len(r); return math.sqrt(sum((x - m) ** 2 for x in r) / (len(r) - 1) * 252)
monthly = lambda x: 15 <= D(x).day <= 21 and D(x).weekday() == 4 or 14 <= D(x).day <= 20 and D(x).weekday() == 3

def pick(M, exps, day, S, tenor, strike):
    tgt, mn, _ = TENOR[tenor]
    cands = sorted([x for x in exps if (D(x) - D(day)).days >= mn], key=lambda x: (not (monthly(x) or tenor == '1m'), abs((D(x) - D(day)).days - tgt)))
    for e in cands[:12]:
        ch = M.chain(e, day)
        if not ch: continue
        if STRIKE[strike] is None: K = min(ch, key=lambda k: abs(k - S))
        else:
            dl = {}
            for k, (b, a) in ch.items():
                v = iv_of((b + a) / 2, S, k, yrs(day, e))
                if v: dl[k] = bs(S, k, yrs(day, e), v)[1]
            if not dl: continue
            K = min(dl, key=lambda k: abs(dl[k] - STRIKE[strike]))
        return dict(e=e, K=K, d=day, n=0, iv=iv_of(sum(ch[K]) / 2, S, K, yrs(day, e)) or 0.5, q0=ch[K], tenor=tenor)
    return None

def run(struct, strike, band, freq, fill='mid', t='TSLA', M=None, d=None):
    d = d or data(t); M = M or Q(t); C = d['closes']; exps = d['exps']
    sl = [s for s, _ in d['slots'] if s >= START[t] and s <= END]
    week_last = {max(x for x in sl if D(x).isocalendar()[:2] == D(s).isocalendar()[:2]) for s in sl}
    SELL = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    BUY = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    lo, hi, aim = BANDS[band]
    core = STRUCT[struct] if isinstance(STRUCT[struct], str) else None
    spec = [('1y', None), ('1m', None)] if core else STRUCT[struct]
    legs = [None] * len(spec)
    cash = 0.0; shorts = {}; n_sold = 0; eq = []; trades = 0; cb_out = 0
    def quote(L, day):
        q = M.hist(L['e'], L['K'], L['d']).get(day)
        return q or (L['q0'] if day == L['d'] else None)
    def value(L, day, S):
        q = quote(L, day); return (sum(q) / 2) if q else bs(S, L['K'], yrs(day, L['e']), L['iv'])[0]
    for i, day in enumerate(sl):
        S = C[day]
        if i == 0: cash -= 1000 * S; sells = sl[1:4]
        else:
            if day in shorts:
                s = shorts.pop(day); x = max(0, S - s['K']) * 1000; cash -= x + (5 if x > 0 else 0)
            sells = sl[i + 3:i + 4]
        for e in sells:
            q = {float(k): v for k, v in d['q'].get(f'{day}|{e}', {}).items() if v[0] > 0} or M.chain(e, day)
            if not q: n_sold += 1; continue
            ks = sorted(q); atm = n_sold % 3 == 0; n_sold += 1
            if IVCHECK:
                ka = min(ks, key=lambda k: abs(k - S)); iv_a = iv_of(sum(q[ka]) / 2, S, ka, yrs(day, e)) or 0
                hv = hv20_ex(C, day)
                if iv_a <= hv: SKIPPED.append((day, e, round(iv_a, 3), round(hv, 3))); continue
            cs_ = sorted(x for x in C if x <= day); prev = C[cs_[-6]] if len(cs_) > 5 else S
            if RULE and S / prev - 1 >= RULE[0]:                     # further out after a big up week
                if RULE[1] == 'skip': continue
                pct = (OTM if atm else 0.10) if RULE[1] == 'step' else 0.10
                K = next((k for k in ks if k >= S * (1 + pct)), ks[-1])
            else: K = min(ks, key=lambda k: abs(k - S)) if atm else next((k for k in ks if k >= S * (1 + OTM)), ks[-1])
            cash += SELL(*q[K]) * 1000 - 6.5
            shorts[e] = dict(K=K, d=day, iv=iv_of((q[K][0] + q[K][1]) / 2, S, K, yrs(day, e)) or 0.4)
        rolled = False
        for j, L in enumerate(legs):                                 # roll with a third of life left
            if L and (D(L['e']) - D(day)).days <= TENOR[L['tenor']][2]:
                q = quote(L, day); px = SELL(*q) if q else value(L, day, S)
                cash += px * 100 * L['n'] - 0.65 * L['n']; trades += L['n'] > 0; legs[j] = None; rolled = True
        for j, (ten, _) in enumerate(spec):
            if legs[j] is None: legs[j] = pick(M, exps, day, S, ten, strike)
        for L in legs:
            if L:
                q = quote(L, day)
                if q: L['iv'] = iv_of(sum(q) / 2, S, L['K'], yrs(day, L['e'])) or L['iv']
        def base(x):
            v = 1000.0
            for e, s in shorts.items():
                if e > day:
                    q = M.hist(e, s['K'], s['d']).get(day); iv = iv_of(sum(q) / 2, S, s['K'], yrs(day, e)) if q else None
                    v -= 1000 * bs(x, s['K'], yrs(day, e), iv or s['iv'])[1]
            return v
        b_dn, b_up = base(S * 0.95), base(S * 1.05)
        dl = lambda L, x: 100 * bs(x, L['K'], yrs(day, L['e']), L['iv'])[1] if L else 0
        cb = lambda ns: min(b_dn + sum(n * dl(L, S * 0.95) for n, L in zip(ns, legs)), b_up + sum(n * dl(L, S * 1.05) for n, L in zip(ns, legs)))
        cur = [L['n'] if L else 0 for L in legs]
        def best(fixed, L, aim):                                       # one adjustable leg after fixed ones
            a_dn, a_up = dl(L, S * 0.95), dl(L, S * 1.05)
            f = lambda n: cb(fixed + [n])
            k_dn = b_dn + sum(m * dl(Lx, S * 0.95) for m, Lx in zip(fixed, legs)); k_up = b_up + sum(m * dl(Lx, S * 1.05) for m, Lx in zip(fixed, legs))
            n0 = max(0, round(max((aim - k_dn) / a_dn if a_dn > 0 else 0, (aim - k_up) / a_up if a_up > 0 else 0)))
            return min((n for n in (n0 - 1, n0, n0 + 1) if n >= 0), key=lambda n: abs(f(n) - aim))
        out_band = not (lo <= cb(cur) <= hi); cb_out += out_band
        due = i == 0 or rolled or (out_band and (freq == 'daily' or day in week_last))
        if due and all(quote(L, day) for L in legs if L):
            if core:
                c, a = legs
                if c and (c['n'] == 0 or rolled and c['d'] == day):           # size the core when it is bought
                    need = max(0.0, aim - cb([0, 0]))
                    c_share = 0.5 if core == 'core50' else 0.75
                    c_new = math.ceil(c_share * need / max(1e-6, min(dl(c, S * 1.05), dl(c, S)))) if need > 0 else 0
                else: c_new = c['n'] if c else 0
                a_new = best([c_new], a, aim) if a else 0
                new = [c_new, a_new]
            else:
                # Exact size: with n_j = X * w_j / delta_j(price), 'could be' is the lower of two
                # straight lines in X; solve for the aim, round, then try one contract either way.
                ws = [w for _, w in spec]
                A = lambda x: sum(w * dl(L, x) / max(1e-9, dl(L, S)) for w, L in zip(ws, legs) if L)
                a_dn, a_up = A(S * 0.95), A(S * 1.05)
                X = max(0.0, max((aim - b_dn) / a_dn if a_dn > 0 else 0, (aim - b_up) / a_up if a_up > 0 else 0))
                base_n = [max(0, round(X * w / max(1e-9, dl(L, S)))) if L else 0 for w, L in zip(ws, legs)]
                opts = itertools.product(*[(n - 1, n, n + 1) if L else (0,) for n, L in zip(base_n, legs)])
                new = list(min((o for o in opts if min(o) >= 0), key=lambda o: abs(cb(list(o)) - aim)))
            for L, n in zip(legs, new):
                if L and n != L['n']:
                    q = quote(L, day); dn = n - L['n']; px = BUY(*q) if dn > 0 else SELL(*q)
                    cash -= dn * px * 100 + 0.65 * abs(dn); L['n'] = n; trades += 1
        lv = sum(L['n'] * 100 * value(L, day, S) for L in legs if L)
        sv = 0.0
        for e, s in shorts.items():
            if e > day:
                q = M.hist(e, s['K'], s['d']).get(day)
                sv += 1000 * ((sum(q) / 2) if q else bs(S, s['K'], yrs(day, e), s['iv'])[0])
        eq.append(cash + 1000 * S + lv - sv)
    peak, mdd = -1e18, 0.0
    for v in eq: peak = max(peak, v); mdd = min(mdd, v - peak)
    S0 = C[sl[0]]
    return dict(struct=struct, strike=strike, band=band, freq=freq, fill=fill, total=eq[-1], trades=trades,
                mdd_pct=mdd / (1000 * S0) * 100, out_band_pct=cb_out / len(sl) * 100, shares=(C[sl[-1]] - S0) * 1000)

if __name__ == '__main__':
    d = data('TSLA'); M = Q('TSLA'); res = []
    combos = list(itertools.product(STRUCT, STRIKE, BANDS, ('daily', 'weekly')))
    for k, (st, sk, bd, fq) in enumerate(combos):
        r = run(st, sk, bd, fq, 'mid', 'TSLA', M, d); res.append(r)
        if k % 40 == 0: print(k, len(combos), st, sk, bd, fq, round(r['total']), flush=True); M.save()
    M.save()
    res.sort(key=lambda r: -r['total'])
    top = [run(r['struct'], r['strike'], r['band'], r['freq'], 'worse', 'TSLA', M, d) for r in res[:5]]
    json.dump(dict(mid=res, top_bidask=top), open(os.path.join(DATA, 'grid_TSLA.json'), 'w'), indent=1)
    print('shares alone', round(res[0]['shares']))
    for r in res[:15]: print(f"{r['struct']:18s} {r['strike']:4s} {r['band']:10s} {r['freq']:6s} total {r['total']:>10,.0f} trades {r['trades']:4d} maxDD {r['mdd_pct']:6.1f}%")
    print('bid/ask of top 5:', [round(x['total']) for x in top])
