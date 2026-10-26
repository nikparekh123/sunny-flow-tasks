"""Three-expiry ladder test (Nik, 18 Oct 2026): TSLA (Mon/Wed/Fri expiries since Feb 2026),
SPY, QQQ, IWM (daily expiries; Mon/Wed/Fri used). For every slot day (an expiry day), the
call quotes at the close for the expiry three slots ahead, plus daily closes. Cached in data/.
Usage: python3 fetch.py"""
import json, os, subprocess, urllib.request, datetime as dt
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
D = dt.date.fromisoformat
START = {'TSLA': '2026-02-02', 'SPY': '2024-10-07', 'QQQ': '2024-10-07', 'IWM': '2024-10-07'}
END = '2026-10-16'

def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    err = None
    for _ in range(4):
        try: return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('response', [])
        except Exception as e: err = e
    print('FAIL', path, err); return []

def chain(t, e, day):
    q = {}
    for c in theta(f"/v3/option/history/eod?symbol={t}&expiration={e.replace('-', '')}&right=call"
                   f"&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
        for x in c.get('data', []):
            if (x.get('created') or '')[:10] == day and (x.get('ask') or 0) > 0:
                q[str(float(c['contract']['strike']))] = [x.get('bid') or 0, x['ask']]
    return q

def slots(exps, trading):
    """Mon, Wed and Fri expiries each week; a holiday moves Mon to Tue and Fri to Thu."""
    by = {}
    for e in exps:
        if e in trading: by.setdefault(D(e).isocalendar()[:2], []).append(e)
    out = []
    for wk in sorted(by):
        xs = by[wk]
        for target, alt in ((0, 1), (2, 2), (4, 3)):
            pick = next((e for e in xs if D(e).weekday() == target), None) or next((e for e in xs if D(e).weekday() == alt and target != 2), None)
            if pick and pick not in [o[0] for o in out]: out.append((pick, target))
    return sorted(out)

for t in START:
    path = os.path.join(DATA, f'{t}.json')
    out = json.load(open(path)) if os.path.exists(path) else {}
    if 'closes' not in out:
        bars = []
        for a, b in (('20240901', '20250831'), ('20250901', '20260831'), ('20260901', END.replace('-', ''))):
            bars += theta(f'/v3/stock/history/eod?symbol={t}&start_date={a}&end_date={b}')
        out['closes'] = {x['created'][:10]: x['close'] for x in bars if x.get('close')}
    trading = set(out['closes'])
    exps = sorted(str(x['expiration']) for x in theta(f'/v3/option/list/expirations?symbol={t}'))
    exps = [e if '-' in e else f'{e[:4]}-{e[4:6]}-{e[6:]}' for e in exps]
    S = [s for s in slots([e for e in exps if START[t] <= e <= '2026-10-31'], trading | {e for e in exps if e > END})]
    out['slots'] = S; out['exps'] = exps
    out.setdefault('q', {})
    sl = [s for s, _ in S]
    jobs = []
    for i, d in enumerate(sl):
        if d > END: break
        for j in ((1, 2, 3) if i == 0 else (3,)):
            if i + j < len(sl):
                key = f'{d}|{sl[i + j]}'
                if key not in out['q']: jobs.append((key, d, sl[i + j]))
    with ThreadPoolExecutor(4) as ex:
        for key, q in ex.map(lambda j: (j[0], chain(t, j[2], j[1])), jobs):
            out['q'][key] = q
    json.dump(out, open(path, 'w'))
    print(t, 'closes', len(out['closes']), 'slots', len([s for s in sl if s <= END]), 'quotes', len(out['q']),
          'empty', sum(1 for v in out['q'].values() if not v), flush=True)
