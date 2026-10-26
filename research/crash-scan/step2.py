"""Crash wheel, step 2 (Nik, 18 Oct 2026). Model research, not advice.
For each one-day crash of 15%+ (events_adj.json): on day 2's close sell 10 puts on the nearest expiry at
least 3 days out, 1/2/3% out (highest strike at or below). Each expiry: puts below the strike -> assigned,
own 1,000 shares at the strike, then sell 10 calls (at the money / 1% out / 1% in) on the next expiry; calls
above the strike -> called away, back to puts. Protection variant: also buy 10 puts ~10% below the price on
every expiry sold. New sales stop once the next expiry is more than 28 days after entry; any shares left are
sold at that last expiry's close. Real Theta end-of-day quotes, raw (unadjusted) prices; events with a split
inside the window are skipped. Fills at mid, or sell at the bid / buy at the ask. $0.65 a contract.
P&L as % of the cash securing the first puts (strike x 1,000). Usage: python3 step2.py"""
import json, os, subprocess, urllib.request, itertools, statistics as st, datetime as dt
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat
def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(r, timeout=120).read()).get('response', [])
        except Exception: pass
    return []
CP = os.path.join(DATA, 'chains.json'); CACHE = json.load(open(CP)) if os.path.exists(CP) else {}
def exps(t):
    k = f'x|{t}'
    if k not in CACHE:
        ex = [str(x['expiration']) for x in theta(f'/v3/option/list/expirations?symbol={t}')]
        CACHE[k] = sorted(e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in ex)
    return CACHE[k]
def chain(t, e, day, right):
    k = f'{t}|{e}|{day}|{right}'
    if k not in CACHE:
        q = {}
        for c in theta(f"/v3/option/history/eod?symbol={t}&expiration={e.replace('-', '')}&right={right}&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
            for x in c.get('data', []):
                if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[str(float(c['contract']['strike']))] = [x['bid'], x['ask']]
        CACHE[k] = q
    return {float(a): b for a, b in CACHE[k].items()}
SPLITS = {(t, d) for t, d, _ in json.load(open(os.path.join(DATA, 'splits.json')))}
PUT_OTM = (0.01, 0.02, 0.03); CALL = {'atm': 0.0, '1% out': 0.01, '1% in': -0.01}; PROT = (False, True); FILL = ('mid', 'bid')

def run_event(ev, otm, cmode, prot, fill, fetch=True):
    t = ev['t']; px = json.load(open(os.path.join(DATA, f'px_{t}.json'))); ds = sorted(px)
    i0 = ds.index(ev['day']) + 1
    if i0 >= len(ds): return None
    entry = ds[i0]; ex = [e for e in exps(t) if e >= entry]
    if any(tt == t and entry <= d <= (D(entry) + dt.timedelta(days=40)).isoformat() for tt, d in SPLITS): return None
    close = lambda d: px[max(x for x in ds if x <= d)][1]
    SELL = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    BUY = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    day = entry; shares = False; basis = None; pnl = 0.0; notional = None; legs = []; last = entry
    while True:
        nxt = [e for e in ex if (D(e) - D(day)).days >= 3]
        if not nxt or (D(nxt[0]) - D(entry)).days > 28: break
        e = nxt[0]; S = close(day)
        if e > ds[-1]: break
        right = 'call' if shares else 'put'; q = chain(t, e, day, right)
        if not q: break
        ks = sorted(q)
        if shares:
            tgt = S * (1 + CALL[cmode]); K = min(ks, key=lambda k: abs(k - tgt))
        else:
            below = [k for k in ks if k <= S * (1 - otm)]
            if not below: break
            K = below[-1]
            if notional is None: notional = K * 1000
        pnl += SELL(*q[K]) * 1000 - 6.5
        Kp = None
        if prot:
            qp = q if right == 'put' else chain(t, e, day, 'put')
            lowk = [k for k in sorted(qp) if k <= S * 0.90]
            if lowk: Kp = lowk[-1]; pnl -= BUY(*qp[Kp]) * 1000 + 6.5
        Se = close(e)
        if Kp: pnl += max(0, Kp - Se) * 1000
        if shares:
            if Se > K: pnl += (K - basis) * 1000; shares = False; legs.append(f'{e} called at {K:g}')
            else: legs.append(f'{e} calls {K:g} expired')
        else:
            if Se < K: shares = True; basis = K; legs.append(f'{e} assigned at {K:g}')
            else: legs.append(f'{e} puts {K:g} expired')
        day = e; last = e
    if notional is None: return None
    if shares: pnl += (close(last) - basis) * 1000; legs.append(f'sold shares {close(last):.2f}')
    return dict(t=t, day=ev['day'], entry=entry, pnl=pnl, pct=pnl / notional * 100, notional=notional, legs=legs)

if __name__ == '__main__':
    E = json.load(open(os.path.join(DATA, 'events_adj.json')))
    # fetch every chain a variant can touch, in parallel per event (the mid / 2% / atm / no-protection path plus variants)
    def prefetch(ev):
        out = []
        for otm, cm, pr in itertools.product(PUT_OTM, CALL, PROT): out.append(run_event(ev, otm, cm, pr, 'mid'))
        return out
    with ThreadPoolExecutor(6) as ex: list(ex.map(prefetch, E))
    json.dump(CACHE, open(CP, 'w'))
    res = {}
    for otm, cm, pr, fl in itertools.product(PUT_OTM, CALL, PROT, FILL):
        rs = [r for r in (run_event(ev, otm, cm, pr, fl) for ev in E) if r]
        ps = [r['pct'] for r in rs]
        res[f'{int(otm*100)}%|{cm}|{"prot" if pr else "none"}|{fl}'] = dict(n=len(rs), avg=st.mean(ps), med=st.median(ps), win=sum(1 for p in ps if p > 0) / len(ps) * 100,
            worst=min(ps), p10=sorted(ps)[len(ps) // 10], dollars=sum(r['pnl'] for r in rs), events=[(r['t'], r['day'], round(r['pct'], 2)) for r in rs])
    json.dump(res, open(os.path.join(DATA, 'step2.json'), 'w'), indent=1)
    for k, v in sorted(res.items(), key=lambda kv: -kv[1]['avg']):
        print(f"{k:26s} events {v['n']:3d} avg {v['avg']:+5.2f}% median {v['med']:+5.2f}% win {v['win']:4.0f}% bad1in10 {v['p10']:+6.2f}% worst {v['worst']:+6.2f}% total ${v['dollars']/1000:,.0f}K")
