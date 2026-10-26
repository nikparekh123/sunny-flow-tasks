"""Whole-position forward test for NKE (Nik, 15 Oct 2026, second meeting).

Block: 60 Jan 2028 30C LEAPs. Weekly calls on them (part at the money, the rest
z SD out). Long puts ~8% in the money, March 2027, rolled. Weekly puts sold
(about half the long count), strike by rule, never above the long strike so they
stay covered. Optional extra upside: quarterly ~15% OTM calls or one 1-year $50 call
buy. Same path engine as forward.py (own 3y daily moves, earnings jumps, scenario
waypoints) but vectorised over paths so net delta can be tracked every close.
Fixes forward.py's first-week double sale (today's sale and Fri 16 Oct's both ran to 23 Oct)."""
import sys, os, numpy as np, math
from common import *
import forward as F
from forward import EARN_MOVE, LONG_STEP, RHO0, IV_TERM, IV_LEAP, CAL, NDAYS, FRI, at, LONG_EXP, make_paths, rv_series

import json as _j
PRM = _j.load(open('data/params.json'))
# new names: earnings move implied from the weekly chain where a report sits inside it (TSLA, PYPL), else typical size;
# richness = ex-earnings weekly IV / mean(rv20, rv60); LEAP IV = Jan 2028 ATM put. Held names keep forward.py's inputs.
NEW = {'ADBE': (0.07, 1.07, 0.451), 'INTU': (0.06, 1.15, 0.506), 'SPCX': (0.10, 0.90, 0.52),
       'TSLA': (0.078, 0.95, 0.447), 'PYPL': (0.088, 1.04, 0.293), 'APP': (0.12, 0.99, 0.646),
       'UBER': (0.06, 1.12, 0.389), 'DELL': (0.08, 1.01, 0.638), 'SNDK': (0.12, 0.90, 0.653),
       # 16 Oct, priced on 15 Oct EOD quotes. Moves implied from the 23/30 Oct weeklies (VZ 26 Oct, TMUS 28 Oct pm, T 21 Oct).
       # Richness is the 0.90 floor for all three: raw 0.53-0.69, because the 9 Oct sector drop (-11 to -14%) inflates rv20/rv60.
       'VZ': (0.035, 0.90, 0.239), 'TMUS': (0.05, 0.90, 0.349), 'T': (0.045, 0.90, 0.271)}
for t, (em, rho, ivl) in NEW.items():
    p = PRM[t]; SPOT[t] = p['spot']; Q[t] = p['q']; STEP[t] = p['step']; LEAP[t] = tuple(p['leap']); EARN[t] = p['earn']
    LONG_STEP[t] = p['long_step']; IV_TERM[t] = {int(k): v for k, v in p['iv_term'].items()}; EARN_MOVE[t] = em; RHO0[t] = rho; IV_LEAP[t] = ivl
_hr = F.hist_returns
def _hist(t):
    if t != 'SPCX': return _hr(t)
    # SPCX listed 12 Jun 2026 (86 daily moves): its own moves plus TSLA's 3 years rescaled to SPCX's volatility
    own, pre = _hr('SPCX'); ts, _ = _hr('TSLA')
    return np.concatenate([own, ts * own.std() / ts.std()]), pre
F.hist_returns = _hist
_LIVE = None
def live_all():
    global _LIVE
    if _LIVE is None:
        raw = {**_j.load(open('data/live_chains.json')), **_j.load(open('data/live_chains2.json'))}
        _LIVE = {t: {e: {cp: {float(k): v for k, v in side.items()} for cp, side in q.items()} for e, q in ex.items()} for t, ex in raw.items()}
    return _LIVE
F.SCEN['jump 30% in 1m'] = [(21, 1.30), (NDAYS, 1.30)]
F.SCEN['no view'] = []
SCENS = ['flat', 'up 15%', 'rip 25% in 3m', 'jump 30% in 1m', 'bull +40%', 'down 15%', 'crash 30% in 2m', 'V: -20% then back', 'no view']

def _erf(x):
    s = np.sign(x); x = np.abs(x); t = 1 / (1 + 0.3275911 * x)
    y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * np.exp(-x * x)
    return s * y
def N(x): return 0.5 * (1 + _erf(np.asarray(x, float) / math.sqrt(2)))
def bsv(S, K, T, v, q, cp):
    S, K, T, v = (np.asarray(a, float) for a in (S, K, T, v)); Tc = np.maximum(T, 1e-6)
    sq = v * np.sqrt(Tc); d1 = (np.log(S / K) + (R - q + v * v / 2) * Tc) / sq; d2 = d1 - sq
    if cp == 'C': val = S * np.exp(-q * Tc) * N(d1) - K * np.exp(-R * Tc) * N(d2); intr = np.maximum(0, S - K)
    else: val = K * np.exp(-R * Tc) * N(-d2) - S * np.exp(-q * Tc) * N(-d1); intr = np.maximum(0, K - S)
    return np.where(T <= 1e-6, intr, val)
