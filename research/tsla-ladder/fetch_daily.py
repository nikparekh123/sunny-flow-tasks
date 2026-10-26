"""Daily-expiry ladder data (Nik, 18 Oct 2026): SPY, QQQ, IWM. Every trading day is an expiry
day: at each close the set expiring that day settles and a set is sold on the expiry three
trading days ahead. Fetches that chain for every day (and the first three at the start).
Writes data/{T}_daily.json in the same shape as {T}.json. Usage: python3 fetch_daily.py"""
import json, os
from concurrent.futures import ThreadPoolExecutor
from fetch import theta, chain, DATA
START, END = '2024-10-07', '2026-10-16'
for t in ['SPY', 'QQQ', 'IWM']:
    base = json.load(open(os.path.join(DATA, f'{t}.json')))
    path = os.path.join(DATA, f'{t}_daily.json')
    out = json.load(open(path)) if os.path.exists(path) else {'closes': base['closes'], 'exps': base['exps'], 'q': {}}
    trading = set(out['closes'])
    sl = [e for e in out['exps'] if START <= e <= '2026-10-23' and (e in trading or e > END)]
    out['slots'] = [(e, 0) for e in sl]
    jobs = []
    for i, d in enumerate(sl):
        if d > END: break
        for j in ((1, 2, 3) if i == 0 else (3,)):
            if i + j < len(sl) and f'{d}|{sl[i + j]}' not in out['q']: jobs.append((d, sl[i + j]))
    with ThreadPoolExecutor(4) as ex:
        for (d, e), q in zip(jobs, ex.map(lambda j: chain(t, j[1], j[0]), jobs)):
            out['q'][f'{d}|{e}'] = q
    json.dump(out, open(path, 'w'))
    print(t, 'expiry days', len([s for s in sl if s <= END]), 'chains', len(out['q']), 'empty', sum(1 for v in out['q'].values() if not v), flush=True)
