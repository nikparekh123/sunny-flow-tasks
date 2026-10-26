import sys
from forward import *
t = sys.argv[1] if len(sys.argv) > 1 else 'NKE'
nL = LEAP[t][0]
plan = dict(long_n=round(nL * 25 / 60), itm=0.08, tenor=3, short_n=round(nL * 15 / 60), otm=0.015, call_n=nL)
print(f"{t}: {plan['long_n']} long puts ~8% ITM 3m, {plan['short_n']} weekly short puts 1.5% OTM   (medians over 300 paths, 12 months)")
print(f"{'scenario':20}{'put spend':>11}{'put back':>10}{'short puts':>11}{'overlay':>10}{'hedge cost':>12}{'LEAP':>10}{'calls':>10}")
for s in SCEN:
    r = simulate(t, s, plan)
    m = {k: np.median(v) for k, v in r.items()}
    cost = -(m['putback'] + m['shortput'] - m['putspend']) / m['putspend']
    print(f"{s:20}{fmt(-m['putspend']):>11}{fmt(m['putback']):>10}{fmt(m['shortput']):>11}{fmt(m['overlay']):>10}{cost:>11.0%} {fmt(m['leap']):>10}{fmt(m['calls']):>10}")
