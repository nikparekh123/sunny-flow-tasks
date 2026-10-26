"""Forward test, next 3 months (Nik, 18 Oct 2026). Model research, not advice.
Agreed setup, all four names, starting at the real 16 Oct 2026 close:
  1,000 shares; 10 calls sold on each of the next three expiries (TSLA Mon/Wed/Fri, ETFs every
  trading day), every third sale at the money, the others 5% out (TSLA) or 2% out (ETFs);
  calls bought 1 month at the money, re-sized weekly to keep 'could be' (the lower net delta after
  an instant 5% move) between -150 and +150, aiming at 0, rolled with 10 days left; 15 at-the-money
  puts to 15 Jan 2027, bought once and held, NOT counted in 'could be'.
Day 1 trades at real Theta quotes. After that: 500 paths per version built from each name's own
daily moves since late 2024 (drift removed), scaled 0.5x (Safe), 1x (Moderate), 1.75x (Wild);
options priced with Black-Scholes at Friday's implied volatility moved 0.8x / 1x / 1.5x over the
first two weeks. Every trade pays half of Friday's bid/ask gap (as a share of price), $0.65 a
contract; assigned shares bought back at the close ($5). Runs to 15 Jan 2027 (the put expiry).
FIXES (Nik OK'd 18 Oct 2026): (1) on a re-size day, a bought call whose delta has fallen below
0.20 is sold and replaced by a new 1-month at-the-money call before sizing; (2) SPY, QQQ, IWM
size 'could be' on a typical week's move (1-month implied volatility x sqrt(5/252), about 2-3%)
instead of 5%. TSLA keeps 5%.
Usage: python3 forward.py"""
import json, math, os, random, statistics as stt, datetime as dt
from sim import theta, bs, iv_of, yrs, D, DATA
NAMES = {'TSLA': 0.05, 'SPY': 0.02, 'QQQ': 0.02, 'IWM': 0.02}
DAY0, END = '2026-10-16', '2027-01-15'
HOL = {'2026-11-26', '2026-12-25', '2027-01-01'}
SCEN = {'Safe': (0.5, 0.8), 'Moderate': (1.0, 1.0), 'Wild': (1.75, 1.5)}
NPATH = 500
days = []; x = D(DAY0) + dt.timedelta(days=1)
while x <= D(END):
    if x.weekday() < 5 and x.isoformat() not in HOL: days.append(x.isoformat())
    x += dt.timedelta(days=1)
def pput(S, K, T, v): return bs(S, K, T, v)[0] - S + K * math.exp(-0.04 * T)
def chain(t, e, right):
    q = {}
    for c in theta(f"/v3/option/history/eod?symbol={t}&expiration={e.replace('-', '')}&right={right}&start_date=20261016&end_date=20261016"):
        for x_ in c.get('data', []):
            if (x_.get('bid') or 0) > 0 and (x_.get('ask') or 0) > 0: q[float(c['contract']['strike'])] = (x_['bid'], x_['ask'])
    return q

def setup(t):
    d = json.load(open(os.path.join(DATA, f'{t}.json'))); C = d['closes']; S0 = C[DAY0]
    listed = sorted(e for e in d['exps'] if e > DAY0)
    if t == 'TSLA':   # Mon/Wed/Fri: the listed ones, then every Mon/Wed/Fri trading day
        slots = [e for e in listed if e <= '2026-10-30' and D(e).weekday() in (0, 2, 4)] + [x for x in days if x > '2026-10-30' and D(x).weekday() in (0, 2, 4)]
    else: slots = list(days)
    slots = [s for s in slots if s <= END]
    first = [s for s in slots][:3]
    sold = []
    for j, e in enumerate(first):
        q = chain(t, e, 'call'); ks = sorted(q)
        K = min(ks, key=lambda k: abs(k - S0)) if j == 0 else next(k for k in ks if k >= S0 * (1 + NAMES[t]))
        b, a = q[K]; T = yrs(DAY0, e); sold.append(dict(e=e, K=K, p=(b + a) / 2, iv=iv_of((b + a) / 2, S0, K, T) or 0.3, hs=(a - b) / 2 / ((a + b) / 2)))
    qc = chain(t, '2026-11-20', 'call'); Kc = min(qc, key=lambda k: abs(k - S0)); bc, ac = qc[Kc]
    ivc = iv_of((bc + ac) / 2, S0, Kc, yrs(DAY0, '2026-11-20'))
    qp = chain(t, '2027-01-15', 'put'); Kp = min(qp, key=lambda k: abs(k - S0)); bp, ap = qp[Kp]; Tp = yrs(DAY0, '2027-01-15')
    lo, hi = 0.01, 5
    for _ in range(60):
        m = (lo + hi) / 2; lo, hi = (m, hi) if pput(S0, Kp, Tp, m) < (bp + ap) / 2 else (lo, m)
    ivp = (lo + hi) / 2
    cs = sorted(C); r = [math.log(C[b_] / C[a_]) for a_, b_ in zip(cs, cs[1:]) if '2024-10-01' <= b_ <= DAY0]
    mu = sum(r) / len(r); r = [x_ - mu for x_ in r]
    hs_short = sum(s['hs'] for s in sold) / 3
    move = 0.05 if t == 'TSLA' else ivc * math.sqrt(5 / 252)
    return dict(t=t, S0=S0, move=move, slots=slots, sold=sold, call=dict(e='2026-11-20', K=Kc, p=(bc + ac) / 2, iv=ivc, hs=(ac - bc) / 2 / ((ac + bc) / 2)),
                put=dict(e='2027-01-15', K=Kp, p=(bp + ap) / 2, iv=ivp, hs=(ap - bp) / 2 / ((ap + bp) / 2)), rets=r, hs_short=hs_short,
                iv_short=sum(s['iv'] for s in sold) / 3)

