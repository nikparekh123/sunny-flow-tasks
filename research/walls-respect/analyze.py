"""Do gamma walls hold? Step 2: the numbers (24 Oct 2026).

Each week: walls of next Friday's expiry at this Friday's close (spot = the quotes' implied price).
  Held at the close: the expiry's regular-hours close stayed on its side of the wall
                     (at or under a call wall, at or over a put wall).
  Never touched:     no regular-hours trade went through it all week.
The fair comparison is a strike the SAME distance away with no wall: how often the stock stayed inside
that distance over any 5 sessions (every start day in the two years, this week left out). If walls do
something, "held" beats "same distance". Monthlies the same: walls ~4 weeks out on the previous monthly
expiry, compared with any window of the same number of sessions.
"""
import json, os, glob, statistics as st

HERE = os.path.dirname(os.path.abspath(__file__)); C = os.path.join(HERE, 'cache')

def load(t):
    B = json.load(open(os.path.join(C, f'bars_{t}.json')))
    B = {d: x for d, x in B.items() if min(x.values()) > 0}; days = sorted(B)
    W = []
    for f in sorted(glob.glob(os.path.join(C, f'w_{t}_*.json'))):
        x = json.load(open(f)); r = x['r']
        if not r.get('ok'): continue
        for row in r['rows']:
            W.append({'D': x['D'], 'E': row['expiry'], 'S': r['spot'], 'flip': row['flip'], 'call': row['call'], 'put': row['put']})
    return B, days, W

def path(B, days, D, E):
    seg = [d for d in days if D < d <= E]
    if not seg or seg[-1] != E: return None
    return max(B[d]['h'] for d in seg), min(B[d]['l'] for d in seg), B[E]['c'], len(seg)

def windows(B, days, n):
    """Every n-session window: (max high, min low, last close) as returns on the start day's close."""
    out = []
    for i in range(len(days) - n):
        s = B[days[i]]['c']; seg = days[i + 1:i + 1 + n]
        out.append((days[i], max(B[d]['h'] for d in seg) / s - 1, min(B[d]['l'] for d in seg) / s - 1, B[seg[-1]]['c'] / s - 1))
    return out

def study(t, monthly):
    B, days, W = load(t)
    cases = []
    for w in W:
        p = path(B, days, w['D'], w['E'])
        if not p: continue
        is_m = w['E'] != min((x['E'] for x in W if x['D'] == w['D']), default=w['E'])
        if is_m != monthly: continue
        cases.append({**w, 'H': p[0], 'L': p[1], 'CE': p[2], 'n': p[3]})
    if not cases: return None
    n = round(st.median(c['n'] for c in cases))
    win = windows(B, days, n)
    def base(D, d, call, kind):
        xs = [x for x in win if abs((__import__('datetime').date.fromisoformat(x[0]) - __import__('datetime').date.fromisoformat(D)).days) > 7 * (n // 5 + 1)]
        if call: v = [x[1] <= d for x in xs] if kind == 'touch' else [x[3] <= d for x in xs]
        else:    v = [x[2] >= d for x in xs] if kind == 'touch' else [x[3] >= d for x in xs]
        return sum(v) / len(v)
    res = {}
    for side, idx, lab in [('call', 0, 'Call 1st wall'), ('call', 1, 'Call 2nd wall'), ('put', 0, 'Put 1st wall'), ('put', 1, 'Put 2nd wall')]:
        rows = []
        for c in cases:
            k = c[side][idx][0] if len(c[side]) > idx else None
            if k is None: continue
            d = k / c['S'] - 1; call = side == 'call'
            held = c['CE'] <= k if call else c['CE'] >= k
            untouched = c['H'] <= k if call else c['L'] >= k
            rows.append((abs(d), held, untouched, base(c['D'], d, call, 'close'), base(c['D'], d, call, 'touch')))
        if rows:
            res[lab] = dict(N=len(rows), dist=st.mean(r[0] for r in rows) * 100,
                            held=sum(r[1] for r in rows) / len(rows) * 100, held_exp=st.mean(r[3] for r in rows) * 100,
                            untouched=sum(r[2] for r in rows) / len(rows) * 100, untouched_exp=st.mean(r[4] for r in rows) * 100)
    # Both 1st walls: the expiry close between them.
    ch = [c for c in cases if c['call'][0][0] is not None and c['put'][0][0] is not None]
    inside = [c['put'][0][0] <= c['CE'] <= c['call'][0][0] for c in ch]
    exp_in = [base(c['D'], c['call'][0][0] / c['S'] - 1, True, 'close') - (1 - base(c['D'], c['put'][0][0] / c['S'] - 1, False, 'close')) for c in ch]
    res['Between the 1st walls'] = dict(N=len(ch), dist=st.mean((c['call'][0][0] - c['put'][0][0]) / c['S'] for c in ch) * 100,
                                        held=sum(inside) / len(ch) * 100, held_exp=st.mean(exp_in) * 100, untouched=None, untouched_exp=None)
    # Flip: weeks starting above it vs below it.
    fl = {}
    for lab, sel in [('above the flip (calmer)', lambda c: c['flip'] and c['S'] >= c['flip']), ('below the flip (choppier)', lambda c: c['flip'] and c['S'] < c['flip'])]:
        cs = [c for c in cases if sel(c)]
        if cs:
            fl[lab] = dict(N=len(cs), rng=st.mean((c['H'] - c['L']) / c['S'] for c in cs) * 100,
                           move=st.mean(abs(c['CE'] / c['S'] - 1) for c in cs) * 100,
                           call_held=sum(c['CE'] <= c['call'][0][0] for c in cs if c['call'][0][0]) / max(1, sum(1 for c in cs if c['call'][0][0])) * 100,
                           put_held=sum(c['CE'] >= c['put'][0][0] for c in cs if c['put'][0][0]) / max(1, sum(1 for c in cs if c['put'][0][0])) * 100)
    return dict(cases=len(cases), sessions=n, first=min(c['D'] for c in cases), last=max(c['E'] for c in cases), walls=res, flip=fl,
                sample=cases[-1])

out = {}
for t in (__import__('sys').argv[1:] or ['TLT', 'IWM', 'SPY', 'QQQ', 'MSFT']):
    for m in [False, True]:
        r = study(t, m)
        if not r: continue
        out[f'{t} {"monthly" if m else "weekly"}'] = r
        print(f"\n== {t} {'MONTHLY' if m else 'WEEKLY'}: {r['cases']} periods, {r['first']} to {r['last']}, {r['sessions']} sessions each")
        print(f"{'':24}{'N':>4}{'away':>7}{'held':>7}{'same-dist':>10}{'untouched':>10}{'same-dist':>10}")
        for k, v in r['walls'].items():
            u = '' if v['untouched'] is None else f"{v['untouched']:9.0f}%{v['untouched_exp']:9.0f}%"
            print(f"{k:24}{v['N']:4}{v['dist']:6.1f}%{v['held']:6.0f}%{v['held_exp']:9.0f}% {u}")
        for k, v in r['flip'].items():
            print(f"  {k:26} N {v['N']:3}  range {v['rng']:.1f}%  |move| {v['move']:.1f}%  call wall held {v['call_held']:.0f}%  put wall held {v['put_held']:.0f}%")
json.dump(out, open(os.path.join(HERE, 'results.json'), 'w'), indent=1, default=str)
