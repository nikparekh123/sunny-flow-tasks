"""TWO-WEEK expiry quotes (the Friday after next) for the ladder test. Study 1 (Nik, 17 Oct 2026): each stock's own delta target, NKE only.
Fetch, for every Friday sale from Oct 2025 to Oct 2026, the next weekly expiry's
call AND put quotes at that day's close (Theta end-of-day), cached per sale date.
Usage: python3 -I fetch_weeklies.py   (run from research/target-study)"""
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

bars = []
for f in ('nke_a.json', 'nke_b.json'): bars += json.load(open(os.path.join(DATA, f)))['response']
days = sorted({b['created'][:10] for b in bars if b.get('close')})
exps = sorted(str(x['expiration']) for x in theta('/v3/option/list/expirations?symbol=NKE'))
exps = [e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps]
# Sale day: the last session of each week; expiry: the first listed expiry in the following week.
weeks = {}
for d in days:
    if '2025-10-10' <= d <= '2026-10-09':
        y, w, _ = D(d).isocalendar(); weeks[(y, w)] = d
out = {}
path = os.path.join(DATA, 'nke_2wk.json')
if os.path.exists(path): out = json.load(open(path))
for sale in sorted(weeks.values()):
    if sale in out: continue
    nxt = [e for e in exps if D(sale) + dt.timedelta(days=10) <= D(e) <= D(sale) + dt.timedelta(days=16)]
    if not nxt: print('no expiry after', sale); continue
    e = nxt[0]; q = {'expiry': e, 'C': {}, 'P': {}}
    for right in ('call', 'put'):
        for c in theta(f"/v3/option/history/eod?symbol=NKE&expiration={e.replace('-', '')}&right={right}"
                       f"&start_date={sale.replace('-', '')}&end_date={sale.replace('-', '')}"):
            k = float(c['contract']['strike'])
            for x in c['data']:
                if (x.get('created') or '')[:10] == sale and (x.get('ask') or 0) > 0:
                    q['C' if right == 'call' else 'P'][str(k)] = [x.get('bid') or 0, x['ask']]
    out[sale] = q
    print(sale, '->', e, len(q['C']), 'calls', len(q['P']), 'puts', flush=True)
    json.dump(out, open(path, 'w'))
print('weeks', len(out))
