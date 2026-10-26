"""Quarterly-diagonal test on the other six names (Nik, 19 Oct 2026). For BABA FIS LULU NFLX PEP UBER fetch
(Theta end-of-day, NOT split-adjusted): daily closes Oct 2023 to Oct 2026; for every Friday sale Oct 2025 to Oct 2026
the next weekly expiry's call quotes; the quarterly (Jan/Apr/Jul/Oct) call quotes on each roll date.
Run from research/target-study: python3 -I fetch_six.py"""
import json, os, subprocess, urllib.request, datetime as dt, sys
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data', 'six'); os.makedirs(DATA, exist_ok=True)
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat
def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception as e: err = e
    print('FAIL', path, err, flush=True); return []
sales = sorted(json.load(open(os.path.join(HERE, 'data', 'nke_weeklies.json'))))
def chain(t, e, day):
    out = {}
    for c in theta(f"/v3/option/history/eod?symbol={t}&expiration={e.replace('-', '')}&right=call&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
        k = float(c['contract']['strike'])
        for x in c['data']:
            if (x.get('created') or '')[:10] == day and (x.get('ask') or 0) > 0: out[str(k)] = [x.get('bid') or 0, x['ask']]
    return out
def third_friday(y, m):
    d = dt.date(y, m, 15)
    while d.weekday() != 4: d += dt.timedelta(days=1)
    return d
for t in sys.argv[1:] or ['BABA', 'FIS', 'LULU', 'NFLX', 'PEP', 'UBER']:
    path = os.path.join(DATA, f'{t}.json'); out = json.load(open(path)) if os.path.exists(path) else {'closes': {}, 'weekly': {}, 'quarterly': {}}
    if not out['closes']:
        for a, b in (('20231016', '20241015'), ('20241016', '20251015'), ('20251016', '20261016')):
            for x in theta(f'/v3/stock/history/eod?symbol={t}&start_date={a}&end_date={b}'):
                if x.get('close'): out['closes'][x['created'][:10]] = x['close']
        json.dump(out, open(path, 'w'))
    exps = sorted(str(x['expiration']) for x in theta(f'/v3/option/list/expirations?symbol={t}'))
    exps = [e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps]
    for s in sales:
        if s in out['weekly']: continue
        nxt = [e for e in exps if 4 <= (D(e) - D(s)).days <= 9]
        out['weekly'][s] = {'expiry': nxt[0], 'C': chain(t, nxt[0], s)} if nxt else {'expiry': None, 'C': {}}
        json.dump(out, open(path, 'w'))
    q = sorted(e for e in exps if D(e).month in (1, 4, 7, 10) and abs((third_friday(D(e).year, D(e).month) - D(e)).days) <= 1)
    buy = sales[0]
    while True:
        nx = [m for m in q if (D(m) - D(buy)).days >= 56]
        if not nx or nx[0] > '2026-10-16': break
        m = nx[0]
        if buy not in out['quarterly']:
            out['quarterly'][buy] = {'expiry': m, 'C': chain(t, m, buy)}; json.dump(out, open(path, 'w'))
        roll = [s for s in sales if s <= m]
        if not roll or roll[-1] == buy: break
        buy = roll[-1]
    nw = sum(1 for v in out['weekly'].values() if v['C'])
    print(t, 'closes', len(out['closes']), '| weeks with quotes', nw, 'of', len(sales), '| quarterly rolls', {k: v['expiry'] for k, v in out['quarterly'].items()}, flush=True)
