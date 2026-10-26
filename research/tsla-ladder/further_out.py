"""Further-out test after big up weeks, TSLA (Nik, 18 Oct 2026). Model research, not advice.
Rule: at each call sale, if TSLA rose X% or more over the last 5 sessions, the sale goes further out:
'step' (at the money -> 5% out, 5% out -> 10% out), 'all10' (everything 10% out) or 'skip' (no sale on
that expiry). X = 5%, 8%, 10%. Checked on (1) the real-weeks forward test (forward_real.py: Safe / Moderate
/ Wild, next-morning buy-back, 500 paths, same paths for every rule) and (2) TSLA's real Feb-Oct 2026
quotes with the grid's best setup (1-month at-the-money calls bought, weekly, band -150..150).
Usage: python3 further_out.py"""
import json, math, random, statistics as stt, os
from multiprocessing import Pool
import forward_real as FR, grid as G
RULES = [None] + [(x, m) for x in (0.05, 0.08, 0.10) for m in ('step', 'all10', 'skip')]
P = FR.setup('TSLA'); P['pre5'] = [378.03, 375.23, 367.16, 362.44, 354.72]        # real closes 12-16 Oct
W = FR.real_weeks(); rng = random.Random(11); PATHS = {}
for sc, pool in W.items():
    ps = []
    for _ in range(FR.NPATH):
        d_ = []
        while len(d_) < len(FR.days): d_ += rng.choice(pool)
        S = P['S0']; px = []
        for on, intr in d_[:len(FR.days)]:
            o_ = S * math.exp(on); S = o_ * math.exp(intr); px.append((o_, S))
        ps.append(px)
    PATHS[sc] = ps
IVK = {'Safe': 0.8, 'Moderate': 1.0, 'Wild': 1.5}

def one(rule):
    FR.RULE = rule; G.RULE = rule; r = {}
    for sc, ps in PATHS.items():
        tot = sorted(sum(FR.path_run2(P, px, IVK[sc], 'open')[0].values()) for px in ps)
        r[sc] = dict(avg=stt.mean(tot), mid=tot[len(tot) // 2], bad=tot[len(tot) // 10], worst=tot[0])
    for fill in ('mid', 'worse'):
        b = G.run('1m', 'atm', '-150..150', 'weekly', fill)
        r['real_' + fill] = b['total']
    return rule, r

if __name__ == '__main__':
    with Pool(4) as pool: res = pool.map(one, RULES)
    json.dump([dict(rule=r, **v) for r, v in res], open(os.path.join(FR.DATA, 'further_out.json'), 'w'), indent=1)
    for rule, v in res:
        lab = 'today' if rule is None else f"{int(rule[0] * 100)}% {rule[1]}"
        print(f"{lab:12s} " + ' '.join(f"{sc} avg {v[sc]['avg']/1000:6.1f}K bad {v[sc]['bad']/1000:7.1f}K |" for sc in ('Safe', 'Moderate', 'Wild')) + f" real Feb-Oct mid {v['real_mid']/1000:6.1f}K bid/ask {v['real_worse']/1000:6.1f}K", flush=True)
