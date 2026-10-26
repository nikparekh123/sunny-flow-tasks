"""Flow profile (handoff 32, Nik's rule 5, 26 Oct 2026 "full"): five inputs per name over the last 20 sessions,
ranked against the book, the watchlist and the 100 most-traded option names (no ETFs):
  1. share of option volume under 7 days to expiry      (higher = retail)
  2. call to put volume ratio                           (higher = retail)
  3. median trade size, contracts                       (lower = retail)
  4. share of trades of 10 contracts or fewer           (higher = retail)
  5. institutional ownership, % of shares               (lower = retail; Nasdaq 13F, Yahoo refused us)
Retail-heavy when at least 3 of 5 rank beyond the 70th percentile toward retail; otherwise Institution-heavy.
Inputs 1-2 come from Theta's end-of-day volumes (all expiries, one request per name); 3-4 from every option trade
of every session (all expiries, one request per name per day), streamed, never held. Results go to flow_profile.
Usage: run.py [--refresh]   (caches per name and per name-day in ./cache, so a stopped run resumes)"""
import csv, io, json, os, subprocess, sys, time, urllib.request, datetime as dt

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache'); os.makedirs(CACHE, exist_ok=True)
sec = lambda s: subprocess.check_output(['security', 'find-generic-password', '-a', 'sunnyfi', '-s', s, '-w']).decode().strip()
PK, TH = sec('theta_proxy_key'), 'https://sunnyfi-theta.fly.dev'
PAT, REF = sec('supabase_pat'), 'ziwoutsnuywjnsyfbzsp'
UA = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
      'Accept': 'application/json, text/plain, */*', 'Origin': 'https://www.nasdaq.com', 'Referer': 'https://www.nasdaq.com/'}

# Stocks with busy option chains (no ETFs); the 100 busiest by 20-day option volume make the universe.
CANDIDATES = """AAPL MSFT NVDA AMZN GOOGL META TSLA AMD AVGO NFLX PLTR SMCI MSTR COIN HOOD SOFI INTC MU BAC JPM C WFC GS MS
XOM CVX OXY F GM RIVN LCID NIO XPEV LI BABA JD PDD BIDU UBER LYFT ABNB DASH SHOP XYZ PYPL DIS NKE SBUX MCD WMT TGT COST
HD LOW BA CAT DE GE LMT RTX PFE MRNA JNJ LLY NVO UNH CVS ABBV MRK BMY GILD AMGN TSM ARM QCOM TXN ORCL CRM ADBE NOW SNOW
CRWD PANW NET DDOG ZS MDB U RBLX SNAP PINS SPOT ROKU TTD DKNG CHWY GME AMC MARA RIOT CLSK CVNA AFRM UPST SE MELI TLRY
AAL DAL UAL CCL NCLH RCL T VZ TMUS KO PEP PG CSCO IBM DELL HPQ ANET MRVL ON WDC STX LULU TJX ETSY EBAY BBY CLF FCX NEM
AA VALE SLB HAL DVN ENPH FSLR PLUG RUN QS JOBY ACHR IONQ RGTI QUBT SOUN BBAI AI PATH OKLO SMR CEG VST APP INTU FIS BX
KKR SCHW AXP V MA COF ZM DOCU TWLO OKTA LUV HUT WULF IREN CORZ NBIS CRWV CRCL HIMS OPEN RKLB ASTS LUNR CELH ELF""".split()


def theta(path, fmt='csv', tries=6):
    for i in range(tries):
        try:
            r = urllib.request.Request(f'{TH}{path}&format={fmt}', headers={'x-proxy-key': PK})
            return urllib.request.urlopen(r, timeout=600)
        except urllib.error.HTTPError as e:
            if e.code == 472: return None                     # no data
            if e.code in (429, 500, 502, 503, 504) and i < tries - 1: time.sleep(2 ** i); continue
            raise
        except Exception:
            if i < tries - 1: time.sleep(5 * (i + 1)); continue
            raise


def rows(resp):
    """Stream a Theta CSV response as dicts, a line at a time."""
    for row in csv.DictReader(io.TextIOWrapper(resp, encoding='utf-8')):
        yield row


