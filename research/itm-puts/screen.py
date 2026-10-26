import sys
from block import *
def plans(t):
    nL = LEAP[t][0]
    def X(**kw):
        kw.setdefault('call_n', nL)
        for k in ('long_n', 'short_n', 'qtr_n', 'year_n'):
            if k in kw: kw[k] = kw[k] * nL
        return B(**kw)
    h = dict(long_n=1/2, short_n=1/4)
    return [
        ('today', X()),
        ('today, delta floor 20%', X(delta_floor=0.2)),
        ('buy 1/3 sell 1/6 @2%', X(long_n=1/3, short_n=1/6)),
        ('buy 1/2 sell 1/4 @2%', X(**h)),
        ('buy 1/2 no sell', X(long_n=1/2)),
        ('  puts ATM', X(**h, put_rule=('atm',))),
        ('  puts 5% OTM', X(**h, put_rule=('otm', 0.05))),
        ('  puts 0.6 SD', X(**h, put_rule=('sd', 0.6))),
        ('  puts 1 SD', X(**h, put_rule=('sd', 1.0))),
        ('  puts 30% ATM/70% 0.6SD', X(**h, put_rule=('split', 0.3, 0.6))),
        ('  calls 70% at 1 SD', X(**h, call_z=1.0)),
        ('  calls on 80%', X(**h, call_n=0.8 * nL)),
        ('  calls on 70%', X(**h, call_n=0.7 * nL)),
        ('  calls on 60%', X(**h, call_n=0.6 * nL)),
        ('  calls, delta floor 20%', X(**h, delta_floor=0.2)),
        ('  calls, delta floor 30%', X(**h, delta_floor=0.3)),
        ('  + qtr 15% OTM x1/6', X(**h, qtr_n=1/6)),
        ('  + qtr 15% OTM x1/3', X(**h, qtr_n=1/3)),
        ('  + 1yr 30% OTM x1/6', X(**h, year_n=1/6)),
        ('  + 1yr 30% OTM x1/3', X(**h, year_n=1/3)),
    ]
SH = ['flat', 'up 15%', 'rip 25% in 3m', 'jump 30% in 1m', 'bull +40%', 'down 15%', 'crash 30% in 2m', 'V: -20% then back', 'no view']
if __name__ == '__main__':
    for t in sys.argv[1:]:
        print(f"\n{t} spot {SPOT[t]} LEAPs {LEAP[t]}  ($K, median 12m total; no view = mean)")
        print(f"{'plan':28}" + ''.join(f"{s[:7]:>8}" for s in SH) + f"{'avg':>7}{'d0':>7}{'negW':>6}{'negDnv':>7}{'-15%':>7}{'+20%':>7}")
        for name, p in plans(t):
            r = summary(t, p); avg = np.mean([r[s] for s in SH])
            print(f"{name:28}" + ''.join(f"{r[s]/1000:8.1f}" for s in SH) + f"{avg/1000:7.1f}{r['delta0']:7.0f}{r['negweeks']:6.2f}{r['negdays_nv']:7.2f}{r['drop15']/1000:7.1f}{r['jump20']/1000:7.1f}", flush=True)
