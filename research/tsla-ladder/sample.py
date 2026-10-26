"""Sample week for Nik's three-expiry ladder, option B (18 Oct 2026). Model research, not advice.
Set up at the close of Fri 18 Sep 2026: 1,000 TSLA shares; 10 calls on each of the next three
expiries; every expiry day the expiring 10 settle and 10 are sold on the next expiry, so three
are always open. Sales rotate: every third one AT the money, the other two 3% OUT. Long calls
~3 months at the money, re-sized on each expiry day so 'could be' (the lower net delta after an
instant 5% move either way) sits near +150 whenever it leaves 0..+300. Real Theta mids."""
import json, math, os
from sim import theta, bs, iv_of, yrs, D, DATA
T_, OTM = 'TSLA', 0.03
d = json.load(open(os.path.join(DATA, f'{T_}.json'))); C = d['closes']
cache_p = os.path.join(DATA, 'sample_cache.json'); cache = json.load(open(cache_p)) if os.path.exists(cache_p) else {}
def chain(e, day):
    k = f'c|{e}|{day}'
    if k not in cache:
        q = {}
        for c in theta(f"/v3/option/history/eod?symbol={T_}&expiration={e.replace('-', '')}&right=call&start_date={day.replace('-', '')}&end_date={day.replace('-', '')}"):
            for x in c.get('data', []):
                if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[str(float(c['contract']['strike']))] = [x['bid'], x['ask']]
        cache[k] = q
    return {float(a): (b[0] + b[1]) / 2 for a, b in cache[k].items()}
def mark(e, K, day):
    k = f'h|{e}|{K}'
    if k not in cache:
        q = {}
        for c in theta(f"/v3/option/history/eod?symbol={T_}&expiration={e.replace('-', '')}&right=call&strike={K}&start_date=20260918&end_date={min(e, '2026-10-16').replace('-', '')}"):
            for x in c.get('data', []):
                if (x.get('bid') or 0) > 0 and (x.get('ask') or 0) > 0: q[x['created'][:10]] = (x['bid'] + x['ask']) / 2
        cache[k] = q
    return cache[k].get(day)
days = [x for x in sorted(C) if '2026-09-18' <= x <= '2026-09-25']
slots = [s for s, _ in d['slots'] if s > '2026-09-18']
cash = 0.0; shorts = {}; longs = {'n': 0, 'e': None, 'K': None}; prev = None; n_sold = 0; rows = []
def delta_at(S, day, n_long):
    v = 1000.0
    for e, s in shorts.items():
        if e > day:
            m = mark(e, s['K'], day); iv = iv_of(m, C[day], s['K'], yrs(day, e)) if m else s['iv']
            v -= 1000 * bs(S, s['K'], yrs(day, e), iv or s['iv'])[1]
    if n_long:
        m = mark(longs['e'], longs['K'], day); iv = iv_of(m, C[day], longs['K'], yrs(day, longs['e'])) or 0.45
        v += n_long * 100 * bs(S, longs['K'], yrs(day, longs['e']), iv)[1]
    return v
for day in days:
    S = C[day]; acts = []
    if day == days[0]:
        cash -= 1000 * S; acts.append(f"Buy 1,000 shares at ${S:.2f}")
        sells = slots[:3]
    elif day in slots:
        s = shorts.pop(day); x = max(0, S - s['K']) * 1000
        if x > 0: cash -= x + 5; acts.append(f"{s['K']:g} calls ({day[5:]}) in the money: shares called at {s['K']:g}, bought back at {S:.2f}: -${x:,.0f}")
        else: acts.append(f"{s['K']:g} calls ({day[5:]}) expire worthless: keep the ${s['p'] * 1000:,.0f}")
        sells = [slots[slots.index(day) + 3]]
    else: sells = []
    for e in sells:
        q = chain(e, day); ks = sorted(q)
        atm = n_sold % 3 == 0
        K = min(ks, key=lambda k: abs(k - S)) if atm else next(k for k in ks if k >= S * (1 + OTM))
        p = q[K]; cash += p * 1000 - 6.5; n_sold += 1
        shorts[e] = dict(K=K, p=p, iv=iv_of(p, S, K, yrs(day, e)) or 0.5, kind='at the money' if atm else '3% out')
        acts.append(f"Sell 10 x {e[5:]} ${K:g} ({'at the money' if atm else '3% out'}): +${p * 1000:,.0f}")
    if day == days[0] or day in slots:                          # re-size the long calls
        if longs['e'] is None:
            e = '2026-12-18'; q = chain(e, day); K = min(q, key=lambda k: abs(k - S)); longs.update(e=e, K=K)
        cb = lambda n: min(delta_at(S * 0.95, day, n), delta_at(S * 1.05, day, n))
        if not (0 <= cb(longs['n']) <= 300) or longs['n'] == 0:
            n = min(range(0, 80), key=lambda n: abs(cb(n) - 150)); dn = n - longs['n']
            if dn:
                m = mark(longs['e'], longs['K'], day) or chain(longs['e'], day)[longs['K']]
                cash -= dn * m * 100 + 0.65 * abs(dn); longs['n'] = n
                acts.append(f"{'Buy' if dn > 0 else 'Sell'} {abs(dn)} x Dec 18 ${longs['K']:g} calls at ${m:.2f}: {'-' if dn > 0 else '+'}${abs(dn) * m * 100:,.0f}")
    sv = sum(1000 * (mark(e, s['K'], day) if e > day and mark(e, s['K'], day) is not None else max(0, S - s['K'])) for e, s in shorts.items())
    lv = longs['n'] * 100 * (mark(longs['e'], longs['K'], day) or 0)
    eq = cash + 1000 * S + lv - sv
    rows.append(dict(day=day, S=S, acts=acts, pnl=None if prev is None else eq - prev, eq=eq,
                     now=delta_at(S, day, longs['n']), cb=min(delta_at(S * 0.95, day, longs['n']), delta_at(S * 1.05, day, longs['n'])),
                     open=[(e, s['K'], s['kind']) for e, s in sorted(shorts.items()) if e > day], longs=longs['n']))
    prev = eq
json.dump(cache, open(cache_p, 'w'))
for r in rows:
    pl = '' if r['pnl'] is None else format(r['pnl'], ',.0f')
    print(f"\n{r['day']} TSLA {r['S']:.2f}  day P&L {pl}  delta now {r['now']:.0f}  could be {r['cb']:.0f}  longs {r['longs']}")
    for a in r['acts']: print('   ', a)
    print('    open:', r['open'])
print('\nweek total', round(rows[-1]['eq'] - rows[0]['eq']))
