"""Nik, 15 Oct: NKE March puts, 30 x 40P vs 20 x 45P vs 18 x 50P (about the same delta), how many weekly
puts to sell against each, and more 1-year $50 calls. Same engine as block.py."""
from block import *
t = 'NKE'; S0 = SPOT[t]
def itm(K): return K / S0 - 1
V = [
    ('Today: no puts', B()),
    ('30 x 40P, sell 15', B(long_n=30, itm=itm(40), short_n=15)),
    ('20 x 45P, sell 10', B(long_n=20, itm=itm(45), short_n=10)),
    ('20 x 45P, sell 15', B(long_n=20, itm=itm(45), short_n=15)),
    ('20 x 45P, sell 20', B(long_n=20, itm=itm(45), short_n=20)),
    ('18 x 50P, sell 9', B(long_n=18, itm=itm(50), short_n=9)),
    ('18 x 50P, sell 15', B(long_n=18, itm=itm(50), short_n=15)),
    ('30 x 40P, sell 15 + 20 calls', B(long_n=30, itm=itm(40), short_n=15, year_n=20)),
    ('20 x 45P, sell 15 + 20 calls', B(long_n=20, itm=itm(45), short_n=15, year_n=20)),
    ('20 x 45P, sell 15 + 30 calls', B(long_n=20, itm=itm(45), short_n=15, year_n=30)),
    ('20 x 45P, sell 20 + 30 calls', B(long_n=20, itm=itm(45), short_n=20, year_n=30)),
]
SH = ['flat', 'up 15%', 'rip 25% in 3m', 'jump 30% in 1m', 'down 15%', 'crash 30% in 2m', 'V: -20% then back', 'no view']
print(f"{'':30}" + ''.join(f"{s[:8]:>9}" for s in SH) + f"{'avg':>7}{'margin':>8}{'buyOnly':>8}{'d0':>7}{'negD':>6}")
base = None
for name, p in V:
    r = summary(t, p)
    _, _, d0 = run(t, 'flat', p, n=4)
    mg = min(shock(d0, t, -0.15, 0.05), shock(d0, t, 0.15, -0.03))
    buy = [x for x in d0 if not (x[4] == 'P' and x[0] < 0)]           # long puts only, no weekly puts sold (IBKR what-if on the buy)
    mgb = min(shock(buy, t, -0.15, 0.05), shock(buy, t, 0.15, -0.03))
    if base is None: base = (mg, mgb)
    avg = np.mean([r[s] for s in SH])
    print(f"{name:30}" + ''.join(f"{r[s]/1000:9.1f}" for s in SH) + f"{avg/1000:7.1f}{(mg-base[0])/1000:8.1f}{(mgb-base[1])/1000:8.1f}{r['delta0']:7.0f}{r['negdays_nv']:6.2f}", flush=True)
