# -*- coding: utf-8 -*-
"""Nik's loop, written out step by step.

  1. wait for two red days
  2. sell puts at the nearest strike, one week out
  3. if assigned, basis = strike - premium
  4. sell calls just above THAT BASIS (not above spot), one week out
  5. repeat

The part that is different from everything I tested before: the call strike is set off
the basis. You do not need the stock back at 220 to win, you need it above 208.
"""
import math
from statistics import NormalDist
ND=NormalDist(); R=0.045; IV=0.45
def bs(S,K,d,put):
    T=d/365; v=IV; sq=v*math.sqrt(T)
    a=(math.log(S/K)+(R+v*v/2)*T)/sq
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a), ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq), ND.cdf(a)
snap=lambda x: round(x/2.5)*2.5          # NVDA strikes are $2.50 apart near 220

print("="*70)
print("THE LOOP, ONE PASS THROUGH".center(70))
print("="*70)
S0=220.0; drop=0.04; S1=S0*(1-drop)
print("\nSTEP 1  Two red days")
print("   NVDA was          %8.2f"%S0)
print("   Two red days, -4%% %8.2f   (down $%.2f)"%(S1,S0-S1))

K=snap(S1)
p,dl=bs(S1,K,7,True)
print("\nSTEP 2  Sell 10 puts, nearest strike, next Friday")
print("   strike            %8.2f"%K)
print("   premium           %8.2f  per share"%p)
print("   you collect       %8s  (10 contracts)"%("$"+format(round(p*100*10),",")))
print("   chance assigned   %8.0f%%"%(100*dl))

basis=K-p
print("\nSTEP 3  If assigned you own 1,000 shares")
print("   you pay           %8.2f"%K)
print("   less premium      %8.2f"%p)
print("   YOUR BASIS        %8.2f   <- %.1f%% below where NVDA was a week ago"%(basis,100*(1-basis/S0)))

for lab,ck in (("just above basis", snap(basis*1.01)),):
    c,cdl=bs(basis,ck,7,False)
    print("\nSTEP 4  Sell 5 calls %s, next Friday"%lab)
    print("   strike            %8.2f   (basis %.2f + 1%%)"%(ck,basis))
    print("   premium           %8.2f  per share"%c)
    print("   you collect       %8s  (5 contracts)"%("$"+format(round(c*100*5),",")))
    print("   chance called     %8.0f%%"%(100*cdl))
    print("\nSTEP 5  What each outcome pays you")
    print("   called away at %.2f : %8s  (%.2f - %.2f on 500 shares, plus both premiums)"%(
        ck, "$"+format(round((ck-basis)*500 + p*1000 + c*500),","), ck, basis))
    print("   not called          : %8s  (both premiums, you keep all 1,000 shares)"%(
        "$"+format(round(p*1000+c*500),",")))
    print("   you still hold      : %s shares at %.2f"%("500-1,000",basis))
print("\n   Repeat next time NVDA is red twice.")
