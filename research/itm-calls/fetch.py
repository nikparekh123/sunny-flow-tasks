"""ITM + OTM ladder test (Nik, 18 Oct 2026): TSLA, COIN, HOOD, URA.
Fetch, for every Friday sale from Oct 2024 to Oct 2026, the call quotes at that day's
close (Theta end-of-day) for the next weekly expiry (1 week) and the one after (2 weeks),
plus daily stock closes. Cached per ticker in data/. Usage: python3 fetch.py"""
import json, os, subprocess, urllib.request, datetime as dt
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat
TICKERS = ['TSLA', 'COIN', 'HOOD', 'URA']
FROM, TO = '2024-10-01', '2026-10-17'

def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    err = None
    for _ in range(4):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception as e: err = e
    print('FAIL', path, err); return []

def calls(t, e, day):
    q = {}
    for c in theta(f"/v3/option/history/eod?symbol={t}&expiration={e.replace('-', '')}&right=call"
                   f"&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
        for x in c.get('data', []):
            if (x.get('created') or '')[:10] == day and (x.get('ask') or 0) > 0:
                q[str(float(c['contract']['strike']))] = [x.get('bid') or 0, x['ask']]
    return q

for t in TICKERS:
    path = os.path.join(DATA, f'{t}.json')
    out = json.load(open(path)) if os.path.exists(path) else {}
    if 'closes' not in out:
        bars = []
        for a, b in (('20241001', '20250930'), ('20251001', '20260930'), ('20261001', TO.replace('-', ''))):  # 365-day cap per request
            bars += theta(f'/v3/stock/history/eod?symbol={t}&start_date={a}&end_date={b}')
        out['closes'] = {x['created'][:10]: x['close'] for x in bars if x.get('close')}
    days = sorted(out['closes'])
    exps = sorted(str(x['expiration']) for x in theta(f'/v3/option/list/expirations?symbol={t}'))
    exps = [e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps]
    weeks = {}
    for d in days:
        if '2024-10-04' <= d <= '2026-10-09':
            y, w, _ = D(d).isocalendar(); weeks[(y, w)] = d
    out.setdefault('sales', {})
    for s_ in [s_ for s_ in out['sales'] if s_ not in set(weeks.values())]: del out['sales'][s_]   # a stale week from a shorter run
    jobs = []
    def weekly(sale, k):
        """The Friday expiry k weeks after the sale's week (that week's last listed
        expiry up to Friday, so a holiday Thursday counts; TSLA's Monday and
        Wednesday expiries do not)."""
        mon = D(sale) - dt.timedelta(days=D(sale).weekday()) + dt.timedelta(days=7 * k)
        xs = [e for e in exps if mon <= D(e) <= mon + dt.timedelta(days=4)]
        return xs[-1] if xs else None
    for sale in sorted(weeks.values()):
        e1, e2 = weekly(sale, 1), weekly(sale, 2)
        have = out['sales'].get(sale)
        if have and have['e1'] == e1 and have['e2'] == e2: continue
        jobs.append((sale, e1, e2))
    def run(j):
        sale, e1, e2 = j
        return sale, {'e1': e1, 'c1': calls(t, e1, sale) if e1 else {}, 'e2': e2, 'c2': calls(t, e2, sale) if e2 else {}}
    with ThreadPoolExecutor(4) as ex:
        for sale, v in ex.map(run, jobs):
            out['sales'][sale] = v
    json.dump(out, open(path, 'w'))
    print(t, 'closes', len(out['closes']), 'sales', len(out['sales']),
          'missing 1wk', sum(1 for v in out['sales'].values() if not v['c1']), 'missing 2wk', sum(1 for v in out['sales'].values() if not v['c2']), flush=True)
