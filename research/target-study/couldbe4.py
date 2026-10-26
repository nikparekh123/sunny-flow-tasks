"""Study 1, part 5: the CANDIDATE RULE on calm and VIOLENT NKE paths (Nik, 17 Oct 2026).
Based on part 4: DYNAMIC STRIKES from a 2% or 3% base (IV, momentum, history), selling all 60.
Based on part 3: STRIKE STRUCTURES (Nik, 17 Oct 2026), each under sell-all and gentler.
Based on part 2: (Nik, 17 Oct 2026): what does holding NKE's delta target on
"COULD BE" cost? "Could be" = delta left if NKE moves 5% up or down by the
Thursday before the week's calls expire; the lower of the two counts.

Four ways to run the weekly calls on today's NKE book (60 Jan 2028 30C LEAPs,
25 hedge puts ~8% in the money rolled, 13 weekly puts 2% out, 5 three-month
calls ~15% out rolled, 15 one-year calls ~30% out), 12 months, 300 made-up
paths per scenario, on the itm-puts engine (block.py):
  0 baseline   sell all 60 every week (today's One Rule)
  1 strict     sell only as many as keep could-be >= 30% of the 6,000 LEAP shares
  2 gentler    could-be never net short (>= 0%) AND delta now >= 30%
  3 cover      sell all 60, and each Friday buy enough 3-month calls ~15% out
               to keep could-be >= 30% (held to expiry, cost counted)
Run from research/itm-puts with /usr/bin/python3 (numpy lives in the user site):
  /usr/bin/python3 ../target-study/couldbe.py        (RHO_MODE=hold for rich options)"""
import sys, os, json, math, numpy as np
sys.path.insert(0, os.getcwd())
from block import *

# NKE's real closes before the test starts, so the 200-day line and the 21-day change exist from day one
_h = []
for _f in ('nke_a.json', 'nke_b.json'):
    _h += json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', _f)))['response']
_h = sorted({x['created'][:10]: x['close'] for x in _h if x.get('close')}.items())
HIST = np.array([c for d, c in _h if d < str(TODAY)])
V_REF = 0.40
import forward as F
VOLK = {'k': 1.0}
_hr0 = F.hist_returns
def _hr_scaled(t):
    lr, pre = _hr0(t); k = VOLK['k']; return lr * k, pre * k
F.hist_returns = _hr_scaled
from forward import NDAYS as _ND
F.SCEN['rip +25% in 2 weeks (violent)'] = [(10, 1.25), (_ND, 1.25)]
F.SCEN['rally +50% in 3 months (violent)'] = [(63, 1.50), (_ND, 1.50)]
F.SCEN['whipsaw +20% then back (violent)'] = [(21, 1.20), (42, 1.00), (_ND, 1.00)]
F.SCEN['flat (violent)'] = [(_ND, 1.00)]     # NKE's average 30-day IV over the last year (ticker_iv_daily)
TARGET = 0.30; MOVE = 0.05; COVER_OTM = 1.15; COVER_DAYS = 63

