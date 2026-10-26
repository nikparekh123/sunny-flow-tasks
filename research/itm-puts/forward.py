"""Forward test (NOT a backtest) of Nik's ITM-put overlay, 15 Oct 2026.

Book per name: the Jan 2028 LEAP calls he holds, weekly calls sold on them by the
roll-sheet rule. Overlay: buy N long puts some % in the money, ~3 or 5 months out,
rolled at expiry; sell M weekly puts slightly out of the money each Friday, always
at or below the long strike so every short put is covered (no extra margin).

Paths: 12 months from today's close. Daily moves are 5-day blocks of the stock's
own last 3 years (big days trimmed), earnings days get a jump of the stock's usual
earnings size, then each scenario's waypoints are hit exactly. Option prices:
the first long put at today's real quote; later long puts at today's IV for that
tenor, moved gently with the path's volatility; weekly options at the path's
20-day realised vol times a richness that starts at today's and fades to 1.05,
plus the earnings jump in an earnings week."""
import sys, numpy as np
from common import *

EARN_MOVE = {'NKE': 0.08, 'LULU': 0.10, 'BABA': 0.06, 'NFLX': 0.08}
LONG_STEP = {'NKE': 2.5, 'LULU': 5.0, 'BABA': 5.0, 'NFLX': 2.5}
RHO0 = {'NKE': 1.19, 'LULU': 1.05, 'BABA': 1.12, 'NFLX': 1.16}      # weekly implied / realised today
# Today's put IV by tenor (Jan 2027 ~3m, Mar 2027 ~5m, Jun 2027 ~8m) and the LEAP's (Jan 2028 ATM put)
IV_TERM = {'NKE': {3: 0.40, 5: 0.38, 8: 0.38}, 'LULU': {3: 0.48, 5: 0.49, 8: 0.50},
           'BABA': {3: 0.41, 5: 0.41, 8: 0.42}, 'NFLX': {3: 0.37, 5: 0.38, 8: 0.38}}
IV_LEAP = {'NKE': 0.38, 'LULU': 0.52, 'BABA': 0.42, 'NFLX': 0.38}

# trading calendar: index 0 = today's close (Thu 15 Oct 2026) .. Fri 15 Oct 2027
CAL = [TODAY]; d = TODAY
while d < D('2027-10-15'):
    d += datetime.timedelta(days=1)
    if d.weekday() < 5: CAL.append(d)
NDAYS = len(CAL) - 1
IDX = {c.isoformat(): i for i, c in enumerate(CAL)}
FRI = [i for i, c in enumerate(CAL) if c.weekday() == 4]
def at(s): return min(range(len(CAL)), key=lambda i: abs((CAL[i] - D(s)).days))
LONG_EXP = {3: ['2027-01-15', '2027-04-16', '2027-07-16', '2027-10-15'],
            5: ['2027-03-19', '2027-08-20', '2028-01-21'],
            8: ['2027-06-17', '2028-01-21']}
SCEN = {'flat': [(NDAYS, 1.00)], 'up 15%': [(NDAYS, 1.15)], 'rip 25% in 3m': [(63, 1.25), (NDAYS, 1.25)],
        'bull +40%': [(NDAYS, 1.40)], 'down 15%': [(NDAYS, 0.85)], 'crash 30% in 2m': [(42, 0.70), (NDAYS, 0.70)],
        'V: -20% then back': [(63, 0.80), (NDAYS, 1.00)]}

def hist_returns(t):
    cl = closes(t); ks = sorted(cl); p = np.array([cl[k] for k in ks])
    lr = np.diff(np.log(p)); sd = lr.std()
    return np.clip(lr, -3.5 * sd, 3.5 * sd) - np.clip(lr, -3.5 * sd, 3.5 * sd).mean(), lr[-60:]

def make_paths(t, scen, n, seed=7):
    rng = np.random.default_rng(seed + sum(map(ord, scen)))
    lr, pre = hist_returns(t)
    eidx = [at(e) for e in EARN[t] if TODAY < D(e) <= CAL[-1]]
    P = np.empty((n, NDAYS + 1)); R_ = np.empty((n, NDAYS))
    for j in range(n):
        out = []
        while len(out) < NDAYS:
            i = rng.integers(0, len(lr) - 5); out.extend(lr[i:i + 5])
        r = np.array(out[:NDAYS])
        for e in eidx:
            if 1 <= e <= NDAYS: r[e - 1] = rng.normal(0, EARN_MOVE[t])
        a = 0
        for end, mult in SCEN[scen]:
            seg = r[a:end]; r[a:end] = seg + (math.log(mult) - seg.sum()) / len(seg)
            a = end
        R_[j] = r
        P[j] = SPOT[t] * np.exp(np.concatenate([[0], np.cumsum(r)]))
    return P, R_, pre

