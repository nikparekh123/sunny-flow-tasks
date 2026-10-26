"""QUARTERLY expiry quotes for the diagonal test (Nik, 19 Oct 2026: the long goes to the quarterly, 1 or 1.5 SD).
From the monthly version: MONTHLY expiry quotes for the diagonal test (Nik, 19 Oct 2026): sell the weekly at the money, buy a
monthly ~4 weeks out at 0.6 / 0.8 / 1 SD, hold it to expiry, then buy the next monthly that Friday.
Fetches, for each roll Friday from Oct 2025 to Oct 2026, the call quotes of the next monthly expiry at
least 3 weeks out, at that day's close (Theta end-of-day). Run from research/target-study:
python3 -I fetch_monthly.py"""
import json, os, subprocess, urllib.request, datetime as dt

HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat

def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception as e: err = e
    print('FAIL', path, err); return []

sales = sorted(json.load(open(os.path.join(DATA, 'nke_weeklies.json'))))
exps = sorted(str(x['expiration']) for x in theta('/v3/option/list/expirations?symbol=NKE'))
exps = [e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps]
def third_friday(y, m):
    d = dt.date(y, m, 15)
    while d.weekday() != 4: d += dt.timedelta(days=1)
    return d
# monthly = the listed expiry on the third Friday (or the session before it on a holiday)
monthly = []
for e in exps:
    d = D(e); tf = third_friday(d.year, d.month)
    if d.month in (1, 4, 7, 10) and (d == tf or (tf - d).days == 1): monthly.append(e)
monthly = sorted(set(monthly))
path = os.path.join(DATA, 'nke_quarterly.json'); out = json.load(open(path)) if os.path.exists(path) else {}
buy = sales[0]
while True:
    nxt = [m for m in monthly if (D(m) - D(buy)).days >= 56]
    if not nxt or nxt[0] > '2026-10-16': break
    m = nxt[0]
    if buy not in out:
        q = {'expiry': m, 'C': {}}
        for c in theta(f"/v3/option/history/eod?symbol=NKE&expiration={m.replace('-', '')}&right=call"
                       f"&start_date={buy.replace('-', '')}&end_date={buy.replace('-', '')}"):
            k = float(c['contract']['strike'])
            for x in c['data']:
                if (x.get('created') or '')[:10] == buy and (x.get('ask') or 0) > 0:
                    q['C'][str(k)] = [x.get('bid') or 0, x['ask']]
        out[buy] = q
        json.dump(out, open(path, 'w'))
    print(buy, '->', m, len(out[buy]['C']), 'calls', flush=True)
    # the next purchase is the Friday this monthly expires (or the last sale day on or before it)
    roll = [s for s in sales if s <= m]
    if not roll or roll[-1] == buy: break
    buy = roll[-1]
print('rolls', len(out))