def run_cb(t, scen, plan, mode, struct, n=300):
    P, rv20, rv60 = paths(t, scen, n)
    S0, q, step = SPOT[t], Q[t], STEP[t]; nL, KL = LEAP[t]; live = live_all()[t]
    eidx = [at(e) for e in EARN[t] if TODAY < D(e) <= CAL[-1]]
    Tl = np.array([yrs(i, '2028-01-21') for i in range(NDAYS + 1)])
    pnl = {k: np.zeros(n) for k in ('leap', 'calls', 'longput', 'shortput', 'extra', 'cover')}
    dnet = nL * 100 * dlv(P, KL, Tl[None, :], IV_LEAP[t], q, 'C')
    pnl['leap'] = nL * 100 * (bsv(P[:, -1], KL, Tl[-1], IV_LEAP[t], q, 'C') - bs(S0, KL, Tl[0], IV_LEAP[t], q, 'C'))
    held = []   # (n per path or scalar, K per path, expiry day index, v per path, cp, start day): every long or short leg except weekly calls
    # hedge puts, rolled at expiry
    b = 0
    for e in LONG_EXP[plan['tenor']]:
        ei = at(e) if D(e) <= CAL[-1] else None
        S = P[:, b]
        if b == 0:
            ch = live[e]['P']; K0 = min(ch, key=lambda k: abs(k - S0 * (1 + plan['itm']))); bb, aa = ch[K0]
            K = np.full(n, K0); px = np.full(n, (bb + aa) / 2 + (aa - bb) / 4); v = np.full(n, iv((bb + aa) / 2, S0, K0, yrs(0, e), q, 'P'))
        else:
            K = np.round(S * (1 + plan['itm']) / LONG_STEP[t]) * LONG_STEP[t]
            v = IV_TERM[t][plan['tenor']] * np.clip((rv60[:, b] / rv60[:, 0]) ** 0.5, 0.7, 1.6)
            px = bsv(S, K, yrs(b, e), v, q, 'P') * 1.01
        end = ei if ei is not None else NDAYS
        for d in range(b, end): dnet[:, d] += plan['long_n'] * 100 * dlv(P[:, d], K, yrs(d, e), v, q, 'P')
        back = np.maximum(0, K - P[:, ei]) if ei is not None else bsv(P[:, -1], K, yrs(NDAYS, e), v, q, 'P') * 0.99
        pnl['longput'] += plan['long_n'] * (100 * back - px * 100 - 0.65)
        held.append((plan['long_n'], K, e, v, 'P', b, end))
        if ei is None or ei >= NDAYS: break
        b = ei
    # three-month upside calls, rolled
    b = 0
    for e in QTR:
        ei = at(e)
        if b == 0:
            ch = live['2027-01-15']['C']; K0 = min(ch, key=lambda k: abs(k - S0 * 1.15)); bb, aa = ch[K0]
            K = np.full(n, K0); px = (bb + aa) / 2 + (aa - bb) / 4; iq = iv((bb + aa) / 2, S0, K0, yrs(0, e), q, 'C'); v = np.full(n, iq)
        else:
            K = np.round(P[:, b] * 1.15 / LONG_STEP[t]) * LONG_STEP[t]
            v = iq * np.clip((rv60[:, b] / rv60[:, 0]) ** 0.5, 0.7, 1.6)
            px = bsv(P[:, b], K, yrs(b, e), v, q, 'C') * 1.03
        pnl['extra'] += plan['qtr_n'] * (100 * (np.maximum(0, P[:, ei] - K) - px) - 0.65)
        for d in range(b, ei): dnet[:, d] += plan['qtr_n'] * 100 * dlv(P[:, d], K, yrs(d, e), v, q, 'C')
        held.append((plan['qtr_n'], K, e, v, 'C', b, ei))
        b = ei
    iq_cover = iq
    # one-year upside call
    ye = '2027-12-17' if '2027-12-17' in live else '2028-01-21'
    ch = live[ye]['C']; Ky = min(ch, key=lambda k: abs(k - S0 * 1.30)); bb, aa = ch[Ky]; px = (bb + aa) / 2 + (aa - bb) / 4
    vy = iv((bb + aa) / 2, S0, Ky, yrs(0, ye), q, 'C')
    pnl['extra'] += plan['year_n'] * (100 * (bsv(P[:, -1], Ky, yrs(NDAYS, ye), vy, q, 'C') - px) - 0.65)
    dnet += plan['year_n'] * 100 * dlv(P, Ky, np.array([yrs(i, ye) for i in range(NDAYS + 1)])[None, :], vy, q, 'C')
    held.append((plan['year_n'], np.full(n, Ky), ye, np.full(n, vy), 'C', 0, NDAYS + 1))
    covers = []   # (n per path, K per path, expiry day index, v per path, start day)

    def other_delta(Sx, i, dx):
        """Delta of every leg held over day i, priced at price Sx on day dx (LEAPs, hedge, upside, covers)."""
        out = nL * 100 * dlv(Sx, KL, Tl[dx], IV_LEAP[t], q, 'C')
        for nn, K, e, v, cp, b0, e0 in held:
            if b0 <= i < e0: out = out + nn * 100 * dlv(Sx, K, yrs(dx, e), v, q, cp)
        for nn, K, ec, v, b0 in covers:
            if b0 <= i < ec: out = out + nn * 100 * dlv(Sx, K, max(1e-6, (CAL[min(ec, NDAYS)] - CAL[dx]).days / 365), v, q, 'C')
        return out

    first_ex = next(f for f in FRI if f > 1)
    sells = [0] + [f for f in FRI if first_ex <= f < NDAYS]
    short_days = []
    for i in sells:
        ex = next((f for f in FRI if f > max(i, 1)), None)
        if ex is None or ex > NDAYS: break
        S = P[:, i]; T = yrs(i, ex); earn = any(i < e <= ex for e in eidx)
        rho = RHO0[t] if os.environ.get('RHO_MODE') == 'hold' else 1.05 + (RHO0[t] - 1.05) * math.exp(-i / 40)
        v = np.maximum(0.12, rv20[:, i]) * rho
        if earn: v = np.sqrt(v * v + EARN_MOVE[t] ** 2 / T)
        sd = S * v * math.sqrt(T)
        # weekly puts, covered by the hedge strike
        KLp = None
        for nn, K, e, vv, cp, b0, e0 in held:
            if cp == 'P' and b0 <= i < e0: KLp = K
        put_legs = []
        if plan['short_n'] and KLp is not None:
            Kp = np.minimum(np.floor(S * (1 - 0.02) / step) * step, KLp)
            put_legs = [(-plan['short_n'], Kp)]
        atm = min(plan['call_atm'], 0.2) if earn else plan['call_atm']
        m = S / P[:, max(0, i - 21)] - 1
        z = np.where(m >= 0.15, max(1.0, plan['call_z']), plan['call_z'])
        Ka = np.ceil(S / step - 1e-9) * step
        if struct == 'rule':
            Ko = np.maximum(Ka + step, np.round((S + z * sd) / step) * step)
            parts = [(atm, Ka), (1 - atm, Ko)]
        elif struct == 'candidate':
            need = 200 + 21
            past = HIST[-max(0, need - i):] if need - i > 0 else HIST[:0]
            seq = np.concatenate([np.tile(past, (n, 1)), P[:, :i + 1]], axis=1)
            sma200 = seq[:, -200:].mean(axis=1); sma200p = seq[:, -221:-21].mean(axis=1)
            mom_up = (S > sma200) & (sma200 > sma200p); mom_dn = (S < sma200) & (sma200 < sma200p)
            e20 = seq[:, -20:].mean(axis=1); s50 = seq[:, -50:].mean(axis=1)
            d = np.diff(seq[:, -15:], axis=1); g = np.clip(d, 0, None).mean(axis=1); l = np.clip(-d, 0, None).mean(axis=1)
            rsi = 100 - 100 / (1 + g / np.maximum(l, 1e-9))
            tech_up = (S > e20) & (S > s50) & (rsi >= 50) & (rsi <= 70)
            m21 = seq[:, -22:]; lo, hi = m21.min(axis=1), m21.max(axis=1); pos = (S - lo) / np.maximum(hi - lo, 1e-9)
            w5 = S / seq[:, -6] - 1
            st_up = (pos >= 0.9) & (w5 >= 0.05); st_dn = (pos <= 0.1) & (w5 <= -0.05)
            idx = np.where(mom_up, 2, 1) + st_up * 1 - st_dn * 1 + (mom_up & tech_up) * 1
            idx = np.clip(idx, 0, 3)
            share = np.where(idx == 0, 0.2, 0.0); zz = np.choose(idx, [0.6, 0.6, 0.8, 1.0])
            if earn: share = np.zeros(n); zz = np.full(n, 1.0)
            Kz = np.ceil((S + zz * sd) / step - 1e-9) * step
            hi5 = seq[:, -5:].max(axis=1)
            Kz = np.where((w5 >= 0.05) & (Kz <= hi5), np.ceil((hi5 + 0.01) / step - 1e-9) * step, Kz)
            parts = [(share, Ka), (1 - share, Kz)]
            # puts: half size at 0.6 sigma, 0.8 when momentum is bearish; none if stretched down or in an earnings week
            if put_legs:
                pz = np.where(mom_dn, 0.8, 0.6)
                Kp2 = np.minimum(np.floor((S - pz * sd) / step) * step, KLp)
                np_ = -plan['short_n'] * (~st_dn) * (0 if earn else 1)
                put_legs = [(np_, Kp2)]
        elif isinstance(struct, dict):
            pct = np.full(n, struct['base'])
            if 'iv' in struct['use']:
                pct = pct * np.clip(v / V_REF, 0.5, 2.0)
            if 'mom' in struct['use'] or 'hist' in struct['use']:
                need = 200 + 21
                past = HIST[-max(0, need - i):] if need - i > 0 else HIST[:0]
                seq = np.concatenate([np.tile(past, (n, 1)), P[:, :i + 1]], axis=1)
            if 'mom' in struct['use']:
                sma = seq[:, -200:].mean(axis=1); sma_prev = seq[:, -221:-21].mean(axis=1)
                up = (S > sma) & (sma > sma_prev); down = (S < sma) & (sma < sma_prev)
                pct = pct + 0.01 * up - 0.005 * down
            if 'hist' in struct['use']:
                m21 = S / seq[:, -22] - 1
                pct = pct + 0.01 * (m21 > 0.08) - 0.005 * (m21 < -0.08)
            pct = np.clip(pct, 0.01, 0.06)
            parts = [(1.0, np.ceil(S * (1 + pct) / step - 1e-9) * step)]
        else:
            # (share, pct out): strike = first listed step at or above price x (1 + pct); 0 = at the money
            near = min(struct[0][0], 0.2) if (earn and len(struct) > 1) else struct[0][0]
            shares = [near] + [1 - near] if len(struct) > 1 else [1.0]
            parts = [(sh, np.ceil(S * (1 + pc) / step - 1e-9) * step) for sh, (_, pc) in zip(shares, struct)]
        dthu = max(i, ex - 1); Tthu = max(1e-6, yrs(dthu, ex) + 0.25 / 365)
        def could(sgn, nc):
            Sx = S * (1 + sgn * MOVE)
            base = other_delta(Sx, i, dthu) + sum(nn * 100 * dlv(Sx, Kp, Tthu, v, q, 'P') for nn, Kp in put_legs)
            per = -100 * sum(sh * dlv(Sx, K, Tthu, v, q, 'C') for sh, K in parts)
            return base, per        # could-be = base + nc * per  (per < 0)
        bu, pu = could(+1, 0); bd, pd = could(-1, 0)
        cap = float(plan['call_n'])
        def max_calls(floor):
            lim_u = np.floor((bu - floor) / np.maximum(-pu, 1e-6)); lim_d = np.floor((bd - floor) / np.maximum(-pd, 1e-6))
            return np.clip(np.minimum(lim_u, lim_d), 0, cap)
        tgt = TARGET * nL * 100
        if mode == 'baseline' or mode == 'cover':
            nc = np.full(n, cap)
        elif mode == 'strict':
            nc = max_calls(tgt)
        else:  # gentler: could-be never net short AND delta now >= target
            have = dnet[:, i] + sum(nn * 100 * dlv(S, Kp, T, v, q, 'P') for nn, Kp in put_legs)
            per_now = 100 * sum(sh * dlv(S, K, T, v, q, 'C') for sh, K in parts)
            nc = np.minimum(max_calls(0.0), np.clip(np.floor((have - tgt) / np.maximum(per_now, 1e-6)), 0, cap))
        if mode == 'cover':
            short = np.maximum(0.0, tgt - np.minimum(bu + cap * pu, bd + cap * pd))
            if short.any():
                ec = min(i + COVER_DAYS, NDAYS + 40)
                Kc = np.round(S * COVER_OTM / LONG_STEP[t]) * LONG_STEP[t]
                vc = iq_cover * np.clip((rv60[:, i] / rv60[:, 0]) ** 0.5, 0.7, 1.6)
                Tc = (CAL[min(ec, NDAYS)] - CAL[i]).days / 365 + max(0, ec - NDAYS) / 252
                dc = 100 * dlv(S * (1 + MOVE), Kc, max(1e-6, Tc - 4 / 365), vc, q, 'C')
                nn = np.ceil(short / np.maximum(dc, 1e-6)) * (short > 0)
                pxc = bsv(S, Kc, Tc, vc, q, 'C') * 1.03
                if ec <= NDAYS: back = np.maximum(0, P[:, ec] - Kc)
                else: back = bsv(P[:, -1], Kc, max(1e-6, (ec - NDAYS) / 252), vc, q, 'C') * 0.97
                pnl['cover'] += nn * (100 * (back - pxc) - 0.65)
                for d in range(i, min(ec, NDAYS + 1)):
                    dnet[:, d] += nn * 100 * dlv(P[:, d], Kc, max(1e-6, Tc - (CAL[d] - CAL[i]).days / 365), vc, q, 'C')
                covers.append((nn, Kc, ec, vc, i))
        legs = [(nn, Kp, 'P') for nn, Kp in put_legs] + [(-nc * sh, K, 'C') for sh, K in parts]
        for nn, K, cp in legs:
            prem = bsv(S, K, T, v, q, cp) * 0.98 - 0.0065
            pay = np.maximum(0, (P[:, ex] - K) if cp == 'C' else (K - P[:, ex]))
            pnl['calls' if cp == 'C' else 'shortput'] += -nn * 100 * (prem - pay)
            for d in range(i, ex): dnet[:, d] += nn * 100 * dlv(P[:, d], K, yrs(d, ex), v, q, cp)
        cu = bu + nc * pu
        short_days.append(np.mean(cu < 0))
        pnl.setdefault('ncalls', []).append(float(np.mean(nc)))
    pnl['total'] = sum(pnl[k] for k in ('leap', 'calls', 'longput', 'shortput', 'extra', 'cover'))
    return pnl, dnet[:, :NDAYS], float(np.mean(short_days))