def rv_series(R_, pre, w):
    """Annualised realised vol of the last w daily returns, at each day index."""
    n = R_.shape[0]; full = np.concatenate([np.tile(pre, (n, 1)), R_], axis=1)
    out = np.empty((n, NDAYS + 1)); off = len(pre)
    for i in range(NDAYS + 1):
        out[:, i] = full[:, off + i - w: off + i].std(axis=1) * math.sqrt(252)
    return out

def weekly_iv(t, rv20, i, j, T, has_earn):
    rho = 1.05 + (RHO0[t] - 1.05) * math.exp(-i / 40)
    v = max(0.12, rv20[j, i]) * rho
    if has_earn: v = math.sqrt(v * v + EARN_MOVE[t] ** 2 / T)
    return v

def simulate(t, scen, plan, n=300):
    """plan: dict(long_n, itm, tenor, short_n, otm, call_n, lotto_n)"""
    S0, q = SPOT[t], Q[t]; nL, KL = LEAP[t]; step = STEP[t]
    P, R_, pre = make_paths(t, scen, n)
    rv20 = rv_series(R_, pre, 20); rv60 = rv_series(R_, pre, 60)
    eidx = [at(e) for e in EARN[t] if TODAY < D(e) <= CAL[-1]]
    live = live_chains()[t]
    TL0 = years(TODAY, '2028-01-21')
    res = {k: np.zeros(n) for k in ('leap', 'calls', 'longput', 'shortput', 'lotto', 'putspend', 'putback')}
    for j in range(n):
        p = P[j]
        # LEAP mark-to-model change over the year
        TL1 = TL0 - NDAYS / 252
        res['leap'][j] = nL * 100 * (bs(p[-1], KL, TL1, IV_LEAP[t], q, 'C') - bs(S0, KL, TL0, IV_LEAP[t], q, 'C'))
        # long puts, rolled at each expiry; strike re-set off the spot at each purchase
        holds = []                          # (buy_idx, exp_idx, K, n)
        if plan['long_n']:
            buy = 0
            for e in LONG_EXP[plan['tenor']]:
                ei = at(e) if D(e) <= CAL[-1] else None
                S = p[buy]; target = S * (1 + plan['itm'])
                if buy == 0:
                    chain = live[e]['P']; K = min(chain, key=lambda k: abs(k - target))
                    b, a = chain[K]; px = (b + a) / 2 + (a - b) / 4
                else:
                    K = round(target / LONG_STEP[t]) * LONG_STEP[t]; T = years(CAL[buy], e)
                    v = IV_TERM[t][plan['tenor']] * min(1.6, max(0.7, (rv60[j, buy] / rv60[j, 0]) ** 0.5))
                    px = bs(S, K, T, v, q, 'P') * 1.01
                spend = plan['long_n'] * (px * 100 + 0.65)
                if ei is not None: back = plan['long_n'] * 100 * max(0.0, K - p[ei]); end = ei
                else:
                    T = years(CAL[-1], e); v = IV_TERM[t][plan['tenor']]
                    back = plan['long_n'] * 100 * bs(p[-1], K, T, v, q, 'P') * 0.99; end = NDAYS
                res['putspend'][j] += spend; res['putback'][j] += back
                res['longput'][j] += back - spend
                holds.append((buy, end, K))
                if ei is None or ei >= NDAYS: break
                buy = ei
        def long_k(i):
            for b_, e_, K_ in holds:
                if b_ <= i < e_: return K_
            return None
        # weekly legs, Friday to Friday (first sale at today's close for next Friday)
        sells = [0] + [f for f in FRI if f < NDAYS]
        for k_, i in enumerate(sells):
            ex = next((f for f in FRI if f > i + (1 if i == 0 else 0)), None)
            if ex is None or ex > NDAYS: break
            S = p[i]; T = (CAL[ex] - CAL[i]).days / 365
            earn = any(i < e <= ex for e in eidx)
            v = weekly_iv(t, rv20, i, j, T, earn)
            # short puts: slightly out of the money, never above the long strike
            if plan['short_n']:
                KLp = long_k(i)
                if KLp is not None:
                    Ks = math.floor(S * (1 - plan['otm']) / step) * step
                    Ks = min(Ks, KLp)
                    prem = bs(S, Ks, T, v, q, 'P') * 0.98 - 0.0065
                    res['shortput'][j] += plan['short_n'] * 100 * (prem - max(0.0, Ks - p[ex]))
            # calls on the LEAPs, roll-sheet rule
            if plan['call_n']:
                m = p[i] / p[max(0, i - 21)] - 1
                atm_share = 0.2 if earn else 1 / 3
                out_sd = 1.0 if m >= 0.15 else 0.6
                sd = S * v * math.sqrt(T)
                Ka = math.ceil(S / step - 1e-9) * step
                Ko = max(Ka + step, round((S + out_sd * sd) / step) * step)
                for K, part in ((Ka, atm_share), (Ko, 1 - atm_share)):
                    nn = plan['call_n'] * part
                    prem = bs(S, K, T, v, q, 'C') * 0.98 - 0.0065
                    res['calls'][j] += nn * 100 * (prem - max(0.0, p[ex] - K))
        # lotto: far out-of-the-money calls bought once, Dec 2027 expiry, marked at the end
        if plan.get('lotto_n'):
            chain = live['2027-12-17']['C']; K = min(chain, key=lambda k: abs(k - S0 * 1.35))
            b, a = chain[K]; px = (b + a) / 2 + (a - b) / 4
            Tend = years(CAL[-1], '2027-12-17')
            res['lotto'][j] = plan['lotto_n'] * 100 * (bs(p[-1], K, Tend, IV_TERM[t][8] + 0.04, q, 'C') - px)
    res['total'] = res['leap'] + res['calls'] + res['longput'] + res['shortput'] + res['lotto']
    res['overlay'] = res['longput'] + res['shortput']
    return res