def dlv(S, K, T, v, q, cp):
    S, K, T, v = (np.asarray(a, float) for a in (S, K, T, v)); Tc = np.maximum(T, 1e-6)
    d1 = (np.log(S / K) + (R - q + v * v / 2) * Tc) / (v * np.sqrt(Tc))
    d = np.exp(-q * Tc) * (N(d1) if cp == 'C' else N(d1) - 1)
    hard = ((S > K) * 1.0) if cp == 'C' else -((S < K) * 1.0)
    return np.where(T <= 1e-6, hard, d)
def yrs(i, e): return max(0.0, (D(e) - CAL[i]).days / 365) if isinstance(e, str) else max(0.0, (CAL[e] - CAL[i]).days / 365)

_cache = {}
def paths(t, scen, n):
    k = (t, scen, n)
    if k not in _cache:
        P, R_, pre = make_paths(t, scen, n)
        if scen == 'no view':
            # unpinned paths: give the price a fair drift (r - q, as options are priced) instead of the
            # zero log drift the bootstrap has, which lifts the average price by half the variance (+20% a year for SPCX)
            lr, _ = F.hist_returns(t); kk = np.arange(NDAYS + 1)
            ne = np.array([sum(1 for e in EARN[t] if TODAY < D(e) <= CAL[i]) for i in range(NDAYS + 1)])
            P = P * np.exp((R - Q[t]) * kk / 252 - 0.5 * lr.var() * kk - 0.5 * EARN_MOVE[t] ** 2 * ne)[None, :]
        # weekly options are priced off recent moves WITHOUT the earnings days: the report's own
        # jump is added separately when a report falls inside the week, so leaving it in the
        # 20-day window priced the next four weeks as if the jump were still to come (fixed 15 Oct)
        Rx = R_.copy()
        for e in (at(x) for x in EARN[t] if TODAY < D(x) <= CAL[-1]):
            if 1 <= e <= NDAYS: Rx[:, e - 1] = 0.0
        _cache[k] = (P, rv_series(Rx, pre, 20), rv_series(Rx, pre, 60))
    return _cache[k]

QTR = ['2027-01-15', '2027-04-16', '2027-07-16', '2027-10-15']

