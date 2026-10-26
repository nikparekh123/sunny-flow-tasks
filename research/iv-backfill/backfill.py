"""A year of ~30-day ATM IV for every held name (Nik, 19 Oct 2026: extend the reads to all names),
the same method as research/target-study/iv_local.py and ticker-iv-snapshot: expiry nearest 30 days
(within 14), spot from put-call parity where call and put are closest, IV of the call nearest that spot
from its mid, r = 4%. Theta end-of-day quotes, 16 Oct 2025 to the day before each name's first stored
row. Writes data/iv_<T>.json {date: [iv, contract]}. Usage: python3 backfill.py AIG BABA ..."""
import json, math, os, subprocess, sys, urllib.request, datetime as dt
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data'); os.makedirs(DATA, exist_ok=True)
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat
FIRST = json.loads(sys.argv[1]) if sys.argv[1].startswith('{') else {}
def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception: pass
    return []
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
def run(t, last):
    days = set()
    for a, b in (('20251016', '20260930'), ('20261001', '20261016')):
        for x in theta(f'/v3/stock/history/eod?symbol={t}&start_date={a}&end_date={b}'):
            if x.get('close'): days.add(x['created'][:10])
    days = sorted(d for d in days if d < last)
    exps = sorted(str(x['expiration']) for x in theta(f'/v3/option/list/expirations?symbol={t}'))
    exps = [e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps]
    by = defaultdict(list)
    for d in days:
        win = [e for e in exps if abs((D(e) - D(d)).days - 30) <= 14]
        if win: by[min(win, key=lambda e: abs((D(e) - D(d)).days - 30))].append(d)
    out = {}
    for e, ds in sorted(by.items()):
        q = {}
        for right in ('call', 'put'):
            for c in theta(f"/v3/option/history/eod?symbol={t}&expiration={e.replace('-', '')}&right={right}&start_date={min(ds).replace('-', '')}&end_date={max(ds).replace('-', '')}"):
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
                if v and 0.03 < v < 3: out[d] = [round(v, 5), f'theta-eod {t} {e} {calls[0][0]:g}C']
    json.dump(out, open(os.path.join(DATA, f'iv_{t}.json'), 'w'))
    return t, len(days), len(out)
if __name__ == '__main__':
    with ThreadPoolExecutor(4) as ex:
        for t, n, k in ex.map(lambda kv: run(*kv), FIRST.items()): print(t, 'days', n, 'iv rows', k, flush=True)
