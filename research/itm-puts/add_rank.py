"""Which name to add (Nik, 15 Oct): every candidate as the same NEW block, about $150K of stock,
Jan 2028 LEAP near 0.80 delta (SPCX 0.85), calls on all (roll-sheet split), with and without the
suggested put overlay (buy 1/2, sell 1/4 at 2% out). Results per $100K of stock."""
from block import *
L = live_all()
NAMES = sys.argv[1:] or ['LULU', 'BABA', 'NFLX', 'ADBE', 'INTU', 'SPCX', 'TSLA', 'PYPL', 'APP']
SH = ['flat', 'up 15%', 'jump 30% in 1m', 'down 15%', 'crash 30% in 2m', 'V: -20% then back', 'no view']
T28 = years(TODAY, '2028-01-21')
for t in NAMES:
    S = SPOT[t]; q = Q[t]; tgt = 0.85 if t == 'SPCX' else 0.80
    ch = L[t]['2028-01-21']['C']
    cand = [(k, iv(sum(v) / 2, S, k, T28, q, 'C')) for k, v in ch.items() if 0.4 * S < k < S]
    k, _ = min([c for c in cand if c[1]], key=lambda c: abs(delta(S, c[0], T28, c[1], q, 'C') - tgt))
    # LEAP_K="VZ:33,T:18" forces a strike (16 Oct): on cheap names the deep in-the-money quotes are so wide that
    # the mid's IV is inflated and the pick above lands near 0.90 delta, not 0.80. Unset = the original pick.
    k = dict((a, float(b)) for a, b in (x.split(':') for x in os.environ.get('LEAP_K', '').split(',') if x)).get(t, k)
    mid = sum(ch[k]) / 2
    n = 150000 / (100 * S)                       # exact size so every name is the same $150K
    LEAP[t] = (n, k)
    out = {}
    for lab, p in (('none', B(call_n=n)), ('hedged', B(call_n=n, long_n=n / 2, short_n=n / 4))):
        r = summary(t, p); out[lab] = {s: r[s] / 1.5 for s in SH}; out[lab]['d15'] = r['drop15'] / 1.5
    tv = (mid - max(0, S - k)) / S / T28 * 100
    cl = closes(t); ks = sorted(cl); last = cl[ks[-1]]; w = [cl[x] for x in ks[-252:]]
    pos = (last - min(w)) / (max(w) - min(w)) * 100
    print(t, k, round(tv, 1), round(RHO0[t], 2), round(pos), json.dumps({l: {s: round(v / 1000, 1) for s, v in o.items()} for l, o in out.items()}), flush=True)
