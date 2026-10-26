"""Two tests on NKE's real year (Nik, 17 Oct 2026), rolled every Friday, fills at mid,
$0.65 a contract, LEAPs and hedge left out (same in every row):
 1. TWO-WEEK LADDER: always 30 calls expiring this Friday and 30 the Friday after;
    each Friday the expiring 30 roll into new two-week calls at 0.6 or 0.8 sigma
    (sigma of the two-week window). First Friday: 30 one-week at 0.6 sigma + 30
    two-week. The two-week tranche sold 9 Oct 2026 (expires 23 Oct) is still open
    and left out. Compared with selling all 60 one-week calls at 0.6 / 0.8 sigma.
 2. KEEP 15% FREE: sell 51 of 60 calls (85%), on the playbook + tweaks and today's rule.
Usage: python3 -I ladder_85.py"""
import json, math, os, io, contextlib, runpy
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = os.path.join(HERE, 'data')
buf = io.StringIO()
with contextlib.redirect_stdout(buf): g = runpy.run_path(os.path.join(HERE, 'playbook_replay.py'))
D, settle, iv_of, reads, res = g['D'], g['settle'], g['iv_of'], g['reads'], g['res']
W1 = json.load(open(os.path.join(DATA, 'nke_weeklies.json'))); W2 = json.load(open(os.path.join(DATA, 'nke_2wk.json')))
LAST = '2026-10-16'

def chain(w, sale):
    S = reads(sale)['S']; e = w['expiry']; T = max(1, (D(e) - D(sale)).days) / 365
    CQ = {float(k): (b + a) / 2 for k, (b, a) in w['C'].items() if a > 0}
    katm = min(CQ, key=lambda k: abs(k - S)); v = iv_of(CQ[katm], S, katm, T) or 0.35
    return S, e, CQ, S * v * math.sqrt(T)
def sell(CQ, S, e, K_target, n):
    ks = sorted(k for k in CQ if k >= K_target); K = ks[0] if ks else max(CQ)
    return n * 100 * (CQ[K] - max(0, settle(e) - K)) - 0.65 * n

sales = sorted(W1)
weekly = {}
for z in (0.6, 0.8):
    pnl = []
    for s_ in sales:
        S, e, CQ, sig = chain(W1[s_], s_); pnl.append(sell(CQ, S, e, S + z * sig, 60))
    weekly[z] = pnl
ladder = {}
for z in (0.6, 0.8):
    by_expiry = {}
    S, e, CQ, sig = chain(W1[sales[0]], sales[0])
    by_expiry[e] = by_expiry.get(e, 0) + sell(CQ, S, e, S + 0.6 * sig, 30)
    open_left = 0
    for s_ in sales:
        S, e, CQ, sig = chain(W2[s_], s_)
        if e > LAST: open_left += 1; continue
        by_expiry[e] = by_expiry.get(e, 0) + sell(CQ, S, e, S + z * sig, 30)
    ladder[z] = (by_expiry, open_left)

def line(lab, pnl):
    print(f"  {lab:44s} ${sum(pnl):>9,.0f}  losing weeks {sum(1 for x in pnl if x < 0):2d}  worst ${min(pnl):>8,.0f}")
print('1. TWO-WEEK LADDER vs one-week (calls only, NKE Oct 2025 - Oct 2026):')
line('one-week, all 60 at 0.6 sigma', weekly[0.6]); line('one-week, all 60 at 0.8 sigma', weekly[0.8])
for z in (0.6, 0.8):
    be, ol = ladder[z]; line(f'ladder 30 + 30, two-week at {z} sigma ({ol} tranche open)', list(be.values()))
print('\n2. KEEP 15% FREE (sell 51 of 60), calls + puts:')
for a in ('playbook + tweaks', "today's rule"):
    r = res[a]; full = [x for x in r['weeks']]
    calls_w = []   # scale only the call part
    tot = r['calls'] * 0.85 + r['puts']
    print(f"  {a:26s} all 60: ${r['calls'] + r['puts']:>9,.0f}   51 of 60: ${tot:>9,.0f}   (calls ${r['calls']:,.0f} -> ${r['calls'] * 0.85:,.0f})")
fw = json.load(open(os.path.join(DATA, 'nke_forward_fade.json')))['sell all 60']
print('  forward test, calls part of selling all 60 -> what keeping 15% free changes, by scenario ($K):')
print('   ', {s: round(-0.15 * v['calls'] / 1000, 1) for s, v in fw.items()})