def run(t, scen, plan, n=300):
    """plan keys: long_n, itm, tenor, short_n, put_rule, call_n, call_atm, call_z, qtr_n, year_n.
    put_rule: ('atm',) | ('otm', x) | ('sd', z) | ('split', atm_share, z)."""
    P, rv20, rv60 = paths(t, scen, n)
    S0, q, step = SPOT[t], Q[t], STEP[t]; nL, KL = LEAP[t]; live = live_all()[t]
    eidx = [at(e) for e in EARN[t] if TODAY < D(e) <= CAL[-1]]
    Tl = np.array([yrs(i, '2028-01-21') for i in range(NDAYS + 1)])
    pnl = {k: np.zeros(n) for k in ('leap', 'calls', 'longput', 'shortput', 'extra')}
    dnet = nL * 100 * dlv(P, KL, Tl[None, :], IV_LEAP[t], q, 'C')          # (n, days) share delta
    pnl['leap'] = nL * 100 * (bsv(P[:, -1], KL, Tl[-1], IV_LEAP[t], q, 'C') - bs(S0, KL, Tl[0], IV_LEAP[t], q, 'C'))
    day0 = [(nL, KL, Tl[0], IV_LEAP[t], 'C')]                                # legs held at today's close, for the stress test
    # long puts: (buy, end, K per path)
    holds = []
    if plan['long_n']:
        b = 0
        for e in LONG_EXP[plan['tenor']]:
            ei = at(e) if D(e) <= CAL[-1] else None
            S = P[:, b]
            if b == 0:
                ch = live[e]['P']; K0 = min(ch, key=lambda k: abs(k - S0 * (1 + plan['itm']))); bb, aa = ch[K0]
                K = np.full(n, K0); px = np.full(n, (bb + aa) / 2 + (aa - bb) / 4)
                v = np.full(n, iv((bb + aa) / 2, S0, K0, yrs(0, e), q, 'P'))
                day0.append((plan['long_n'], K0, yrs(0, e), v[0], 'P'))
            else:
                K = np.round(S * (1 + plan['itm']) / LONG_STEP[t]) * LONG_STEP[t]
                v = IV_TERM[t][plan['tenor']] * np.clip((rv60[:, b] / rv60[:, 0]) ** 0.5, 0.7, 1.6)
                px = bsv(S, K, yrs(b, e), v, q, 'P') * 1.01
            end = ei if ei is not None else NDAYS
            K = K.copy(); cash = -px * 100 - 0.65
            Kd = np.empty((n, end - b))
            fri = set(FRI)
            for d in range(b, end):
                Td = yrs(d, e)
                if plan.get('reset') and d > b and d in fri and Td > 42 / 365:
                    # take profit after a fall: put deep in the money -> sell it, buy a fresh one ~itm above today's price, same expiry
                    hit = dlv(P[:, d], K, Td, v, q, 'P') < -plan['reset']
                    if hit.any():
                        Kn = np.round(P[:, d] * (1 + plan['itm']) / LONG_STEP[t]) * LONG_STEP[t]
                        sell = bsv(P[:, d], K, Td, v, q, 'P') * 0.99; buy = bsv(P[:, d], Kn, Td, v, q, 'P') * 1.01
                        cash = cash + np.where(hit, 100 * (sell - buy) - 1.30, 0.0)
                        K = np.where(hit, Kn, K)
                Kd[:, d - b] = K
                dnet[:, d] += plan['long_n'] * 100 * dlv(P[:, d], K, Td, v, q, 'P')
            back = np.maximum(0, K - P[:, ei]) if ei is not None else bsv(P[:, -1], K, yrs(NDAYS, e), v, q, 'P') * 0.99
            pnl['longput'] += plan['long_n'] * (100 * back + cash)
            holds.append((b, end, Kd))
            if ei is None or ei >= NDAYS: break
            b = ei
    def longK(i):
        for b_, e_, K_ in holds:
            if b_ <= i < e_: return K_[:, i - b_]
        return None
    # extra upside: quarterly ~15% OTM calls, rolled; or one 1-year $50 call buy (Dec 2027)
    if plan.get('qtr_n'):
        b = 0
        for e in QTR:
            ei = at(e)
            if b == 0:
                ch = live['2027-01-15']['C']; K0 = min(ch, key=lambda k: abs(k - S0 * 1.15)); bb, aa = ch[K0]
                K = np.full(n, K0); px = (bb + aa) / 2 + (aa - bb) / 4; iq = iv((bb + aa) / 2, S0, K0, yrs(0, e), q, 'C'); v = np.full(n, iq)
                day0.append((plan['qtr_n'], K0, yrs(0, e), iq, 'C'))
            else:
                K = np.round(P[:, b] * 1.15 / LONG_STEP[t]) * LONG_STEP[t]
                v = iq * np.clip((rv60[:, b] / rv60[:, 0]) ** 0.5, 0.7, 1.6)
                px = bsv(P[:, b], K, yrs(b, e), v, q, 'C') * 1.03
            pnl['extra'] += plan['qtr_n'] * (100 * (np.maximum(0, P[:, ei] - K) - px) - 0.65)
            for d in range(b, ei): dnet[:, d] += plan['qtr_n'] * 100 * dlv(P[:, d], K, yrs(d, e), v, q, 'C')
            b = ei
    if plan.get('year_n'):
        ye = '2027-12-17' if '2027-12-17' in live else '2028-01-21'
        ch = live[ye]['C']; Ky = min(ch, key=lambda k: abs(k - S0 * 1.30)); bb, aa = ch[Ky]; px = (bb + aa) / 2 + (aa - bb) / 4
        v = iv((bb + aa) / 2, S0, Ky, yrs(0, ye), q, 'C')
        pnl['extra'] += plan['year_n'] * (100 * (bsv(P[:, -1], Ky, yrs(NDAYS, ye), v, q, 'C') - px) - 0.65)
        dnet += plan['year_n'] * 100 * dlv(P, Ky, np.array([yrs(i, ye) for i in range(NDAYS + 1)])[None, :], v, q, 'C')
        day0.append((plan['year_n'], Ky, yrs(0, ye), v, 'C'))
    # weekly legs: sell today for Fri 23 Oct, then every Friday
    first_ex = next(f for f in FRI if f > 1)
    sells = [0] + [f for f in FRI if first_ex <= f < NDAYS]
    for i in sells:
        ex = next((f for f in FRI if f > max(i, 1)), None)
        if ex is None or ex > NDAYS: break
        S = P[:, i]; T = yrs(i, ex); earn = any(i < e <= ex for e in eidx)
        # RHO_MODE=hold keeps today's richness all year; the default fades it to 1.05 over ~2 months
        rho = RHO0[t] if os.environ.get('RHO_MODE') == 'hold' else 1.05 + (RHO0[t] - 1.05) * math.exp(-i / 40)
        v = np.maximum(0.12, rv20[:, i]) * rho
        if earn: v = np.sqrt(v * v + EARN_MOVE[t] ** 2 / T)
        sd = S * v * math.sqrt(T)
        legs = []                                                          # (signed n, K array, cp)
        put_legs = []
        if plan['short_n']:
            KLp = longK(i)
            if KLp is not None:
                r = plan['put_rule']
                atmK = np.round(S / step) * step
                def sdK(z): return np.floor(S * (1 - z * v * math.sqrt(T)) / step) * step
                if r[0] == 'atm': parts = [(1.0, atmK)]
                elif r[0] == 'otm': parts = [(1.0, np.floor(S * (1 - r[1]) / step) * step)]
                elif r[0] == 'sd': parts = [(1.0, sdK(r[1]))]
                else: parts = [(r[1], atmK), (1 - r[1], sdK(r[2]))]
                put_legs = [(-plan['short_n'] * sh, np.minimum(K, KLp), 'P') for sh, K in parts]
        if plan['call_n']:
            m = S / P[:, max(0, i - 21)] - 1
            atm = min(plan['call_atm'], 0.2) if earn else plan['call_atm']
            z = np.where(m >= 0.15, max(1.0, plan['call_z']), plan['call_z'])
            Ka = np.ceil(S / step - 1e-9) * step
            Ko = np.maximum(Ka + step, np.round((S + z * sd) / step) * step)
            nc = np.full(n, float(plan['call_n']))
            if plan.get('delta_floor') is not None:
                # sell only as many calls as keep the block at least delta_floor x LEAP shares long at the sale
                have = dnet[:, i] + sum(nn * 100 * dlv(S, K, T, v, q, cp) for nn, K, cp in put_legs)
                per = 100 * (atm * dlv(S, Ka, T, v, q, 'C') + (1 - atm) * dlv(S, Ko, T, v, q, 'C'))
                nc = np.clip(np.floor((have - plan['delta_floor'] * nL * 100) / np.maximum(per, 1e-6)), 0, plan['call_n'])
            legs += [(-nc * atm, Ka, 'C'), (-nc * (1 - atm), Ko, 'C')]
        legs = put_legs + legs
        for nn, K, cp in legs:
            prem = bsv(S, K, T, v, q, cp) * 0.98 - 0.0065
            pay = np.maximum(0, (P[:, ex] - K) if cp == 'C' else (K - P[:, ex]))
            pnl['calls' if cp == 'C' else 'shortput'] += -nn * 100 * (prem - pay)
            for d in range(i, ex):
                dnet[:, d] += nn * 100 * dlv(P[:, d], K, yrs(d, ex), v, q, cp)
            if i == 0: day0.append((float(np.median(nn)) if np.ndim(nn) else nn, float(K[0]), T, float(v[0]), cp))
    pnl['total'] = sum(pnl[k] for k in ('leap', 'calls', 'longput', 'shortput', 'extra'))
    pnl['wkstart'] = dnet[:, [i for i in sells if i < NDAYS]]
    return pnl, dnet[:, :NDAYS], day0

