# -*- coding: utf-8 -*-
"""The keep model, delta terms. See docs/PLANNER_KEEP_MODEL.md."""
import math
def clamp(v,a,b): return max(a,min(b,v))
def ncdf(x): return 0.5*(1+math.erf(x/math.sqrt(2)))
def bsdelta(S,K,T,v,r=0.045): return ncdf((math.log(S/K)+(r+v*v/2)*T)/(v*math.sqrt(T)))

# Baseline is now ONE number per event state. Price state left the baseline entirely:
# Nik's three pre-earnings answers (32/50/20% of shares) all landed on ~77% of delta
# because he varied share count and strike in opposite directions. The share number was
# the route; delta is the destination.
BASE_KEEP = {'PRE':77, 'CLEAR':68, 'POST':59}
# Price state lives HERE, which is where it was doing its real work all along.
BASE_OTM  = {('PRE','down'):1.5,('PRE','flat'):0.0,('PRE','up'):2.5,
             ('CLEAR','down'):1.5,('CLEAR','flat'):1.5,('CLEAR','up'):2.0,
             ('POST','down'):0.5,('POST','flat'):1.5,('POST','up'):2.0}
RSI_EXPECT={'down':30,'flat':50,'up':70}; GRADE_EXPECT={'down':2,'flat':5,'up':9}
REL_EXPECT={'down':-8,'flat':0,'up':12}
K = 1/2.8   # share-points -> delta-points

def plan(ev,px,spot,shares,days,iv,ivPct,grade,sessSince,nvda,smh,smhNow,smhNorm,rsi,macro,peer,step=2.5):
    m={}
    m['iv']     = clamp(-4*(ivPct-50)/50,-4,4)*K
    decay       = clamp((60-sessSince)/50,0,1)
    m['grade']  = (clamp((grade-GRADE_EXPECT[px])*2.5*decay,-10,10) if grade is not None else 0)*K
    m['rel']    = clamp(((nvda-smh)-REL_EXPECT[px])*0.4,-5,5)*K
    m['sector'] = clamp((smhNow-smhNorm)*0.5,-4,4)*K
    m['rsi']    = clamp((rsi-RSI_EXPECT[px])*0.15,-4,4)*K
    m['macro']  = (4 if macro=='inside' else 2 if macro=='near' else 0)*K
    m['peer']   = (3 if peer=='inside' else 1.5 if peer=='near' else 0)*K
    raw=sum(m.values()); agg=clamp(raw,-5,5)
    keep = clamp(BASE_KEEP[ev]+agg, 55, 95)

    # distance: sqrt-time scaled so the same target holds its delta across expiry lengths,
    # then nudged by IV richness. A 1.5% strike is much further out on a 2-day than a 4-day.
    otm = clamp(BASE_OTM[(ev,px)]*math.sqrt(days/4) + clamp((ivPct-50)/50,-0.5,1.0)*math.sqrt(days/4), 0, 4)
    strike = round(spot*(1+otm/100)/step)*step
    dl = bsdelta(spot, strike, days/365, iv)

    want   = (100-keep)/100*shares            # delta to sell
    ct     = want/(dl*100)
    maxct  = shares//100
    capped = ct > maxct
    ct     = min(round(ct), maxct)
    got    = (shares - ct*dl*100)/shares*100  # delta actually kept
    return dict(keep=keep, raw=raw, otm=otm, strike=strike, dl=dl*100, ct=ct,
                got=got, capped=capped, m=m)

S=[ # name             ev     px      spot  shr   iv  ivP  gr  ss  nvda smh  sN sNm  rsi  macro    peer
 ("PRE  down 15%",   'PRE','down',   190,7500, 2,.55, 90,  6, 55, -15,-12,  1, 6, 28, None,None),
 ("PRE  flat",       'PRE','flat', 223.8,7500, 2,.52, 85,  6, 55,   1,  2,  6, 6, 50, None,None),
 ("PRE  up 20%",     'PRE','up',     268,7500, 2,.54, 88,  6, 55,  20,  8,  9, 6, 74, None,None),
 ("POST 190  g2",    'POST','down',  190,7500, 2,.48, 35,  2,  2, -15, -4,  2, 6, 25, None,None),
 ("POST 224  g5",    'POST','flat',223.8,7500, 2,.36, 30,  5,  2,   0,  1,  6, 6, 48, None,None),
 ("POST 275  g9",    'POST','up',    275,1000, 2,.38, 38,  9,  2,  23,  6,  9, 6, 78, None,None),
 ("TODAY  clear",    'CLEAR','flat',223.8,7500, 2,.40, 51,None,999,  9,  0,  7, 6,44.5,'inside',None),
 ("POST 190  g8 !",  'POST','down',  190,7500, 2,.48, 35,  8,  2, -15, -4,  2, 6, 25, None,None),
 ("POST 275  g4 !",  'POST','up',    275,1000, 2,.38, 38,  4,  2,  23,  6,  9, 6, 78, None,None)]

print(f"{'scenario':16}{'keep':>6}{'got':>6}{'OTM':>6}{'strike':>8}{'Δ':>5}{'ct':>5}{'of':>4}   modifiers")
for row in S:
    n=row[0]; r=plan(*row[1:])
    top="  ".join(f"{a}{v:+.1f}" for a,v in sorted(r['m'].items(),key=lambda x:-abs(x[1])) if abs(v)>=0.3) or "none"
    flag=" CAPPED" if r['capped'] else ""
    print(f"{n:16}{r['keep']:>5.0f}%{r['got']:>5.0f}%{r['otm']:>5.2f}%{r['strike']:>8.1f}{r['dl']:>5.0f}{r['ct']:>5}{row[4]//100:>4}   raw{r['raw']:+.1f} | {top}{flag}")