book = dict(long_n=25, itm=0.08, tenor=5, short_n=13, put_rule=('otm', 0.02), call_n=60, call_atm=1 / 3, call_z=0.6, qtr_n=5, year_n=15)
SC = ['flat', 'up 15%', 'bull +40%', 'jump 30% in 1m', 'down 15%', 'crash 30% in 2m', 'no view',
      'flat (violent)', 'rip +25% in 2 weeks (violent)', 'rally +50% in 3 months (violent)', 'whipsaw +20% then back (violent)']
ARMSX = [("today's rule", 'rule', 60), ('fixed 2%', [(1.0, 0.02)], 60), ('candidate rule', 'candidate', 60), ('candidate, 15% free', 'candidate', 51)]
res = {}
for lab, st, ncall in ARMSX:
    row = {}
    for s_ in SC:
        VOLK['k'] = 1.5 if 'violent' in s_ else 1.0
        bk = dict(book); bk['call_n'] = ncall
        pnl, dn, couldneg = run_cb('NKE', s_, B(**bk), 'baseline', st)
        agg = np.mean if s_ == 'no view' else np.median
        row[s_] = dict(total=float(agg(pnl['total'])), p5=float(np.percentile(pnl['total'], 5)), short=float(np.mean(dn < 0)))
    res[lab] = row
    print(lab, {k: round(v['total'] / 1000, 1) for k, v in row.items()}, flush=True)
json.dump(res, open('../target-study/data/candidate_' + os.environ.get('RHO_MODE', 'fade') + '.json', 'w'), indent=1)