def shock(day0, t, move, dv):
    S0, q = SPOT[t], Q[t]; S1 = S0 * (1 + move); out = 0.0
    for nn, K, T, v, cp in day0:
        out += nn * 100 * (bs(S1, K, T, v + dv, q, cp) - bs(S0, K, T, v, q, cp))
    return out

def summary(t, plan, n=300):
    row = {}; negd = {}; negw = {}; mins = []
    for s in SCENS:
        pnl, dn, day0 = run(t, s, plan, n)
        row[s] = float(np.mean(pnl['total'])) if s == 'no view' else float(np.median(pnl['total']))
        negd[s] = float(np.mean(dn < 0)); negw[s] = float(np.mean(pnl['wkstart'] < 0)); row['negw_' + s] = negw[s]
        mins.append(float(np.percentile(dn.min(axis=1), 5)))
    row['delta0'] = float(dn[0, 0]); row['negdays'] = max(negd.values()); row['negdays_s'] = max(negd, key=negd.get)
    row['negweeks'] = max(negw.values()); row['negdays_nv'] = negd['no view']; row['negweeks_nv'] = negw['no view']; row['min5'] = min(mins)
    row['drop15'] = shock(day0, t, -0.15, 0.05); row['jump20'] = shock(day0, t, 0.20, 0.0)
    return row

def B(**kw):
    p = dict(long_n=0, itm=0.08, tenor=5, short_n=0, put_rule=('otm', 0.02), call_n=60, call_atm=0.3, call_z=0.6, qtr_n=0, year_n=0)
    p.update(kw); return p

if __name__ == '__main__':
    import time; t0 = time.time()
    for t in sys.argv[1:] or ['NKE']:
        r = summary(t, B(call_n=LEAP[t][0])); print(t, {k: (round(v) if abs(v) > 2 else round(v, 3)) if isinstance(v, float) else v for k, v in r.items()}, round(time.time() - t0, 1), 's', flush=True)
