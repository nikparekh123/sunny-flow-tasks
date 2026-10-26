"""Nik's playbook on NKE's real year (17 Oct 2026). Every Friday Oct 2025 - Oct 2026:
work out the seven reads from data available that day, pick the call variation from
the menu, sell at the real Theta end-of-day mids for the next Friday, settle at
that Friday's close. Compared with today's rule, fixed 0.6 sigma, fixed 2%, and
0.6 sigma with the vetoes only. 60 calls (the LEAPs), 13 weekly puts.

Read rules and mapping as agreed 17 Oct (memory: planner playbook). Assumptions:
fundamentals = Nasdaq analyst consensus only (models have no history); events
caution = ex-dividend or a Fed decision before expiry -> 40 of 60 calls (CPI/jobs
dates not stored); delta approval not modelled; fills at mid, $0.65 a contract.
Usage: python3 -I playbook_replay.py"""
import json, math, os, datetime as dt
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
D = dt.date.fromisoformat
R = 0.04
def ncdf(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))
def bs(S, K, T, v, call=True):
    sq = v * math.sqrt(T); d1 = (math.log(S / K) + (R + v * v / 2) * T) / sq; d2 = d1 - sq
    return S * ncdf(d1) - K * math.exp(-R * T) * ncdf(d2) if call else K * math.exp(-R * T) * ncdf(-d2) - S * ncdf(-d1)
def iv_of(mid, S, K, T, call=True):
    if not mid > max(0.0, (S - K) if call else (K - S)) + 0.005: return None
    lo, hi = 0.02, 4.0
    for _ in range(60):
        m = (lo + hi) / 2
        if bs(S, K, T, m, call) < mid: lo = m
        else: hi = m
    return (lo + hi) / 2

bars = []
for f in ('nke_0.json', 'nke_a.json', 'nke_b.json'): bars += json.load(open(os.path.join(DATA, f)))['response']
bars = sorted({b['created'][:10]: b for b in bars if b.get('close')}.values(), key=lambda b: b['created'])
DAYS = [b['created'][:10] for b in bars]; C = [b['close'] for b in bars]; HI = [b['high'] for b in bars]; LO = [b['low'] for b in bars]
IV = {k: float(v) for k, v in json.load(open(os.path.join(DATA, 'nke_iv_old.json'))).items()}
IV.update({r['d']: float(r['iv']) for r in json.load(open(os.path.join(DATA, 'nke_iv.json')))})
tg = json.load(open(os.path.join(DATA, 'nke_targets.json')))['data']['historicalConsensus']
TARGETS = sorted((dt.datetime.utcfromtimestamp(h['x']).date().isoformat(), float(h['y'])) for h in tg)
WEEKS = json.load(open(os.path.join(DATA, 'nke_weeklies.json')))
EARN = ['2025-10-01', '2025-12-19', '2026-04-01', '2026-07-01', '2026-09-30']      # reaction sessions
EXDIV = ['2025-12-01', '2026-03-02', '2026-06-01', '2026-09-01']
FED = ['2025-10-29', '2025-12-10', '2026-01-28', '2026-03-18', '2026-04-29', '2026-06-17', '2026-07-29', '2026-09-16']

def sma(xs, n): return sum(xs[-n:]) / n
def ema(xs, n):
    k = 2 / (n + 1); e = sum(xs[:n]) / n
    for x in xs[n:]: e = x * k + e * (1 - k)
    return e
def rsi(xs, n=14):
    g = l = 0.0
    for i in range(1, len(xs)):
        ch = xs[i] - xs[i - 1]; up, dn = max(0, ch), max(0, -ch)
        if i <= n: g += up / n; l += dn / n
        else: g = (g * (n - 1) + up) / n; l = (l * (n - 1) + dn) / n
    return 100 if l == 0 else 100 - 100 / (1 + g / l)
def hv(xs, n):
    r = [math.log(xs[i] / xs[i - 1]) for i in range(len(xs) - n, len(xs))]
    m = sum(r) / n; return math.sqrt(sum((x - m) ** 2 for x in r) / (n - 1) * 252)

def hv_ex(i, n=20):
    """Realised volatility over the last n daily moves, LEAVING OUT earnings reaction days
    (a -15% report day otherwise sits in the 20-day number for a month and vetoes good weeks)."""
    r = [math.log(C[j] / C[j - 1]) for j in range(i, 0, -1) if DAYS[j] not in EARN][:n]
    m = sum(r) / len(r); return math.sqrt(sum((x - m) ** 2 for x in r) / (len(r) - 1) * 252)

