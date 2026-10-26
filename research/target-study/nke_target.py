"""Study 1 (Nik, 17 Oct 2026): how much delta should NKE keep, and should that
depend on how far the price sits below fundamental value?

Replays Oct 2025 to Oct 2026 week by week with real weekly quotes (Theta end of
day). Each week the calls follow our rule (a third at the money, 20% in an
earnings week, the rest at 0.6 SD, 1 SD after a 15%+ month). Arms differ ONLY in
how many of the 60 LEAPs get a call, so the difference between arms is the call
P&L; the LEAP, hedge and upside legs are identical across arms and left out.
Delta left is reported for each arm against TODAY'S book (LEAP 60 at 0.75,
25 hedge puts ~8% in the money, 13 weekly puts 2% out, 20 upside calls at ~0.30)
so the arms read as targets. Fundamental value = Nasdaq's monthly analyst
consensus (the models have no history). Usage: python3 -I nke_target.py"""
import json, math, os, datetime as dt

HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
D = dt.date.fromisoformat
R = 0.04

def ncdf(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))
def bs(S, K, T, v, call=True):
    sq = v * math.sqrt(T); d1 = (math.log(S / K) + (R + v * v / 2) * T) / sq; d2 = d1 - sq
    if call: return S * ncdf(d1) - K * math.exp(-R * T) * ncdf(d2), ncdf(d1)
    return K * math.exp(-R * T) * ncdf(-d2) - S * ncdf(-d1), ncdf(d1) - 1
def iv_of(mid, S, K, T, call=True):
    intr = max(0.0, (S - K) if call else (K - S))
    if not mid > intr + 0.005: return None
    lo, hi = 0.02, 4.0
    for _ in range(60):
        m = (lo + hi) / 2
        if bs(S, K, T, m, call)[0] < mid: lo = m
        else: hi = m
    return (lo + hi) / 2

bars = []
for f in ('nke_a.json', 'nke_b.json'): bars += json.load(open(os.path.join(DATA, f)))['response']
close = {b['created'][:10]: b['close'] for b in bars if b.get('close')}
days = sorted(close)
def px_on_or_before(d):
    ks = [x for x in days if x <= d]; return close[ks[-1]]
weeks = json.load(open(os.path.join(DATA, 'nke_weeklies.json')))
tg = json.load(open(os.path.join(DATA, 'nke_targets.json')))['data']['historicalConsensus']
targets = sorted((dt.datetime.utcfromtimestamp(h['x']).date().isoformat(), float(h['y'])) for h in tg)
def target_on(d): return [y for x, y in targets if x <= d][-1]
# Earnings reaction days (the session after an after-close report), from the price data:
# 30 Sep 2025, 18 Dec 2025, 31 Mar 2026, 30 Jun 2026, 29 Sep 2026 reports.
EARN_REACT = ['2025-10-01', '2025-12-19', '2026-04-01', '2026-07-01', '2026-09-30']

ARMS = [60, 48, 36, 24, 12]          # calls sold of 60 LEAPs (100%, 80%, 60%, 40%, 20%)
rows = []
for sale in sorted(weeks):
    w = weeks[sale]; e = w['expiry']; S = close[sale]; Se = px_on_or_before(e)
    T = max(1, (D(e) - D(sale)).days) / 365
    C = {float(k): (b + a) / 2 for k, (b, a) in w['C'].items() if a > 0}
    P = {float(k): (b + a) / 2 for k, (b, a) in w['P'].items() if a > 0}
    if not C: continue
    katm = min(C, key=lambda k: abs(k - S))
    v = iv_of(C[katm], S, katm, T) or 0.35
    sd = S * v * math.sqrt(T)
    i = days.index(sale); back = close[days[i - 20]] if i >= 20 else None
    out = 1.0 if back and (S / back - 1) >= 0.15 else 0.6
    earn = any(sale < x <= e for x in EARN_REACT)
    share = 0.2 if earn else 1 / 3
    above = sorted(k for k in C if k >= S and C[k] > 0)
    if not above: continue
    ka = above[0]
    ko = min((k for k in C if k > S and C[k] > 0), key=lambda k: abs(k - (S + out * sd)))
    if ko <= ka:
        nxt = [k for k in above if k > ka]; ko = nxt[0] if nxt else ka
    def leg(k):
        mid = C[k]; vv = iv_of(mid, S, k, T) or v
        return mid, bs(S, k, T, vv)[1], max(0.0, Se - k)
    ma, da, pa = leg(ka); mo, do, po = leg(ko)
    # Today's book around the calls, for delta left
    hedge = 25 * 100 * bs(S, S * 1.08, 0.42, v * 0.95, call=False)[1]
    kp = max([k for k in P if k <= S * 0.98] or [min(P)])
    vp = iv_of(P[kp], S, kp, T, call=False) or v
    sput = -13 * 100 * bs(S, kp, T, vp, call=False)[1]
    base = 60 * 100 * 0.75 + hedge + sput + 20 * 100 * 0.30
    arm = {}
    for n in ARMS:
        na = round(n * share); no = n - na
        pnl = na * 100 * (ma - pa) + no * 100 * (mo - po) - 0.65 * n
        dl = (base - 100 * (na * da + no * do)) / 6000 * 100
        arm[n] = (pnl, dl)
    gap = (target_on(sale) / S - 1) * 100
    rows.append(dict(sale=sale, S=S, Se=Se, move=(Se / S - 1) * 100, gap=gap, earn=earn, arm=arm))

def regime(r): return 'far below value (>10%)' if r['gap'] > 10 else 'near value (within 10%)' if r['gap'] >= -10 else 'above value'
print(f"{len(rows)} weeks, {rows[0]['sale']} to {rows[-1]['sale']}")
for lab, sel in [('ALL WEEKS', lambda r: True), ('far below value (>10%)', lambda r: regime(r) == 'far below value (>10%)'),
                 ('near value (within 10%)', lambda r: regime(r) == 'near value (within 10%)'), ('above value', lambda r: regime(r) == 'above value'),
                 ('earnings weeks', lambda r: r['earn'])]:
    rs = [r for r in rows if sel(r)]
    if not rs: continue
    up = sum(1 for r in rs if r['move'] > 0)
    print(f"\n{lab}: {len(rs)} weeks, stock up in {up}, avg weekly move {sum(r['move'] for r in rs) / len(rs):+.1f}%")
    for n in ARMS:
        tot = sum(r['arm'][n][0] for r in rs); lose = sum(1 for r in rs if r['arm'][n][0] < 0)
        worst = min(r['arm'][n][0] for r in rs); dl = sum(r['arm'][n][1] for r in rs) / len(rs)
        print(f"  sell {n:2d} of 60 (delta left ~{dl:4.0f}%): calls P&L ${tot:>9,.0f}  losing weeks {lose:2d}  worst week ${worst:>8,.0f}")
json.dump(rows, open(os.path.join(DATA, 'nke_target_rows.json'), 'w'), indent=0)
