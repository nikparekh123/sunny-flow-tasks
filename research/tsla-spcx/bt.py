"""LEAP + short-call overlay, on real end-of-day option quotes (Theta).

Per 10 LEAP contracts. Each event sells n = coverage x 10 calls at the close of
the sell date (fill: mid less a quarter of the spread, $0.65 a contract) and
settles them at the expiry close at intrinsic (bought back if in the money,
never assigned). Strike rules: atm (first strike at or above spot), otmN (first
at or above spot x (1+N%)), d30 (delta nearest 0.30 from each strike's own IV),
sd1 (spot x e^(ATM IV x sqrt(T))), and splits that sell 3 of the 10 at the money
and the rest by another rule.
"""
import json, math, datetime
from lib import bs_call, bs_delta, iv_from, D

N_LEAP = 10
FEE = 0.65

def load(t):
    cl = {b["d"]: b["c"] for b in json.load(open(f"{t.lower()}.json"))["bars"]}
    ch = json.load(open(f"{t.lower()}_chains.json"))
    return cl, ch

def T_of(s, e): return max(1, (D(e) - D(s)).days) / 365.0

def events(cl, ch, freq, fr, to):
    """(sell, expiry) pairs. weekly: Thu/Fri expiries; tri: every expiry."""
    xs = [e for e in ch["all"] if e in cl]
    if freq == "weekly": xs = [e for e in xs if D(e).weekday() >= 3]
    out = []
    for a, b in zip(xs, xs[1:]):
        if fr <= a and b <= to: out.append((a, b))
    return out

def quotes(ch, e, s):
    q = ch["chains"].get(e, {}).get(s)
    if not q: return None
    return sorted(((float(k), b, a) for k, (b, a) in q.items() if a > 0), key=lambda x: x[0])

def first_at_or_above(q, x):
    for k, b, a in q:
        if k >= x - 1e-9: return (k, b, a)
    return None

def pick(rule, q, S, T):
    if rule == "atm": return first_at_or_above(q, S)
    if rule.startswith("otm"): return first_at_or_above(q, S * (1 + float(rule[3:]) / 100))
    atm = first_at_or_above(q, S)
    if not atm: return None
    iv_atm = iv_from((atm[1] + atm[2]) / 2, S, atm[0], T)
    if rule == "sd1":
        if not iv_atm: return None
        return first_at_or_above(q, S * math.exp(iv_atm * math.sqrt(T)))
    if rule == "d30":
        best = None
        for k, b, a in q:
            if k < S: continue
            v = iv_from((b + a) / 2, S, k, T)
            if not v: continue
            d = bs_delta(S, k, T, v)
            if best is None or abs(d - 0.30) < abs(best[0] - 0.30): best = (d, (k, b, a))
        return best[1] if best else None
    raise ValueError(rule)

def legs_for(rule, cov):
    """[(rule, n)] for a coverage on 10 LEAPs; splits: 3 ATM + the rest."""
    n = round(cov * N_LEAP)
    if rule.startswith("split_"):
        other = rule[len("split_"):]
        a = min(3, n)
        return [("atm", a)] + ([(other, n - a)] if n - a > 0 else [])
    return [(rule, n)]

def run_calls(cl, ch, freq, rule, cov, fr, to):
    rows = []
    for s, e in events(cl, ch, freq, fr, to):
        q = quotes(ch, e, s)
        if not q or s not in cl or e not in cl: continue
        S, Se, T = cl[s], cl[e], T_of(s, e)
        pl = 0.0; credit = 0.0; ok = True
        for r, n in legs_for(rule, cov):
            if n == 0: continue
            leg = pick(r, q, S, T)
            if not leg: ok = False; break
            k, b, a = leg
            fill = (b + a) / 2 - 0.25 * (a - b)
            c = fill * 100 * n - FEE * n
            paid = max(0.0, Se - k) * 100 * n + (FEE * n if Se > k else 0)
            credit += c; pl += c - paid
        if ok: rows.append({"s": s, "e": e, "S": S, "Se": Se, "credit": credit, "pl": pl})
    return rows
