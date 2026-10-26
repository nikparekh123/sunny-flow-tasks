"""Split-adjusted events from scan.py's prices (Theta closes are NOT split-adjusted). A day whose
close AND open both sit within 6% of a common split ratio of the prior close is a split; everything
before it is scaled by that ratio. Usage: python3 events.py"""
import json, os, glob
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
# 3-for-2 (2/3) is left out: real -33% crashes (ALGN, SNPS, TTD) look the same; WRB's July 2024
# 3-for-2 is added by hand. DD's -57% on 3 Nov 2025 is the Qnity spin-off, not a crash.
MANUAL = {('WRB', '2024-07-11'): 2/3}
NOT_CRASH = {('DD', '2025-11-03')}
RATIOS = [1/2, 1/3, 1/4, 1/5, 1/6, 1/8, 1/10, 1/15, 1/20, 1/25, 1/40, 1/50, 2, 3, 4, 5, 10, 20]
splits, events = [], []
for f in sorted(glob.glob(os.path.join(DATA, 'px_*.json'))):
    t = os.path.basename(f)[3:-5]; px = json.load(open(f)); ds = sorted(px)
    if len(ds) < 30: continue
    o = [px[d][0] for d in ds]; c = [px[d][1] for d in ds]
    for i in range(len(ds) - 1, 0, -1):
        r, ro = c[i] / c[i - 1], o[i] / c[i - 1]
        R = MANUAL.get((t, ds[i])) or next((R for R in RATIOS if abs(r / R - 1) < 0.06 and abs(ro / R - 1) < 0.06), None)
        if R:
            splits.append((t, ds[i], round(1 / R, 2)))
            for j in range(i): c[j] *= R; o[j] *= R
    for i in range(1, len(ds)):
        if c[i] / c[i - 1] - 1 <= -0.15 and (t, ds[i]) not in NOT_CRASH:
            def fwd(j0, n): return c[j0 + n] / c[j0] - 1 if j0 + n < len(c) else None
            def low(j0, n): return min(c[j0 + 1:j0 + n + 1]) / c[j0] - 1 if j0 + 1 < len(c) else None
            e = dict(t=t, day=ds[i], drop=c[i] / c[i - 1] - 1, gap=o[i] / c[i - 1] - 1)
            for lab, j0 in (('d0', i), ('d1', i + 1), ('d3', i + 3)):
                if j0 < len(c): e[lab] = {f'r{n}': fwd(j0, n) for n in (1, 5, 10, 20)} | {f'low{n}': low(j0, n) for n in (5, 20)}
            events.append(e)
json.dump(events, open(os.path.join(DATA, 'events_adj.json'), 'w'), indent=1)
json.dump(splits, open(os.path.join(DATA, 'splits.json'), 'w'))
print('splits found', len(splits), '| events', len(events), 'tickers', len({e['t'] for e in events}))
print('largest remaining drops:', sorted((round(e['drop'] * 100, 1), e['t'], e['day']) for e in events)[:10])
