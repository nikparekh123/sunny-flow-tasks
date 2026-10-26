"""One-day crash scan (Nik, 18 Oct 2026). Model research, not advice.
Universe: S&P 500 (Wikipedia, today's members) + the Nasdaq-100 names outside it + BABA, CRWV, MDB.
Today's members only, so stocks that crashed and left the index are missing (survivorship bias).
Daily closes from Theta (2024-01-02 to 2026-10-16). Event: a close-to-close fall of 15% or more.
For each event: the move from that close to the close 1, 5, 10 and 20 sessions later, the lowest close
within 5 and 20 sessions, and the same from the next day's and the third day's close (entry timing).
Usage: python3 scan.py"""
import json, os, subprocess, urllib.request, statistics as st
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
TK = subprocess.run(['security', 'find-generic-password', '-s', 'theta_proxy_key', '-w'], capture_output=True, text=True).stdout.strip()
EXTRA = ['ASML', 'ARM', 'AZN', 'CCEP', 'GFS', 'MELI', 'MDB', 'PDD', 'TEAM', 'ZS', 'DDOG', 'BABA', 'CRWV', 'TTD', 'BIIB', 'ON', 'LULU']
def theta(path):
    r = urllib.request.Request('https://sunnyfi-theta.fly.dev' + path + '&format=json', headers={'x-proxy-key': TK})
    for _ in range(3):
        try: return json.loads(urllib.request.urlopen(r, timeout=120).read()).get('response', [])
        except Exception as e: err = str(e)
    return []
def closes(t):
    p = os.path.join(DATA, f'px_{t}.json')
    if os.path.exists(p): return t, json.load(open(p))
    out = {}
    for a, b in (('20240102', '20241231'), ('20250101', '20251231'), ('20260101', '20261016')):
        for x in theta(f'/v3/stock/history/eod?symbol={t}&start_date={a}&end_date={b}'):
            if x.get('close') and x.get('open'): out[x['created'][:10]] = (x['open'], x['close'])
    json.dump(out, open(p, 'w')); return t, out
uni = sorted(set(json.load(open(os.path.join(DATA, 'universe.json')))) | set(EXTRA))
with ThreadPoolExecutor(6) as ex: PX = dict(ex.map(closes, uni))
events = []
for t, px in PX.items():
    ds = sorted(px)
    for i in range(1, len(ds)):
        c0, c1 = px[ds[i - 1]][1], px[ds[i]][1]
        if c0 > 0 and c1 / c0 - 1 <= -0.15:
            def fwd(j0, n): return px[ds[j0 + n]][1] / px[ds[j0]][1] - 1 if j0 + n < len(ds) else None
            def low(j0, n): return min(px[ds[k]][1] for k in range(j0 + 1, min(len(ds), j0 + n + 1))) / px[ds[j0]][1] - 1 if j0 + 1 < len(ds) else None
            e = dict(t=t, day=ds[i], drop=c1 / c0 - 1, gap=px[ds[i]][0] / c0 - 1)
            for lab, j0 in (('d0', i), ('d1', i + 1), ('d3', i + 3)):
                if j0 < len(ds):
                    e[lab] = {f'r{n}': fwd(j0, n) for n in (1, 5, 10, 20)} | {f'low{n}': low(j0, n) for n in (5, 20)}
            events.append(e)
json.dump(events, open(os.path.join(DATA, 'events.json'), 'w'), indent=1)
print('tickers with data', sum(1 for v in PX.values() if v), 'of', len(uni), '| events', len(events))
