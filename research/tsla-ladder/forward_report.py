"""Typical (median) and bad (1 in 10) 3-month paths, leg by leg, for forward.py. Usage: python3 forward_report.py"""
import forward as F, random, json
rng = random.Random(7); out = {}
for t in F.NAMES:
    P = F.setup(t)
    idxs = [[rng.randrange(len(P['rets'])) for _ in F.days] for _ in range(F.NPATH)]
    out[t] = {'move': P['move']}
    print(f"{t}: 'could be' move {P['move'] * 100:.1f}%", flush=True)
    for sc, (vk, ik) in F.SCEN.items():
        rs = sorted(((sum(l.values()), l, m) for l, m in (F.path_run(P, ix, vk, ik) for ix in idxs)), key=lambda x: x[0])
        med, bad = rs[len(rs) // 2], rs[len(rs) // 10]
        blown = sum(1 for _, l, _ in rs if l['calls bought'] < -300000)
        out[t][sc] = dict(typical=dict(legs=med[1], total=med[0], move=med[2]), bad=dict(legs=bad[1], total=bad[0], move=bad[2]), blown=blown,
                          worst=rs[0][0], worst_bought=min(l['calls bought'] for _, l, _ in rs))
        for k in ('typical', 'bad'):
            o = out[t][sc][k]
            print(f"  {sc:8s} {k:7s} move {o['move']*100:6.1f}% " + ' '.join(f"{a} {v/1000:7.1f}K" for a, v in o['legs'].items()) + f" total {o['total']/1000:7.1f}K", flush=True)
        print(f"    blown {blown}, worst path {rs[0][0]/1000:.0f}K, worst calls bought {out[t][sc]['worst_bought']/1000:.0f}K", flush=True)
json.dump(out, open('data/forward_paths_fixed.json', 'w'), indent=1)
