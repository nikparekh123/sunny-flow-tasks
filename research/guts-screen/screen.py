# Guts / weekly short-vol screen over the crash-scan universe (22 Oct 2026).
# Per name: next-Friday (Oct 30) ATM IV and spread, Jan 2028 ATM IV, realised vol from our closes
# (60 days without its biggest day, a year without its 4 biggest: a stand-in for earnings gaps),
# jump stats and the next earnings date. Read-only: Theta proxy snapshots + local files.
import json, math, os, subprocess, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = '/Users/niketparekh/Library/Mobile Documents/com~apple~CloudDocs/Claude/sunny-flow-tasks/research/crash-scan'
OUT = os.path.dirname(os.path.abspath(__file__))
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
WEEK = '2026-10-30'
EXTRA = ['ASML', 'ARM', 'AZN', 'CCEP', 'GFS', 'MELI', 'MDB', 'PDD', 'TEAM', 'ZS', 'DDOG', 'BABA', 'CRWV', 'TTD', 'BIIB', 'ON', 'LULU', 'SMCI']
uni = sorted(set(json.load(open(os.path.join(ROOT, 'data', 'universe.json')))) | set(EXTRA))
earn = {r['ticker']: r['nxt'] for r in json.load(open(os.path.join(OUT, 'earn.json')))}

def theta(path):
    req = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(req, timeout=90).read()).get('response', [])
        except Exception: pass
    return []

def atm(rows):
    """ATM IV (call and put at the strike nearest the price), the call's spread, the straddle as % of price."""
    by = {}
    px = None
    for r in rows:
        c, d = r.get('contract', {}), (r.get('data') or [{}])[-1]
        px = d.get('underlying_price') or px
        iv, b, a = d.get('implied_vol'), d.get('bid') or 0, d.get('ask') or 0
        if not iv or b <= 0 or a <= 0 or not (0.03 < iv < 4) or abs(d.get('iv_error') or 0) > 0.05: continue
        by.setdefault(float(c['strike']), {})[c['right']] = (iv, b, a)
    if not px or not by: return None
    k = min(by, key=lambda s: abs(s - px))
    legs = by[k]
    ivs = [v[0] for v in legs.values()]
    call = legs.get('CALL') or next(iter(legs.values()))
    mid = (call[1] + call[2]) / 2
    strad = sum((v[1] + v[2]) / 2 for v in legs.values()) * (2 / len(legs))
    return {'px': px, 'k': k, 'iv': sum(ivs) / len(ivs), 'spread': (call[2] - call[1]) / mid if mid else None, 'strad': strad / px}

def hv(xs):
    if len(xs) < 10: return None
    m = sum(xs) / len(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1)) * math.sqrt(252)

def one(t):
    p = os.path.join(ROOT, 'data', f'px_{t}.json')
    if not os.path.exists(p): return None
    d = json.load(open(p)); ks = sorted(d)
    c = [float(d[k][1]) for k in ks if k >= '2025-10-01']
    if len(c) < 120: return None
    r = [math.log(c[i] / c[i - 1]) for i in range(1, len(c))]
    y = r[-250:]
    exps = {x['expiration'] for x in theta(f'/v3/option/list/expirations?symbol={t}')}
    if WEEK not in exps: return {'t': t, 'skip': 'no Oct 30 weekly'}
    longs = sorted(e for e in exps if e >= '2027-12-01')
    leap = '2028-01-21' if '2028-01-21' in exps else (longs[0] if longs else None)
    w = atm(theta(f'/v3/option/snapshot/greeks/implied_volatility?symbol={t}&expiration={WEEK.replace("-", "")}'))
    l = atm(theta(f'/v3/option/snapshot/greeks/implied_volatility?symbol={t}&expiration={leap.replace("-", "")}')) if leap else None
    if not w: return {'t': t, 'skip': 'no weekly quotes'}
    s60 = sorted(r[-60:], key=abs)[:-1]; s250 = sorted(y, key=abs)[:-4]
    return {'t': t, 'px': w['px'], 'wiv': w['iv'], 'spread': w['spread'], 'strad': w['strad'],
            'liv': l['iv'] if l else None, 'leap': leap,
            'hv20': hv(r[-20:]), 'hv60x': hv(s60), 'hv250x': hv(s250), 'hv250': hv(y),
            'maxday': max(abs(x) for x in y), 'days10': sum(1 for x in y if abs(x) > 0.10), 'earn': earn.get(t)}

with ThreadPoolExecutor(6) as ex:
    res = [x for x in ex.map(one, uni) if x]
json.dump(res, open(os.path.join(OUT, 'screen.json'), 'w'))
print('names', len(uni), 'rows', len(res), 'with weekly', sum(1 for x in res if 'skip' not in x))
