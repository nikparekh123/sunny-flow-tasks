"""Gamma backfill (handoff 32): for each name, every session from the start, in order, the 'tape' job then the
'gamma' job of gex-walls (positions depend on the day before). Usage: run.py CRONKEY START END NAME [NAME...]"""
import json, sys, time, urllib.request, os
KEY, START, END, NAMES = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
FN = 'https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/gex-walls'
SESS = [d for d in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'walls-respect', 'cache', 'bars_SPY.json'))) if START <= d <= END]
SESS.sort()
def call(body, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(FN, data=json.dumps(body).encode(), headers={'x-cron-key': KEY, 'Content-Type': 'application/json'}, method='POST')
            with urllib.request.urlopen(req, timeout=400) as r: return json.loads(r.read())
        except Exception as e:
            err = str(e)
            try: err += ' ' + e.read().decode()[:300]
            except Exception: pass
            if i == tries - 1: return {'ok': False, 'error': err}
            time.sleep(10 * (i + 1))
print('sessions', len(SESS), SESS[0], SESS[-1], flush=True)
for spec in NAMES:
    t, _, since = spec.partition('@')          # NAME or NAME@first-day (resume)
    for d in [x for x in SESS if not since or x >= since]:
        # SKIP_TAPE=1: the tape is stored, only the labels re-run (26 Oct 2026, the coverage gate dropped).
        # ONLY=exp,exp: just those expiries (newly tracked ones, 26 Oct 2026: the far hedge rungs). Their tape, then
        # positions only, so the stored views of past days stay as they were; the last day rebuilds its views.
        only = [x for x in os.environ.get('ONLY', '').split(',') if x]
        a = ({'ok': True, 'contracts': 'stored'} if os.environ.get('SKIP_TAPE')
             else call({'mode': 'tape', 'ticker': t, 'as_of': d, 'expiries': only}) if only
             else call({'mode': 'tape', 'ticker': t, 'as_of': d, 'split': True}))   # two expiries per call (TSLA's busy days)
        # The track record only on the last day (26 Oct 2026: it made each past day minutes slower in the session).
        b = (call({'mode': 'gamma', 'ticker': t, 'as_of': d, 'no_track': d != SESS[-1], 'positions_only': bool(only) and d != SESS[-1]})
             if a.get('ok') else {'ok': False, 'error': 'tape failed'})
        print(t, d, 'tape', a.get('contracts') if a.get('ok') else a.get('error'), 'cov', a.get('coverage'),
              '| gamma', b.get('positions') if b.get('ok') else b.get('error', b.get('problems')), flush=True)
print('done', NAMES, flush=True)
