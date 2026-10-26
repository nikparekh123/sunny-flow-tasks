# -*- coding: utf-8 -*-
"""Nik's income sleeve: hold a block, sell an ATM call AND an ATM put every week, roll.

His example: TLT at 82, collect 35c on the call and 35c on the put, so 70c a week and
the average walks down to 81.30. Up -> called away. Down -> put more shares. Sideways ->
keep both and repeat.

Tested against the alternatives on the same block and the same money.
"""
import json, math, datetime, statistics as st
from statistics import NormalDist
ND=NormalDist(); R=0.045; START=82.0; BLOCK=25000
b=json.load(open("../nvda-tenor/tlt_long.json"))["bars"]
D=[x["d"] for x in b]; RAW=[x["c"] for x in b]; N=len(D)
WD=[datetime.date.fromisoformat(x).weekday() for x in D]
ret=[RAW[i+1]/RAW[i]-1 for i in range(N-1)]; lr=[math.log(1+x) for x in ret]
def bs(S,K,T,v,put):
    if T<=0: return (max(0.0,K-S) if put else max(0.0,S-K))
    sq=v*math.sqrt(T); a=(math.log(S/K)+(R+v*v/2)*T)/sq
    if put: return K*math.exp(-R*T)*ND.cdf(-(a-sq))-S*ND.cdf(-a)
    return S*ND.cdf(a)-K*math.exp(-R*T)*ND.cdf(a-sq)

def run(lo,hi,callCt,putCt):
    P=[START]*(hi-lo+1)
    for k in range(1,hi-lo+1): P[k]=P[k-1]*(1+ret[lo+k-1])
    px=lambda i:P[i-lo]
    def vol(i):
        w=lr[max(0,i-63):i]
        return max(0.06, st.pstdev(w)*math.sqrt(252)) if len(w)>10 else 0.14
    def nxt(i):
        j=i+1
        while j<N and not (WD[j]==4 and (datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days>=5): j+=1
        return j if j<N else None
    sh=BLOCK; cost=BLOCK*START; prem=0.0; oC=[]; oP=[]; called=0; putto=0
    for i in range(lo,hi):
        for L in list(oC):
            if L[0]<=i:
                if px(L[0])>L[1]:
                    bas=cost/sh if sh else 0
                    sh-=L[2]*100; cost-=bas*L[2]*100; prem+=(L[1]-bas)*L[2]*100; called+=L[2]*100
                oC.remove(L)
        for L in list(oP):
            if L[0]<=i:
                if px(L[0])<L[1]: sh+=L[2]*100; cost+=L[1]*L[2]*100; putto+=L[2]*100
                oP.remove(L)
        if WD[i]!=4: continue
        j=nxt(i)
        if not j or j>=hi: continue
        S=px(i); K=round(S*2)/2; T=(datetime.date.fromisoformat(D[j])-datetime.date.fromisoformat(D[i])).days/365; v=vol(i)
        if callCt:
            ct=min(callCt, max(0, sh//100 - sum(l[2] for l in oC)))
            if ct>0: prem+=bs(S,K,T,v,False)*100*ct; oC.append((j,K,ct))
        if putCt:
            ct=max(0, putCt - sum(l[2] for l in oP))
            if ct>0: prem+=bs(S,K,T,v,True)*100*ct; oP.append((j,K,ct))
    end=px(hi-1)
    return prem, sh, (cost/sh if sh else 0), end, called, putto

WIN=252
print("A 25,000 share TLT block. One year per run, %d runs, TLT started at 82.\n"%len(range(70,N-WIN-40,25)))
print("%-32s %12s %12s %11s %12s"%("what you sell each week","premium/yr","end shares","avg cost","net /yr"))
print("-"*82)
for lab,c,p in (("nothing, just hold",0,0),
                ("250 ATM calls only",250,0),
                ("250 ATM puts only",0,250),
                ("250 calls + 250 puts (yours)",250,250),
                ("100 calls + 100 puts",100,100),
                ("50 calls + 50 puts",50,50)):
    PR=[];SH=[];BA=[];NET=[]
    for s0 in range(70,N-WIN-40,25):
        pr,sh,bas,end,ca,pu=run(s0,s0+WIN,c,p)
        PR.append(pr);SH.append(sh);BA.append(bas)
        NET.append(pr + (end - bas) * sh)
    m=lambda X:st.mean(X)
    print("%-32s %12s %12s %11s %12s"%(lab,
        "$"+format(round(m(PR)),","), format(round(m(SH)),","),
        "$%.2f"%m(BA), "$"+format(round(m(NET)),",")))
print()
print("  premium/yr counts option premium AND the gain booked when calls are assigned.")
print("  net/yr is that plus the unrealised move on whatever block you still hold.")
