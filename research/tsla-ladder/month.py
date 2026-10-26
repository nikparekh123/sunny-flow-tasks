"""One-month day-by-day view of the three-expiry ladder (Nik, 18 Oct 2026). Model research,
not advice. Same rules as sim.py, started fresh at the close on 1 Sep 2026 (selling the next
three Mon/Wed/Fri expiries) and marked at EVERY close to 30 Sep 2026 (trades still only on Mon/Wed/Fri expiry days): shares at the close, sold and
bought calls at their real end-of-day mid (Theta). Fills at mid, $0.65 a contract.
Usage: python3 month.py"""
import json, math, os
from sim import theta, bs, iv_of, Longs, ZK, LONG, yrs, D, DATA
START, END = '2026-09-01', '2026-09-30'   # Nik: the month of September
TICKERS = os.environ.get('TICKERS', 'TSLA,SPY,QQQ,IWM').split(',')
MODES = ['none', '6m', '1m', '1matm']

class Marks(Longs):
    """Daily quotes for one contract (sold or bought), cached with the long-call cache."""
    def mark(s, e, K, a, day, S, iv):
        q = s.hist(e, K, a).get(day)
        if q: return sum(q) / 2
        return bs(S, K, yrs(day, e), iv)[0] if day < e else max(0, S - K)

def run(t, mode):
    d = json.load(open(os.path.join(DATA, f'{t}.json'))); C = d['closes']
    days = [x for x in sorted(C) if START <= x <= END]
    sl = [s for s, _ in d['slots']]; wd = dict((s, w) for s, w in d['slots'])
    exps = d['exps']; M = Marks(t)
    cash = 0.0; shorts = {}; longs = []; rows = []; prev = 0.0
    for day in days:
        S = C[day]
        if day == days[0]: cash -= 1000 * S
        note = []
        setup = day == days[0]
        if setup or day in sl:
            upcoming = [x for x in sl if x > day]
            if day in shorts:
                s = shorts.pop(day); x = max(0, S - s['K']) * 1000; cash -= x
                if S > s['K']: cash -= 5; note.append(f"{s['K']:g} assigned")
                else: note.append(f"{s['K']:g} expired")
            for g in [g for g in longs if (D(g['e']) - D(day)).days <= g['roll']]:
                px = M.mark(g['e'], g['K'], g['d'], day, S, g['iv']); cash += px * 100 * g['n'] - 0.65 * g['n']; longs.remove(g)
                note.append(f"rolled {g['n']} long")
            for e in (upcoming[:3] if setup else upcoming[2:3]):
                key = f'{day}|{e}'
                q = {float(k): v for k, v in d['q'].get(key, {}).items() if v[0] > 0}
                if not q:
                    q = {float(k): v for k, v in M.chain(e, day).items()}
                if not q: continue
                T = yrs(day, e); ks = sorted(q); ka = min(ks, key=lambda k: abs(k - S))
                iv = iv_of(sum(q[ka]) / 2, S, ka, T) or 0.3; sd = S * iv * math.sqrt(T); z = ZK[wd[e]]
                K = min(ks, key=lambda k: abs(k - (S + z * sd)))
                if z < 0 and K >= S: K = max([k for k in ks if k < S], default=K)
                if z > 0 and K <= S: K = min([k for k in ks if k > S], default=K)
                p = sum(q[K]) / 2; cash += p * 1000 - 6.5
                shorts[e] = dict(K=K, d=day, iv=iv_of(p, S, K, T) or iv); note.append(f"sold {K:g} {e[5:]}")
            def nd():
                n = 1000.0
                for e, s in shorts.items(): n -= 1000 * bs(S, s['K'], yrs(day, e), s['iv'])[1]
                for g in longs:
                    px = M.mark(g['e'], g['K'], g['d'], day, S, g['iv']); T = yrs(day, g['e'])
                    n += g['n'] * 100 * bs(S, g['K'], T, iv_of(px, S, g['K'], T) or g['iv'])[1]
                return n
            net = nd()
            if mode != 'none' and (net < 500 or setup):
                tgt, kx, rl = LONG[mode]
                cand = sorted([x for x in exps if (D(x) - D(day)).days >= tgt * 0.75], key=lambda x: abs((D(x) - D(day)).days - tgt))
                e, ch = None, {}
                for e in cand[:6]:                      # the nearest expiry that traded that day
                    ch = M.chain(e, day)
                    if ch: break
                if ch:
                    K = min(ch, key=lambda k: abs(k - S * kx)); T = yrs(day, e)
                    v = iv_of(sum(ch[K]) / 2, S, K, T) or 0.4; n = math.ceil((1000 - net) / (100 * bs(S, K, T, v)[1]))
                    if n > 0:
                        px = sum(ch[K]) / 2; cash -= px * 100 * n + 0.65 * n
                        longs.append(dict(e=e, K=K, n=n, d=day, iv=v, roll=rl)); note.append(f"bought {n} x {K:g} {e[2:7]}")
        sv = sum(1000 * Marks.mark(M, e, s['K'], s['d'], day, S, s['iv']) for e, s in shorts.items())
        lv = sum(100 * g['n'] * M.mark(g['e'], g['K'], g['d'], day, S, g['iv']) for g in longs)
        eqv = cash + 1000 * S + lv - sv
        net = 1000.0 - sum(1000 * bs(S, s['K'], yrs(day, e), s['iv'])[1] for e, s in shorts.items() if day < e) \
              + sum(g['n'] * 100 * bs(S, g['K'], yrs(day, g['e']), g['iv'])[1] for g in longs)
        rows.append(dict(day=day, S=S, pnl=eqv - prev, cum=eqv, delta=net, note='; '.join(note)))
        prev = eqv
    M.save()
    return rows

if __name__ == '__main__':
    out = {}
    for t in TICKERS:
        out[t] = {m: run(t, m) for m in MODES}
        r0 = out[t]['none']
        print(f"\n{t}  (daily P&L $; cumulative at the end)")
        print(f"{'day':10s} {'price':>8s} " + ' '.join(f"{m:>9s}" for m in MODES))
        for k in range(len(r0)):
            print(f"{r0[k]['day']:10s} {r0[k]['S']:8.2f} " + ' '.join(f"{out[t][m][k]['pnl']:9,.0f}" for m in MODES))
        print(f"{'total':10s} {'':8s} " + ' '.join(f"{out[t][m][-1]['cum']:9,.0f}" for m in MODES))
    json.dump(out, open(os.path.join(DATA, f"month_{'_'.join(TICKERS)}.json"), 'w'), indent=1)
