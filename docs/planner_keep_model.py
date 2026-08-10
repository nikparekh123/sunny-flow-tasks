# -*- coding: utf-8 -*-
# Baseline v2. Every modifier measures DEVIATION from what is already implied — by the
# cell (grade, relative strength, RSI) or by the recent norm (sector, IV). An absolute
# reading double-counts: "SMH above its 200-day" is true most weeks of a bull market,
# so scored raw it quietly added 2-4 points of keep to every single reading.
def clamp(v,a,b): return max(a,min(b,v))

BASE_KEEP = {('PRE','down'):32,('PRE','flat'):50,('PRE','up'):20,
             ('CLEAR','down'):20,('CLEAR','flat'):20,('CLEAR','up'):20,
             ('POST','down'):18,('POST','flat'):5,('POST','up'):5}
BASE_OTM  = {('PRE','down'):1.5,('PRE','flat'):0.0,('PRE','up'):2.5,
             ('CLEAR','down'):1.5,('CLEAR','flat'):1.5,('CLEAR','up'):2.0,
             ('POST','down'):0.5,('POST','flat'):1.5,('POST','up'):2.0}
RSI_EXPECT   = {'down':30,'flat':50,'up':70}
GRADE_EXPECT = {'down':2,'flat':5,'up':9}
REL_EXPECT   = {'down':-8,'flat':0,'up':12}

def plan(ev,px,ivPct,grade,sessSince,nvda,smh,smhNow,smhNorm,rsi,macro,peer,floorGap):
    m = {}
    m['iv']     = clamp(-4*(ivPct-50)/50, -4, 4)
    decay       = clamp((60-sessSince)/50, 0, 1)
    m['grade']  = clamp((grade-GRADE_EXPECT[px])*2.5*decay, -10, 10) if grade is not None else 0
    m['rel']    = clamp(((nvda-smh)-REL_EXPECT[px])*0.4, -5, 5)
    # smhNow/smhNorm: where SMH sits vs its 200-day TODAY, against where it has typically
    # sat. A sector that is always 8% above its average is not a signal; one that has
    # just fallen from 8% to 1% is.
    m['sector'] = clamp((smhNow-smhNorm)*0.5, -4, 4)
    m['rsi']    = clamp((rsi-RSI_EXPECT[px])*0.15, -4, 4)
    m['macro']  = 4 if macro=='inside' else 2 if macro=='near' else 0
    m['peer']   = 3 if peer=='inside' else 1.5 if peer=='near' else 0
    m['floor']  = clamp(-(floorGap-3)*0.6, -3, 3)
    raw=sum(m.values()); agg=clamp(raw,-15,15)
    keep = clamp(BASE_KEEP[(ev,px)]+agg, 5, 55)
    otm  = clamp(BASE_OTM[(ev,px)]+clamp((ivPct-50)/50,-0.5,1.0), 0, 4)
    return keep, otm, raw, m

#      name              ev      px      iv  gr  ss  nvda smh  smhNow smhNorm rsi  macro     peer  floor  spot   you
S = [("PRE  down 15%",  'PRE','down',   90,  6, 55, -15, -12,   1,     6,   28, None,None, 1.0,  190,  "30-35%"),
     ("PRE  flat",      'PRE','flat',   85,  6, 55,   1,   2,   6,     6,   50, None,None, 3.0,  223.8,"50%"),
     ("PRE  up 20%",    'PRE','up',     88,  6, 55,  20,   8,   9,     6,   74, None,None, 8.0,  268,  "20%"),
     ("POST 190  g2",   'POST','down',  35,  2,  2, -15,  -4,   2,     6,   25, None,None,-15.8, 190,  "15-20%"),
     ("POST 224  g5",   'POST','flat',  30,  5,  2,   0,   1,   6,     6,   48, None,None, 2.0,  223.8,"5%"),
     ("POST 275  g9",   'POST','up',    38,  9,  2,  23,   6,   9,     6,   78, None,None,20.0,  275,  "5%"),
     ("TODAY (clear)",  'CLEAR','flat', 51,None,999,  9,   0,   7,     6, 44.5,'inside',None,1.7, 223.8,"—"),
     ("POST 190  g8 !", 'POST','down',  35,  8,  2, -15,  -4,   2,     6,   25, None,None,-15.8, 190,  "divergent"),
     ("POST 275  g4 !", 'POST','up',    38,  4,  2,  23,   6,   9,     6,   78, None,None,20.0,  275,  "divergent")]

print(f"{'scenario':16}{'keep':>6}{'you':>11}{'OTM':>7}{'strike':>9}  {'sell':>5}   modifiers")
for n,ev,px,iv,g,ss,nv,sm,sn,snm,r,mc,pr,fg,sp,you in S:
    k,otm,raw,m = plan(ev,px,iv,g,ss,nv,sm,sn,snm,r,mc,pr,fg)
    strike = round(sp*(1+otm/100)/2.5)*2.5
    top = "  ".join(f"{a}{v:+.1f}" for a,v in sorted(m.items(),key=lambda x:-abs(x[1])) if abs(v)>=0.5) or "none"
    print(f"{n:16}{k:>5.0f}%{you:>11}{otm:>6.1f}%{strike:>9.1f}  {100-k:>4.0f}%   raw{raw:+.1f} | {top}")