def reads(d):
    i = DAYS.index(d); c = C[:i + 1]; S = c[-1]
    tgt = [y for x, y in TARGETS if x <= d]; val = tgt[-1] if tgt else None
    fund = 'neutral' if val is None else 'bullish' if val > S * 1.10 else 'bearish' if val < S * 0.90 else 'neutral'
    e20, s50, r14 = ema(c, 20), sma(c, 50), rsi(c[-120:])
    tech = 'bullish' if S > e20 and S > s50 and 50 <= r14 <= 70 else 'bearish' if S < e20 and S < s50 and r14 < 50 else 'mixed'
    ivd = [IV[x] for x in DAYS[max(0, i - 251):i + 1] if x in IV]
    iv_now = IV.get(d) or (ivd[-1] if ivd else None); h20 = hv_ex(i) if os.environ.get('HV') != 'raw' else hv(c, 20)
    rank = (iv_now - min(ivd)) / (max(ivd) - min(ivd)) * 100 if iv_now and len(ivd) >= 120 and max(ivd) > min(ivd) else None
    rich = iv_now / h20 if iv_now else None
    ivr = 'veto' if (rank is not None and rank < 25) or (rich is not None and rich < 1) else 'rich' if rank and rank >= 50 and rich >= 1.2 else 'ok'
    m21 = c[-22:]; lo, hi = min(m21), max(m21); pos = (S - lo) / (hi - lo) if hi > lo else 0.5
    w5 = S / c[-6] - 1; mo = S / c[-22] - 1
    hist = ('stretched up' if pos >= 0.9 and w5 >= 0.05 else 'stretched down' if pos <= 0.1 and w5 <= -0.05
            else 'up' if mo > 0.05 else 'down' if mo < -0.05 else 'flat')
    s200, s200p = sma(c, 200), sum(c[-221:-21]) / 200
    mom = 'bullish' if S > s200 and s200 > s200p else 'bearish' if S < s200 and s200 < s200p else 'mixed'
    return dict(S=S, fund=fund, tech=tech, iv=ivr, rank=rank, rich=rich, hist=hist, mom=mom, w5=w5, hi5=max(HI[i - 4:i + 1]))

def settle(e):
    ks = [x for x in DAYS if x <= e]; return C[DAYS.index(ks[-1])]

