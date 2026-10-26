"""~30-day ATM IV for NKE from Theta end-of-day quotes, the same method as
ticker-iv-snapshot (expiry nearest 30 days within 14, spot from put-call parity,
call nearest spot, IV from the mid, r = 4%), for days we have no stored IV.
Writes data/nke_iv_old.json {date: iv}. Usage: python3 -I iv_local.py 2024-10-01 2025-10-15"""
import json, math, os, subprocess, sys, urllib.request, datetime as dt
from collections import defaultdict
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
FROM, TO = sys.argv[1], sys.argv[2]
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat
def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception as e: err = e
    print('FAIL', path, err); return []
def ncdf(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))
def bs_call(S, K, T, v, r=0.04):
    sq = v * math.sqrt(T); d1 = (math.log(S / K) + (r + v * v / 2) * T) / sq
    return S * ncdf(d1) - K * math.exp(-r * T) * ncdf(d1 - sq)
def iv_call(mid, S, K, T):
    if not mid > max(0, S - K * math.exp(-0.04 * T)) + 0.005: return None
    lo, hi = 0.01, 4.0
    for _ in range(60):
        m = (lo + hi) / 2
        if bs_call(S, K, T, m) < mid: lo = m
        else: hi = m
    return (lo + hi) / 2
bars = []
for f in ('nke_0.json', 'nke_a.json'): bars += json.load(open(os.path.join(DATA, f)))['response']
days = sorted({b['created'][:10] for b in bars if b.get('close') and FROM <= b['created'][:10] <= TO})
exps = [str(x['expiration']) for x in theta('/v3/option/list/expirations?symbol=NKE')]
exps = sorted(e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps)
by_exp = defaultdict(list)
for d in days:
    win = [e for e in exps if abs((D(e) - D(d)).days - 30) <= 14]
    if win: by_exp[min(win, key=lambda e: abs((D(e) - D(d)).days - 30))].append(d)
out = {}
for e, ds in sorted(by_exp.items()):
    q = {}
    for right in ('call', 'put'):
        for c in theta(f"/v3/option/history/eod?symbol=NKE&expiration={e.replace('-', '')}&right={right}"
                       f"&start_date={min(ds).replace('-', '')}&end_date={max(ds).replace('-', '')}"):
            k = float(c['contract']['strike'])
            for x in c['data']:
                day = (x.get('created') or '')[:10]; b, a = x.get('bid') or 0, x.get('ask') or 0
                if day in ds and b > 0 and a > 0: q.setdefault(day, {}).setdefault(k, {})[right[0]] = (b + a) / 2
    for d in ds:
        ch = q.get(d, {}); T = max(1, (D(e) - D(d)).days) / 365
        pairs = [(k, v) for k, v in ch.items() if 'c' in v and 'p' in v]
        if not pairs: continue
        k0, v0 = min(pairs, key=lambda kv: abs(kv[1]['c'] - kv[1]['p']))
        S = v0['c'] - v0['p'] + k0 * math.exp(-0.04 * T)
        calls = sorted(((k, v['c']) for k, v in ch.items() if 'c' in v), key=lambda kv: abs(kv[0] - S))
        if calls:
            v = iv_call(calls[0][1], S, calls[0][0], T)
            if v: out[d] = round(v, 5)
    print(e, len(ds), flush=True)
json.dump(out, open(os.path.join(DATA, 'nke_iv_old.json'), 'w'))
print(len(out), 'days')