def path_run(P, idx, volk, ivk):
    t = P['t']; S = P['S0']; otm = NAMES[t]; slots = P['slots']; sset = set(slots)
    legs = {'shares': 0.0, 'calls sold': 0.0, 'calls bought': 0.0, 'puts bought': 0.0}
    shorts = {}; n_sold = 0
    for j, s in enumerate(P['sold']):                    # day 1: real quotes, sold at mid less half the gap
        legs['calls sold'] += 1000 * s['p'] * (1 - s['hs']) - 6.5; shorts[s['e']] = dict(K=s['K'], iv=s['iv']); n_sold += 1
    pu = P['put']; legs['puts bought'] -= 15 * 100 * pu['p'] * (1 + pu['hs']) + 15 * 0.65
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
        S = S_prev * math.exp(P['rets'][idx[i]] * volk); S_prev = S
        if day in shorts:
            s = shorts.pop(day); x_ = max(0, S - s['K']) * 1000; legs['calls sold'] -= x_ + (5 if x_ > 0 else 0)
        if day in sset:
            k = slots.index(day)
            for e in slots[k + 3:k + 4]:
                T = yrs(day, e); iv = ivf(i, P['iv_short'])
                K = S if n_sold % 3 == 0 else S * (1 + otm); n_sold += 1
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
    legs['puts bought'] += 15 * 100 * max(0, pu['K'] - S)
    legs['shares'] = 1000 * (S - P['S0'])
    return legs, S / P['S0'] - 1

if __name__ == '__main__':
    out = {}
    rng = random.Random(7)
    for t in NAMES:
        P = setup(t); out[t] = {'setup': {k: P[k] for k in ('S0', 'sold', 'call', 'put')}}
        idxs = [[rng.randrange(len(P['rets'])) for _ in days] for _ in range(NPATH)]   # same draws in every version
        for sc, (vk, ik) in SCEN.items():
            rs = [path_run(P, ix, vk, ik) for ix in idxs]
            tot = sorted(sum(l.values()) for l, _ in rs)
            mean = {k: stt.mean(l[k] for l, _ in rs) for k in rs[0][0]}
            out[t][sc] = dict(mean=mean, total_mean=sum(mean.values()), median=stt.median(tot), p10=tot[len(tot) // 10],
                              p90=tot[len(tot) * 9 // 10], move_med=stt.median(m for _, m in rs),
                              move_p10=sorted(m for _, m in rs)[len(rs) // 10], move_p90=sorted(m for _, m in rs)[len(rs) * 9 // 10],
                              shares_only_p10=sorted(l['shares'] for l, _ in rs)[len(rs) // 10])
            o = out[t][sc]
            print(f"{t} {sc:8s} " + ' '.join(f"{k} {v/1000:7.1f}K" for k, v in mean.items()) + f" | total avg {o['total_mean']/1000:7.1f}K median {o['median']/1000:7.1f}K bad10% {o['p10']/1000:7.1f}K good10% {o['p90']/1000:7.1f}K | price move 10/50/90% {o['move_p10']*100:5.1f}/{o['move_med']*100:5.1f}/{o['move_p90']*100:5.1f}% | shares-only bad10% {o['shares_only_p10']/1000:7.1f}K", flush=True)
    json.dump(out, open(os.path.join(DATA, 'forward.json'), 'w'), indent=1)
