"""Idea C after a crash (Nik, 18 Oct 2026). Model research, not advice.
Day 2 close: buy 10 in-the-money puts, strike nearest halfway back to the pre-crash close, expiry the
nearest monthly at least 45 days out. Each expiry within 4 weeks: sell weekly puts 2% out (highest strike at
or below), as many as needed for net delta of about -150 per 1,000 shares (0 if the long puts are already
above that); short puts that finish in the money are bought back at the expiry close. At the end the long
puts are sold. Real Theta quotes; deltas from each put's own implied vol. Mid, or sell at bid / buy at ask.
P&L as % of 1,000 shares at the day-2 close. Usage: python3 stepC.py"""
import json, os, math, statistics as st, datetime as dt, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tsla-ladder'))
from sim import bs, yrs
import step2 as S2
D = dt.date.fromisoformat
monthly = lambda x: 15 <= D(x).day <= 21 and D(x).weekday() == 4 or 14 <= D(x).day <= 20 and D(x).weekday() == 3
def pput(S, K, T, v): return bs(S, K, T, v)[0] - S + K * math.exp(-0.04 * T)
def piv(p, S, K, T):
    if p <= max(0, K * math.exp(-0.04 * T) - S) + 1e-4: return None
    lo, hi = 0.01, 5
    for _ in range(60):
        m = (lo + hi) / 2; lo, hi = (m, hi) if pput(S, K, T, m) < p else (lo, m)
    return (lo + hi) / 2
pdl = lambda S, K, T, v: bs(S, K, T, v)[1] - 1

def run(ev, fill):
    t = ev['t']; px = json.load(open(os.path.join(S2.DATA, f'px_{t}.json'))); ds = sorted(px)
    i = ds.index(ev['day'])
    if i < 1 or i + 1 >= len(ds): return None
    entry = ds[i + 1]
    if any(tt == t and entry <= d <= (D(entry) + dt.timedelta(days=60)).isoformat() for tt, d in S2.SPLITS): return None
    close = lambda d: px[max(x for x in ds if x <= d)][1]
    SELL = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: b)
    BUY = (lambda b, a: (b + a) / 2) if fill == 'mid' else (lambda b, a: a)
    S0 = close(entry); half = (px[ds[i - 1]][1] + px[ds[i]][1]) / 2; ex = [e for e in S2.exps(t) if e > entry]
    cand = sorted([e for e in ex if (D(e) - D(entry)).days >= 45], key=lambda e: (not monthly(e), (D(e) - D(entry)).days))
    L = None
    for e in cand[:4]:
        q = S2.chain(t, e, entry, 'put')
        if q: K = min(q, key=lambda k: abs(k - half)); L = dict(e=e, K=K, q=q[K]); break
    if not L or L['e'] > ds[-1] and False: return None
    pnl = -10 * 100 * BUY(*L['q']) - 6.5; ivL = piv(sum(L['q']) / 2, S0, L['K'], yrs(entry, L['e'])) or 0.6
    day = entry; sold = 0; last = entry
    while True:
        nxt = [e for e in ex if (D(e) - D(day)).days >= 3]
        if not nxt or (D(nxt[0]) - D(entry)).days > 28 or nxt[0] > ds[-1]: break
        e = nxt[0]; S = close(day); q = S2.chain(t, e, day, 'put')
        ql = S2.chain(t, L['e'], day, 'put').get(L['K'])
        if ql: ivL = piv(sum(ql) / 2, S, L['K'], yrs(day, L['e'])) or ivL
        dl = 10 * 100 * pdl(S, L['K'], yrs(day, L['e']), ivL)
        below = [k for k in sorted(q) if k <= S * 0.98] if q else []
        n = 0
        if below:
            K = below[-1]; b, a = q[K]; v = piv((b + a) / 2, S, K, yrs(day, e)) or 0.6
            ds_ = pdl(S, K, yrs(day, e), v)
            n = max(0, round((-150 - dl) / (-100 * ds_))) if ds_ < -0.01 else 0
            if n: pnl += n * 100 * SELL(b, a) - 0.65 * n; sold += n
        Se = close(e)
        if n: pnl -= n * 100 * max(0, K - Se)
        day = e; last = e
    ql = S2.chain(t, L['e'], last, 'put').get(L['K'])
    end_v = SELL(*ql) if ql else pput(close(last), L['K'], max(1 / 365, yrs(last, L['e'])), ivL)
    pnl += 10 * 100 * end_v - 6.5
    return dict(t=t, day=ev['day'], pct=pnl / (S0 * 1000) * 100, pnl=pnl, sold=sold, long=f"{L['e']} {L['K']:g}", end=last, move=close(last) / S0 - 1)

if __name__ == '__main__':
    E = json.load(open(os.path.join(S2.DATA, 'events_adj.json')))
    with ThreadPoolExecutor(6) as ex: list(ex.map(lambda ev: run(ev, 'mid'), E))
    json.dump(S2.CACHE, open(S2.CP, 'w'))
    out = {}
    for fill in ('mid', 'bid'):
        rs = [r for r in (run(ev, fill) for ev in E) if r]; ps = sorted(r['pct'] for r in rs)
        out[fill] = dict(n=len(rs), avg=st.mean(ps), med=st.median(ps), win=sum(1 for p in ps if p > 0) / len(ps) * 100, p10=ps[len(ps) // 10], worst=ps[0], best=ps[-1],
                         events=[(r['t'], r['day'], round(r['pct'], 2), round(r['move'] * 100, 1), r['sold']) for r in rs])
        print(f"C {fill}: events {len(rs)} avg {out[fill]['avg']:+.2f}% median {out[fill]['med']:+.2f}% win {out[fill]['win']:.0f}% bad1in10 {out[fill]['p10']:+.2f}% worst {ps[0]:+.2f}% best {ps[-1]:+.2f}% | avg puts sold {st.mean(r['sold'] for r in rs):.1f}")
        mv = [(r['move'], r['pct']) for r in rs]
        for lo, hi, lab in ((-1, -0.05, 'kept falling 5%+'), (-0.05, 0.05, 'stayed within 5%'), (0.05, 9, 'bounced 5%+')):
            g = [p for m, p in mv if lo <= m < hi]
            if g: print(f"   {lab:18s} n {len(g):3d} avg {st.mean(g):+.2f}% win {sum(1 for p in g if p > 0)/len(g)*100:.0f}%")
    json.dump(out, open(os.path.join(S2.DATA, 'stepC.json'), 'w'), indent=1)
