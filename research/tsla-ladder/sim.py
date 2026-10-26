"""Three-expiry ladder (Nik, 18 Oct 2026). Model research, not advice.
1,000 shares. On every Mon/Wed/Fri expiry day, at the close, the expiring 10 calls settle
(assigned shares are bought back at that close, $0.005 a share) and 10 new calls are sold on
the expiry three slots ahead (about a week out): Monday slots 0.25 SD IN the money, Wednesday
slots 0.25 SD out, Friday slots 0.5 SD out (TSLA at $350: about $343, $357, $363). 30 calls
on 1,000 shares, so 20 are uncovered: long calls bring net delta to +1,000 at the start and
are topped back to +1,000 whenever net delta falls under +500 (Nik: add calls after a big
drop); rolled when 60 days (6-month) or 7 days (1-month) are left. Real Theta EOD quotes;
fills at mid, or 'worse' = sell at the bid, buy at the ask; $0.65 a contract.
Usage: python3 sim.py"""
import json, math, os, subprocess, urllib.request, datetime as dt
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat; END = '2026-10-16'
TICKERS = os.environ.get('TICKERS', 'TSLA,SPY,QQQ,IWM').split(',')
ZK = {0: -0.25, 1: -0.25, 2: 0.25, 3: 0.5, 4: 0.5}          # slot weekday -> SD from the price
LONG = {'6m': (182, 1.00, 60), '1m': (30, 1.05, 7), '1matm': (30, 1.00, 7)}   # days out, strike / price, roll at days left

def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(4):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception: pass
    return []
def ncdf(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))
def bs(S, K, T, v, r=0.04):
    T = max(T, 1e-4); sq = v * math.sqrt(T); d1 = (math.log(S / K) + (r + v * v / 2) * T) / sq
    return S * ncdf(d1) - K * math.exp(-r * T) * ncdf(d1 - sq), ncdf(d1)
def iv_of(px, S, K, T):
    if not px > max(0, S - K * math.exp(-0.04 * T)) + 1e-3: return None
    lo, hi = 0.01, 5.0
    for _ in range(60):
        m = (lo + hi) / 2
        if bs(S, K, T, m)[0] < px: lo = m
        else: hi = m
    return (lo + hi) / 2
yrs = lambda a, b: max(1, (D(b) - D(a)).days) / 365