def sql(q):
    body = json.dumps({'query': q}).encode()
    r = urllib.request.Request(f'https://api.supabase.com/v1/projects/{REF}/database/query', data=body, method='POST',
                               headers={'Authorization': f'Bearer {PAT}', 'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(r, timeout=120).read())


def sessions(n=20):
    """The last n sessions that have closed, from SPY's daily bars."""
    end = dt.date.today() - dt.timedelta(days=1)
    start = end - dt.timedelta(days=45)
    resp = theta(f'/v3/stock/history/eod?symbol=SPY&start_date={start:%Y%m%d}&end_date={end:%Y%m%d}')
    days = sorted({r['created'][:10] for r in rows(resp) if float(r.get('volume') or 0) > 0})
    return days[-n:]


def cached(name, fn):
    p = os.path.join(CACHE, name + '.json')
    if os.path.exists(p) and '--refresh' not in sys.argv: return json.load(open(p))
    v = fn(); json.dump(v, open(p, 'w')); return v


def volumes(t, days):
    """Inputs 1-2 and the name's total option volume, from end-of-day rows of every expiry."""
    resp = theta(f'/v3/option/history/eod?symbol={t}&expiration=*&start_date={days[0].replace("-", "")}&end_date={days[-1].replace("-", "")}')
    if resp is None: return None
    tot = u7 = calls = puts = 0
    ds = set(days)
    for r in rows(resp):
        d = r['created'][:10]
        if d not in ds: continue
        v = float(r.get('volume') or 0)
        if v <= 0: continue
        tot += v
        if (dt.date.fromisoformat(r['expiration']) - dt.date.fromisoformat(d)).days < 7: u7 += v
        if r['right'] == 'CALL': calls += v
        else: puts += v
    return {'vol': tot, 'u7': u7, 'calls': calls, 'puts': puts}


def sizes(t, day):
    """Every option trade of one session (all expiries): trade counts by size, 1 to 10 one by one, then buckets."""
    resp = theta(f'/v3/option/history/trade?symbol={t}&expiration=*&date={day.replace("-", "")}')
    if resp is None: return {}
    h = {}
    for r in rows(resp):
        n = int(float(r.get('size') or 0))
        if n <= 0: continue
        k = str(n) if n <= 10 else '11-25' if n <= 25 else '26-50' if n <= 50 else '51-100' if n <= 100 else '101+'
        h[k] = h.get(k, 0) + 1
    return h


def ownership(t):
    u = f'https://api.nasdaq.com/api/company/{t}/institutional-holdings?limit=1&type=TOTAL&sortColumn=marketValue&sortOrder=DESC'
    try:
        j = json.loads(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=30).read())
        v = ((j.get('data') or {}).get('ownershipSummary') or {}).get('SharesOutstandingPCT', {}).get('value')
        return float(v.strip('%').replace(',', '')) if v else None
    except Exception:
        return None


ORDER = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11-25', '26-50', '51-100', '101+']


def median(h):
    tot = sum(h.values()); run = 0
    for k in ORDER:
        run += h.get(k, 0)
        if tot and run >= tot / 2: return int(k.split('-')[0].replace('+', ''))
    return None


def main():
    snap = sql("select payload->'strategies' s, payload->'watchlist' w from home_snapshot where id=1")[0]
    ours = sorted(set(json.loads(snap['s']) if isinstance(snap['s'], str) else snap['s']) | {'TSLA'}
                  | {w['ticker'] for w in (json.loads(snap['w']) if isinstance(snap['w'], str) else snap['w'])})
    days = sessions()
    print('sessions', days[0], days[-1], len(days), 'ours', ours, flush=True)
    vols = {}
    for t in ours + [c for c in CANDIDATES if c not in ours]:
        v = cached(f'vol_{t}_{days[-1]}', lambda: volumes(t, days))
        if v: vols[t] = v
        print('vol', t, v and int(v['vol']), flush=True)
    top = [t for t in sorted((c for c in CANDIDATES if c in vols and c not in ours), key=lambda c: -vols[c]['vol'])][:100]
    universe = ours + top
    print('universe', len(universe), flush=True)
    out = {}
    for t in universe:
        if t not in vols: continue
        h = {}
        for d in days:
            for k, n in cached(f'sz_{t}_{d}', lambda: sizes(t, d)).items(): h[k] = h.get(k, 0) + n
        own = cached(f'own_{t}_{days[-1][:7]}', lambda: ownership(t))
        trades = sum(h.values())
        v = vols[t]
        out[t] = {'u7': v['u7'] / v['vol'] if v['vol'] else None, 'cp': v['calls'] / v['puts'] if v['puts'] else None,
                  'med': median(h), 'small': sum(h.get(str(i), 0) for i in range(1, 11)) / trades if trades else None,
                  'own': own, 'vol': v['vol'], 'trades': trades}
        print('sizes', t, out[t], flush=True)
    # Percentile toward retail within the universe, per input.
    spec = [('u7', 'Volume under 7 days to expiry', 1), ('cp', 'Call to put volume ratio', 1), ('med', 'Median trade size', -1),
            ('small', 'Trades of 10 contracts or fewer', 1), ('own', 'Institutional ownership', -1)]
    res = []
    for t in ours:
        if t not in out: continue
        inputs, retail = [], 0
        for k, name, sign in spec:
            x = out[t][k]
            pool = [out[u][k] for u in out if out[u][k] is not None]
            if x is None or not pool: inputs.append({'key': k, 'name': name, 'value': None, 'pct': None, 'retail': False}); continue
            # Midrank: ties share the middle (most names' median option trade is 1 contract, so a plain rank put every
            # such name at the top).
            below = sum(1 for y in pool if (y < x if sign > 0 else y > x)); same = sum(1 for y in pool if y == x)
            pct = round(100 * (below + 0.5 * same) / len(pool))
            r = pct > 70
            retail += r
            inputs.append({'key': k, 'name': name, 'value': x, 'pct': pct, 'retail': r})
        res.append({'ticker': t, 'asof': days[-1], 'sessions': len(days), 'universe': len(out), 'retail': retail,
                    'profile': 'retail-heavy' if retail >= 3 else 'institution-heavy', 'inputs': inputs})
        print('profile', t, retail, res[-1]['profile'], flush=True)
    vals = ','.join("('%s','%s',%d,%d,%d,'%s','%s'::jsonb, now())" % (r['ticker'], r['asof'], r['sessions'], r['universe'], r['retail'],
                    r['profile'], json.dumps(r['inputs']).replace("'", "''")) for r in res)
    sql('insert into flow_profile (ticker, asof, sessions, universe, retail, profile, inputs, built_at) values ' + vals
        + ' on conflict (ticker) do update set asof=excluded.asof, sessions=excluded.sessions, universe=excluded.universe,'
        + ' retail=excluded.retail, profile=excluded.profile, inputs=excluded.inputs, built_at=excluded.built_at')
    print('done', len(res), flush=True)


if __name__ == '__main__':
    main()