def stress(t, plan, drop):
    """Value change of today's positions on an instant drop (how portfolio margin sizes risk)."""
    S0, q = SPOT[t], Q[t]; nL, KL = LEAP[t]; S1 = S0 * (1 - drop); live = live_chains()[t]
    TL = years(TODAY, '2028-01-21')
    v = nL * 100 * (bs(S1, KL, TL, IV_LEAP[t] + 0.05, q, 'C') - bs(S0, KL, TL, IV_LEAP[t], q, 'C'))
    Tw = years(TODAY, '2026-10-23'); vw = 0.36
    step = STEP[t]
    if plan['call_n']:
        Ka = math.ceil(S0 / step) * step
        v -= plan['call_n'] * 100 * (bs(S1, Ka, Tw, vw, q, 'C') - bs(S0, Ka, Tw, vw, q, 'C'))
    if plan['long_n']:
        e = LONG_EXP[plan['tenor']][0]; chain = live[e]['P']; K = min(chain, key=lambda k: abs(k - S0 * (1 + plan['itm'])))
        T = years(TODAY, e); iv0 = IV_TERM[t][plan['tenor']]
        v += plan['long_n'] * 100 * (bs(S1, K, T, iv0 + 0.05, q, 'P') - bs(S0, K, T, iv0, q, 'P'))
        if plan['short_n']:
            Ks = min(math.floor(S0 * (1 - plan['otm']) / step) * step, K)
            v -= plan['short_n'] * 100 * (bs(S1, Ks, Tw, vw + 0.05, q, 'P') - bs(S0, Ks, Tw, vw, q, 'P'))
    return v

def fmt(x): return f"{'-' if x < 0 else ' '}${abs(x)/1000:,.1f}K"
def table(t, plans, scens=None, n=300):
    scens = scens or list(SCEN)
    print(f"\n{t}  spot {SPOT[t]}  LEAPs {LEAP[t][0]} x {LEAP[t][1]:g}C Jan 2028   (median total P&L over 12 months; overlay = long + short puts)")
    hdr = f"{'plan':44}" + "".join(f"{s[:16]:>18}" for s in scens) + f"{'-15% now':>11}{'-25% now':>11}"
    print(hdr)
    base = None
    for name, plan in plans:
        row = f"{name[:44]:44}"
        for s in scens:
            r = simulate(t, s, plan, n)
            row += f"{fmt(np.median(r['total'])):>10} ({fmt(np.median(r['overlay'])).strip():>6})"
        row += f"{fmt(stress(t, plan, 0.15)):>11}{fmt(stress(t, plan, 0.25)):>11}"
        print(row, flush=True)

if __name__ == '__main__':
    t = sys.argv[1] if len(sys.argv) > 1 else 'NKE'
    nL = LEAP[t][0]
    plans = [
        ('LEAPs + calls on all (today)', dict(long_n=0, itm=0, tenor=3, short_n=0, otm=0, call_n=nL)),
        ('Nik: 25 Jan 40P, sell 15 wkly 1.5% OTM', dict(long_n=round(nL * 25 / 60), itm=0.08, tenor=3, short_n=round(nL * 15 / 60), otm=0.015, call_n=nL)),
    ]
    table(t, plans)
