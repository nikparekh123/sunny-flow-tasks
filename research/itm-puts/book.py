from forward import *
NAMES = ['NKE', 'LULU', 'BABA', 'NFLX']
def P(t, long_r, itm, tenor, short_r, otm=0.015, call_r=1.0):
    nL = LEAP[t][0]
    return dict(long_n=round(nL * long_r), itm=itm, tenor=tenor, short_n=round(nL * short_r), otm=otm, call_n=round(nL * call_r), lotto_n=0)
VARS = [
    ("Today (no puts)", lambda t: P(t, 0, 0, 3, 0)),
    ("Your plan: 25/60 long 8% ITM, sell 15/60", lambda t: P(t, 25/60, 0.08, 3 if t != 'NFLX' else 5, 15/60)),
    ("  sell 8/60 instead of 15", lambda t: P(t, 25/60, 0.08, 3 if t != 'NFLX' else 5, 8/60)),
    ("  no weekly puts", lambda t: P(t, 25/60, 0.08, 3 if t != 'NFLX' else 5, 0)),
    ("  sell 25/60 (all)", lambda t: P(t, 25/60, 0.08, 3 if t != 'NFLX' else 5, 25/60)),
    ("  long 30/60, sell 15/60", lambda t: P(t, 30/60, 0.08, 3 if t != 'NFLX' else 5, 15/60)),
    ("  5-month on every name", lambda t: P(t, 25/60, 0.08, 5, 15/60)),
]
scens = ['flat', 'up 15%', 'rip 25% in 3m', 'bull +40%', 'down 15%', 'crash 30% in 2m', 'V: -20% then back']
print("All four names together (NKE, LULU, BABA, NFLX). Sum of each name's median 12-month P&L; difference vs today in brackets.")
print(f"{'plan':42}" + "".join(f"{s[:13]:>21}" for s in scens) + f"{'-15% now':>10}{'-25% now':>10}")
base = None
for name, mk in VARS:
    tot = []
    for s in scens:
        tot.append(sum(np.median(simulate(t, s, mk(t))['total']) for t in NAMES))
    st15 = sum(stress(t, mk(t), 0.15) for t in NAMES); st25 = sum(stress(t, mk(t), 0.25) for t in NAMES)
    if base is None: base = (tot, st15, st25)
    row = f"{name:42}" + "".join(f"{fmt(v):>10} ({fmt(v - b).strip():>7})" for v, b in zip(tot, base[0]))
    row += f"{fmt(st15):>10}{fmt(st25):>10}"
    print(row, flush=True)