class Longs:
    """Long-call quotes, fetched per contract over its life and cached."""
    def __init__(s, t):
        s.t = t; s.path = os.path.join(DATA, f'longs_{t}.json')
        s.c = json.load(open(s.path)) if os.path.exists(s.path) else {}
    def save(s): json.dump(s.c, open(s.path, 'w'))
    def chain(s, e, day):
        k = f'chain|{e}|{day}'
        if k not in s.c:
            q = {}
            for c in theta(f"/v3/option/history/eod?symbol={s.t}&expiration={e.replace('-', '')}&right=call&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
                for x in c.get('data', []):
                    if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[str(float(c['contract']['strike']))] = [x['bid'], x['ask']]
            s.c[k] = q
        return {float(k): v for k, v in s.c[k].items()}
    def hist(s, e, K, a):
        k = f'hist|{e}|{K}|{a}'
        if k not in s.c:
            b = min(e, END); q = {}
            for c in theta(f"/v3/option/history/eod?symbol={s.t}&expiration={e.replace('-', '')}&right=call&strike={K}&start_date={a.replace('-', '')}&end_date={b.replace('-', '')}"):
                for x in c.get('data', []):
                    if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[x['created'][:10]] = [x['bid'], x['ask']]
            s.c[k] = q
        return s.c[k]

def run(t, mode, fill):
    d = json.load(open(os.path.join(DATA, f'{t}.json'))); C = d['closes']; days = sorted(C)
    slots = [(s, w) for s, w in d['slots']]; sl = [s for s, _ in slots]; wd = dict(slots)
    exps = d['exps']; L = Longs(t)
    sell_px = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    buy_px = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    cash = 0.0; shorts = {}; longs = []; eq = []; deltas = []; spend = 0.0; buys = 0; assigned = 0
    sh_prem = sh_settle = 0.0; S0 = None
    for i, day in enumerate(sl):
        if day > END: break
        S = C[day]
        if S0 is None: S0 = S; cash -= 1000 * S
        if day in shorts:                                           # the expiring 10
            K = shorts.pop(day)['K']; x = max(0, S - K) * 1000
            cash -= x; sh_settle += x
            if S > K: cash -= 5; assigned += 1
        for lg in [g for g in longs if (D(g['e']) - D(day)).days <= g['roll']]:   # roll
            q = L.hist(lg['e'], lg['K'], lg['d']).get(day)
            px = sell_px(*q) if q else max(0, S - lg['K'])
            cash += px * 100 * lg['n'] - 0.65 * lg['n']; longs.remove(lg)
        for j in ((1, 2, 3) if i == 0 else (3,)):                   # sell
            if i + j >= len(sl): continue
            e = sl[i + j]; q = {float(k): v for k, v in d['q'].get(f'{day}|{e}', {}).items() if v[0] > 0}
            if not q: continue
            T = yrs(day, e); ks = sorted(q); ka = min(ks, key=lambda k: abs(k - S))
            iv = iv_of(sum(q[ka]) / 2, S, ka, T) or 0.3; sd = S * iv * math.sqrt(T); z = ZK[wd[e]]
            K = min(ks, key=lambda k: abs(k - (S + z * sd)))
            if z < 0 and K >= S: K = max([k for k in ks if k < S], default=K)
            if z > 0 and K <= S: K = min([k for k in ks if k > S], default=K)
            p = sell_px(*q[K]); cash += p * 1000 - 6.5; sh_prem += p * 1000
            shorts[e] = dict(K=K, iv=iv_of(sum(q[K]) / 2, S, K, T) or iv)
        def net_delta():
            n = 1000.0
            for e, s in shorts.items(): n -= 1000 * bs(S, s['K'], yrs(day, e), s['iv'])[1]
            for g in longs:
                q = L.hist(g['e'], g['K'], g['d']).get(day); T = yrs(day, g['e'])
                v = iv_of(sum(q) / 2, S, g['K'], T) if q else None
                n += g['n'] * 100 * bs(S, g['K'], T, v or g['iv'])[1]
            return n
        nd = net_delta()
        if mode != 'none' and (nd < 500 or i == 0):                 # top up to +1,000
            tgt, kx, rl = LONG[mode]
            # Today's listing holds expiries that did not trade yet on `day`: take the
            # nearest one that had quotes that day.
            cand = sorted([e for e in exps if (D(e) - D(day)).days >= tgt * 0.75], key=lambda x: abs((D(x) - D(day)).days - tgt))
            e, ch = None, {}
            for e in cand[:6]:
                ch = L.chain(e, day)
                if ch: break
            if ch:
                K = min(ch, key=lambda k: abs(k - S * kx))
                T = yrs(day, e); v = iv_of(sum(ch[K]) / 2, S, K, T) or 0.4; dl = bs(S, K, T, v)[1]
                n = math.ceil((1000 - nd) / (100 * dl))
                if n > 0:
                    px = buy_px(*ch[K]); cash -= px * 100 * n + 0.65 * n; spend += px * 100 * n; buys += 1
                    longs.append(dict(e=e, K=K, n=n, d=day, iv=v, roll=rl))
                    nd = net_delta()
        deltas.append(nd)
        lv = 0.0
        for g in longs:
            q = L.hist(g['e'], g['K'], g['d']).get(day)
            lv += (sum(q) / 2 if q else max(0, S - g['K'])) * 100 * g['n']
        sv = sum(1000 * bs(S, s['K'], yrs(day, e), s['iv'])[0] for e, s in shorts.items())
        eq.append((day, cash + 1000 * S + lv - sv))
        last = day
    L.save()
    tot = eq[-1][1]; peak = -1e18; mdd = 0
    for _, v in eq: peak = max(peak, v); mdd = min(mdd, v - peak)
    years = yrs(sl[0], last)
    return dict(t=t, mode=mode, fill=fill, start=sl[0], end=last, S0=S0, S1=C[last], total=tot, pct_yr=tot / years / (1000 * S0) * 100,
                shares=(C[last] - S0) * 1000, shorts_net=sh_prem - sh_settle, long_spend=spend, buys=buys, mdd=mdd,
                mdd_pct=mdd / (1000 * S0) * 100, short_days=sum(1 for x in deltas if x < 0) / len(deltas) * 100,
                min_delta=min(deltas), assigned=assigned, slots=len(eq))

if __name__ == '__main__':
    res = []
    for t in TICKERS:
        for mode in os.environ.get('MODES', 'none,6m,1m,1matm').split(','):
            for fill in ('mid', 'worse'):
                r = run(t, mode, fill); res.append(r)
                print(f"{t:4s} {mode:4s} {fill:5s} {r['start']}..{r['end']} total ${r['total']:>10,.0f} {r['pct_yr']:6.1f}%/yr shares ${r['shares']:>9,.0f} "
                      f"shorts ${r['shorts_net']:>9,.0f} longs spent ${r['long_spend']:>9,.0f} ({r['buys']} buys) maxDD {r['mdd_pct']:6.1f}% "
                      f"net short {r['short_days']:4.1f}% of days, min delta {r['min_delta']:6.0f}", flush=True)
    json.dump(res, open(os.path.join(DATA, f"results_{'_'.join(TICKERS)}_{os.environ.get('MODES', 'all').replace(',', '_')}.json"), 'w'), indent=1)