MENU = [(0.2, 0.6), (0.0, 0.6), (0.0, 0.8), (0.0, 1.0)]        # (ATM share, sigma of the rest)
ARMS = ['playbook', 'playbook + tweaks', 'candidate, 10% free', 'candidate, 20% free', "today's rule", 'fixed 0.6 sigma', 'fixed 2%', '0.6 sigma + vetoes only']
res = {a: dict(calls=0.0, puts=0.0, weeks=[]) for a in ARMS}
picks = {}; vetoes = {'iv': 0, 'events': 0, 'caution': 0}
for sale in sorted(WEEKS):
    w = WEEKS[sale]; e = w['expiry']; rd = reads(sale); S = rd['S']; Se = settle(e)
    T = max(1, (D(e) - D(sale)).days) / 365
    CQ = {float(k): (b + a) / 2 for k, (b, a) in w['C'].items() if a > 0}
    PQ = {float(k): (b + a) / 2 for k, (b, a) in w['P'].items() if a > 0}
    katm = min(CQ, key=lambda k: abs(k - S)); v = iv_of(CQ[katm], S, katm, T) or 0.35
    sig = S * v * math.sqrt(T)
    def call_at(x): ks = sorted(k for k in CQ if k >= x); return ks[0] if ks else max(CQ)
    def put_at(x): ks = sorted(k for k in PQ if k <= x); return ks[-1] if ks else min(PQ)
    def calls_pnl(parts):   # [(n, K)]
        return sum(n * 100 * (CQ[K] - max(0, Se - K)) - 0.65 * n for n, K in parts if n)
    def puts_pnl(n, K): return n * 100 * (PQ[K] - max(0, K - Se)) - 0.65 * n if n else 0.0
    earn = any(sale < x <= e for x in EARN); caution = any(sale < x <= e for x in EXDIV + FED)
    m21 = S / C[DAYS.index(sale) - 21] - 1
    # today's rule
    atm = 0.2 if earn else 1 / 3; z = 1.0 if m21 >= 0.15 else 0.6
    ka = call_at(S); ko = call_at(S + z * sig); ko = ko if ko > ka else call_at(ka + 0.01)
    na = round(60 * atm)
    put2 = put_at(S * 0.98)
    out = {"today's rule": (calls_pnl([(na, ka), (60 - na, ko)]), puts_pnl(13, put2)),
           'fixed 0.6 sigma': (calls_pnl([(60, call_at(S + 0.6 * sig))]), puts_pnl(13, put2)),
           'fixed 2%': (calls_pnl([(60, call_at(S * 1.02))]), puts_pnl(13, put2))}
    # vetoes
    veto = rd['iv'] == 'veto' or earn
    if rd['iv'] == 'veto': vetoes['iv'] += 1
    if earn: vetoes['events'] += 1
    if caution and not veto: vetoes['caution'] += 1
    n_calls = 0 if veto else 40 if caution else 60
    out['0.6 sigma + vetoes only'] = (calls_pnl([(n_calls, call_at(S + 0.6 * sig))]), puts_pnl(0 if veto else 13, put2))
    # playbook
    idx = 2 if rd['mom'] == 'bullish' else 1
    if rd['fund'] == 'bearish': idx -= 1
    if rd['hist'] == 'stretched up': idx += 1
    if rd['hist'] == 'stretched down': idx -= 1
    if rd['mom'] == 'bullish' and rd['tech'] == 'bullish': idx += 1
    idx = max(0, min(3, idx)); share, zz = MENU[idx]
    k_out = call_at(S + zz * sig)
    if rd['w5'] >= 0.05 and k_out <= rd['hi5']: k_out = call_at(rd['hi5'] + 0.01)   # fresh breakout range: next strike up
    n_atm = round(n_calls * share)
    pz = 0.8 if rd['mom'] == 'bearish' else 0.6
    n_puts = 0 if (veto or rd['hist'] == 'stretched down') else 13
    out['playbook'] = (calls_pnl([(n_atm, call_at(S)), (n_calls - n_atm, k_out)]), puts_pnl(n_puts, put_at(S - pz * sig)))
    # TWEAKS (Nik, 17 Oct): (1) earnings inside the window -> no veto: all calls at 1 sigma, no puts;
    # (2) caution only for an ex-dividend date when the calls sit near the money (within 2%), not Fed days
    exdiv = any(sale < x <= e for x in EXDIV)
    for lab_, full in (('playbook + tweaks', 60), ('candidate, 10% free', 54), ('candidate, 20% free', 48)):
        if rd['iv'] == 'veto':
            out[lab_] = (0.0, 0.0)
        elif earn:
            out[lab_] = (calls_pnl([(full, call_at(S + 1.0 * sig))]), 0.0)
        else:
            near = min(call_at(S) if n_atm else k_out, k_out) <= S * 1.02
            n2 = round(full * 2 / 3) if (exdiv and near) else full; na2 = round(n2 * share)
            out[lab_] = (calls_pnl([(na2, call_at(S)), (n2 - na2, k_out)]), puts_pnl(0 if rd['hist'] == 'stretched down' else 13, put_at(S - pz * sig)))
    lab = 'veto' if veto else ['20% ATM + 0.6σ', '0.6σ', '0.8σ', '1σ'][idx]
    picks[lab] = picks.get(lab, 0) + 1
    for a in ARMS:
        res[a]['calls'] += out[a][0]; res[a]['puts'] += out[a][1]; res[a]['weeks'].append(out[a][0] + out[a][1])
    res['playbook'].setdefault('log', []).append(dict(sale=sale, S=round(S, 2), move=round((Se / S - 1) * 100, 1), pick=lab, **{k: rd[k] for k in ('fund', 'tech', 'iv', 'hist', 'mom')}))

print(f"{len(WEEKS)} weeks {min(WEEKS)} to {max(WEEKS)} | NKE {C[DAYS.index(min(WEEKS))]:.2f} -> {C[-1]:.2f}")
print('playbook picks:', picks, '| vetoes:', vetoes)
for a in ARMS:
    r = res[a]; tot = r['calls'] + r['puts']; lose = sum(1 for x in r['weeks'] if x < 0)
    print(f"{a:26s} calls ${r['calls']:>9,.0f}  puts ${r['puts']:>8,.0f}  total ${tot:>9,.0f}  losing weeks {lose:2d}  worst ${min(r['weeks']):>8,.0f}")
json.dump(res['playbook']['log'], open(os.path.join(DATA, 'playbook_log.json'), 'w'), indent=0)
