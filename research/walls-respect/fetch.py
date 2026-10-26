"""Do gamma walls hold? Step 1: fetch (24 Oct 2026).

For TLT and IWM, every week from Oct 2024: on the Friday close (the day Nik sells) the walls of the
NEXT Friday's expiry, from gex-walls' history mode (as_of = that Friday: Theta end-of-day quotes and
that day's open interest, the same maths as the live tool). For each monthly expiry: its walls on the
previous monthly expiry day (about 4 weeks before). Plus regular-hours daily bars (from hourly bars).
Cached as JSON under ./cache so a rerun resumes.
"""
import json, os, subprocess, sys, time, urllib.request, datetime as dt

HERE = os.path.dirname(os.path.abspath(__file__)); C = os.path.join(HERE, 'cache'); os.makedirs(C, exist_ok=True)
sec = lambda s: subprocess.check_output(['security', 'find-generic-password', '-a', 'sunnyfi', '-s', s, '-w']).decode().strip()
PK = sec('theta_proxy_key'); TH = 'https://sunnyfi-theta.fly.dev'
CRON = open(sys.argv[1]).read().strip()
FN = 'https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/gex-walls'
TICKERS = sys.argv[2:] or ['TLT', 'IWM']; START, END = '2024-10-01', '2026-10-23'

def get(url, headers, body=None, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None, headers=headers, method='POST' if body else 'GET')
            with urllib.request.urlopen(req, timeout=300) as r: return json.loads(r.read())
        except Exception as e:
            if i == tries - 1: return {'ok': False, 'error': str(e)}
            time.sleep(5 * (i + 1))

def bars(t):
    f = os.path.join(C, f'bars_{t}.json')
    if os.path.exists(f):
        B = json.load(open(f))
        if all(min(x.values()) > 0 for x in B.values()): return B   # an old cache with holiday zeros is fetched again
    days = {}
    d = dt.date.fromisoformat(START)
    while d <= dt.date.fromisoformat(END):
        e = min(d + dt.timedelta(days=30), dt.date.fromisoformat(END))
        r = get(f"{TH}/v3/stock/history/ohlc?symbol={t}&start_date={d:%Y%m%d}&end_date={e:%Y%m%d}&interval=1h&format=json", {'x-proxy-key': PK})
        for b in r.get('response', []):
            # Holidays and the empty hours of a half day come back as zero bars: no trade, skip them.
            if not b.get('count') or min(b['open'], b['high'], b['low'], b['close']) <= 0: continue
            day = b['timestamp'][:10]; x = days.setdefault(day, {'o': b['open'], 'h': b['high'], 'l': b['low'], 'c': b['close']})
            x['h'] = max(x['h'], b['high']); x['l'] = min(x['l'], b['low']); x['c'] = b['close']
        d = e + dt.timedelta(days=1)
    json.dump(days, open(f, 'w')); return days

def monthly(day, tdays):
    """The third Friday, or the Thursday before it when that Friday is a holiday."""
    d = dt.date.fromisoformat(day)
    return (d.weekday() == 4 and 15 <= d.day <= 21) or (d.weekday() == 3 and 14 <= d.day <= 20 and str(d + dt.timedelta(days=1)) not in tdays)

for t in TICKERS:
    B = bars(t); tdays = sorted(B)
    print(t, len(tdays), 'sessions', tdays[0], tdays[-1], flush=True)
    # The week's last session (Friday, or Thursday before a holiday) is both the sell day and the expiry.
    weekly = [d for i, d in enumerate(tdays) if i + 1 == len(tdays) or dt.date.fromisoformat(tdays[i + 1]).isocalendar()[1] != dt.date.fromisoformat(d).isocalendar()[1]]
    weekly = [d for d in weekly if d >= '2024-10-25']
    T = set(tdays); mons = [d for d in tdays if monthly(d, T)]
    for i, D in enumerate(weekly[:-1]):
        E = weekly[i + 1]
        if (dt.date.fromisoformat(E) - dt.date.fromisoformat(D)).days > 8: continue
        exps = [E] + [M for M in mons if M > E and D in mons and M == next((m for m in mons if m > D), None)]
        f = os.path.join(C, f'w_{t}_{D}.json')
        if os.path.exists(f):
            old = json.load(open(f))
            if old['exps'] == exps and old['r'].get('ok') and len(old['r'].get('rows', [])) == len(exps): continue
        r = get(FN, {'x-cron-key': CRON, 'Content-Type': 'application/json'}, {'ticker': t, 'per_expiry': True, 'as_of': D, 'save': False, 'expiries': exps})
        if not r.get('ok'):  # an expiry Theta does not list that day (holiday weeks): try the weekly alone
            r = get(FN, {'x-cron-key': CRON, 'Content-Type': 'application/json'}, {'ticker': t, 'per_expiry': True, 'as_of': D, 'save': False, 'expiries': [E]})
        if r.get('ok'): json.dump({'D': D, 'E': E, 'exps': exps, 'r': r}, open(f, 'w'))  # a failed week is fetched again on a rerun
        print(t, D, '->', exps, 'ok' if r.get('ok') else r.get('error'), r.get('errors') or '', flush=True)
print('done')
