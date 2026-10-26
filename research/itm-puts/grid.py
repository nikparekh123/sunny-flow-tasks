import sys
from forward import *
t = sys.argv[1] if len(sys.argv) > 1 else 'NKE'
nL = LEAP[t][0]; f = nL / 60
def P(long_n, itm, tenor, short_n, otm, call_n, lotto_n=0):
    return dict(long_n=round(long_n * f), itm=itm, tenor=tenor, short_n=round(short_n * f), otm=otm, call_n=round(call_n * f), lotto_n=round(lotto_n * f))
plans = [
    ("Today: no puts, calls on all", P(0, 0, 3, 0, 0, 60)),
    ("Your plan: 25 x 3m 8% ITM, sell 15 wkly", P(25, 0.08, 3, 15, 0.015, 60)),
    ("  same, no weekly puts", P(25, 0.08, 3, 0, 0.015, 60)),
    ("  same, sell 25 weekly (all)", P(25, 0.08, 3, 25, 0.015, 60)),
    ("  same, weekly puts at the money", P(25, 0.08, 3, 15, 0.0, 60)),
    ("  ATM long puts instead", P(25, 0.0, 3, 15, 0.015, 60)),
    ("  15% ITM long puts instead", P(25, 0.15, 3, 15, 0.015, 60)),
    ("  5-month (Mar) puts instead", P(25, 0.08, 5, 15, 0.015, 60)),
    ("  8-month (Jun) puts instead", P(25, 0.08, 8, 15, 0.015, 60)),
    ("  40 long puts, sell 25", P(40, 0.08, 3, 25, 0.015, 60)),
    ("  calls on 42 not 60", P(25, 0.08, 3, 15, 0.015, 42)),
    ("  + 15 lotto calls (Dec 27, +35%)", P(25, 0.08, 3, 15, 0.015, 60, 15)),
]
scens = ['flat', 'up 15%', 'rip 25% in 3m', 'down 15%', 'crash 30% in 2m', 'V: -20% then back']
print(f"\n{t} spot {SPOT[t]} | {nL} LEAPs | median 12-month TOTAL book P&L by scenario | stress = instant drop today, positions as of today")
print(f"{'plan':40}" + "".join(f"{s[:13]:>14}" for s in scens) + f"{'-15% now':>10}{'-25% now':>10}")
for name, plan in plans:
    row = f"{name:40}"
    for s in scens:
        row += f"{fmt(np.median(simulate(t, s, plan)['total'])):>14}"
    row += f"{fmt(stress(t, plan, 0.15)):>10}{fmt(stress(t, plan, 0.25)):>10}"
    print(row, flush=True)
