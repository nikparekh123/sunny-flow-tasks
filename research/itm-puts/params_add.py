"""Add new names to data/params.json the way UBER/DELL/SNDK were added on 15 Oct (that was an inline
script; this is the same code kept as a file). Every existing entry is left untouched.
Spot = put-call parity on the 23 Oct weekly (median of the 3 strikes nearest the close); LEAP = Jan 2028
call nearest 0.80 delta, sized to $150K; weekly ATM IV = mean of call and put IV at the nearest strike;
term IVs = ~8% ITM puts; iv_leap = Jan 2028 ATM put; earn_move = historical (median biggest 1-day move
within 3 days of each of the last 8 reports). Where a report sits inside the 23 Oct or 30 Oct weekly, the
implied move and the ex-earnings weekly IV are also backed out of those two expiries (TSLA/PYPL method).
Chains are 15 Oct EOD quotes (Theta history/eod), so they line up with TODAY = 15 Oct in common.py.
Usage: python3 params_add.py VZ TMUS T"""
import json, math, sys, datetime, numpy as np
from common import iv, delta, D, TODAY
L = {**json.load(open('data/live_chains.json')), **json.load(open('data/live_chains2.json'))}
def ch(t, e, cp): return {float(k): v for k, v in L[t][e].get(cp, {}).items()}
def T(e): return (D(e) - TODAY).days / 365
# report dates: company announcements for the next one (VZ 26 Oct bmo, TMUS 28 Oct after the close -> moves 29 Oct,
# T 21 Oct bmo); later ones from earnings_events. The DB's 20/28 Oct VZ and 22 Oct TMUS rows are wrong.
EARN = {'VZ': ['2026-10-26', '2027-01-29', '2027-04-26', '2027-07-23'],
        'TMUS': ['2026-10-29', '2027-02-10', '2027-04-28', '2027-07-22'],
        'T': ['2026-10-21', '2027-01-27', '2027-04-21', '2027-07-21']}
LAST = {'VZ': '2026-07-24', 'TMUS': '2026-07-23', 'T': '2026-07-22'}
# dividend yield = latest quarterly x 4 / 15 Oct close: VZ 0.708 x 4 / 44.40, TMUS 1.02 x 4 / 157.03, T 0.278 x 4 / 23.50
Q = {'VZ': 0.064, 'TMUS': 0.026, 'T': 0.047}
def closes(t):
    c = json.load(open(f'data/{t.lower()}_closes.json'))['bars']; ks = sorted(c); return ks, np.array([c[k] for k in ks])
def rv(t, w):
    ks, px = closes(t); r = np.diff(np.log(px)); return float(r[-w:].std() * math.sqrt(252))
def step_near(c, S):
    ks = sorted(k for k in c if 0.85 * S < k < 1.15 * S); g = np.diff(ks); return float(np.median(g)) if len(g) else 1.0
def atm(t, e, S, q):
    C = ch(t, e, 'C'); Pp = ch(t, e, 'P'); k = min((k for k in C if k in Pp), key=lambda k: abs(k - S))
    return float(np.mean([iv(sum(C[k]) / 2, S, k, T(e), q, 'C') or 0, iv(sum(Pp[k]) / 2, S, k, T(e), q, 'P') or 0]))
P = json.load(open('data/params.json'))
for t in sys.argv[1:]:
    ks, px = closes(t); s0 = px[-1]; q = Q[t]
    C = ch(t, '2026-10-23', 'C'); Pp = ch(t, '2026-10-23', 'P')
    near = sorted((k for k in C if k in Pp), key=lambda k: abs(k - s0))[:3]
    S = round(float(np.median([sum(C[k]) / 2 - sum(Pp[k]) / 2 + k * math.exp(-0.04 * T('2026-10-23')) for k in near])), 3)
    v = atm(t, '2026-10-23', S, q); v30 = atm(t, '2026-10-30', S, q)
    T1, T2 = T('2026-10-23'), T('2026-10-30')
    e1 = any(TODAY < D(e) <= D('2026-10-23') for e in EARN[t]); e2 = any(TODAY < D(e) <= D('2026-10-30') for e in EARN[t])
    if e1:      # report inside both weeklies: solve sigma_x^2*T + m^2 for the two expiries
        x2 = (v30 ** 2 * T2 - v ** 2 * T1) / (T2 - T1); em_i = math.sqrt(max(0.0, v * v * T1 - x2 * T1)); vx = math.sqrt(max(0.01, x2))
    elif e2:    # report inside the 30 Oct weekly only: the 23 Oct weekly is the ex-earnings vol
        em_i = math.sqrt(max(0.0, (v30 ** 2 - v ** 2) * T2)); vx = v
    else: em_i, vx = None, v
    term = {}
    for ten, e in ((3, '2027-01-15'), (5, '2027-03-19'), (8, '2027-06-17')):
        c = ch(t, e, 'P'); kk = min(c, key=lambda x: abs(x - S * 1.08)); term[ten] = round(iv(sum(c[kk]) / 2, S, kk, T(e), q, 'P') or v, 3)
    c28 = ch(t, '2028-01-21', 'C'); p28 = ch(t, '2028-01-21', 'P')
    ka = min(p28, key=lambda x: abs(x - S)); ivl = iv(sum(p28[ka]) / 2, S, ka, T('2028-01-21'), q, 'P')
    cand = [(kk, iv(sum(vv) / 2, S, kk, T('2028-01-21'), q, 'C')) for kk, vv in c28.items() if 0.4 * S < kk < S]
    KL = min([x for x in cand if x[1]], key=lambda x: abs(delta(S, x[0], T('2028-01-21'), x[1], q, 'C') - 0.80))[0]
    r = np.diff(np.log(px)); idx = {k_: i for i, k_ in enumerate(ks[1:])}; d0 = D(LAST[t]); mv = []
    for qq in range(8):
        d = d0 - datetime.timedelta(days=round(91.3 * qq)); win = [idx[x] for x in ks[1:] if abs((D(x) - d).days) <= 3]
        if len(win) >= 3: mv.append(max(abs(r[i]) for i in win))
    r20, r60 = rv(t, 20), rv(t, 60)
    P[t] = dict(spot=S, q=q, step=step_near(C, S), long_step=step_near(ch(t, '2027-03-19', 'P'), S), leap=[round(150000 / (100 * S), 3), KL],
                leap_mid=sum(c28[KL]) / 2, iv_leap=round(ivl, 3), earn=EARN[t], earn_move=round(float(np.median(mv)), 3), earn_n=len(mv),
                earn_move_impl=em_i and round(em_i, 3), wk='2026-10-23', iv_wk=round(v, 3), iv_wk30=round(v30, 3), iv_wk_ex=round(vx, 3),
                rv20=round(r20, 3), rv60=round(r60, 3), rho0=round(min(1.4, max(0.9, vx / ((r20 + r60) / 2))), 3),
                rho_raw=round(vx / ((r20 + r60) / 2), 3), iv_term=term, held=False)
    print(t, P[t], flush=True)
json.dump(P, open('data/params.json', 'w'), indent=1)
