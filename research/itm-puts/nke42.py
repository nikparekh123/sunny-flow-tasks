from block import *
t='NKE'; S0=SPOT[t]
SH=['flat','up 15%','rip 25% in 3m','jump 30% in 1m','down 15%','crash 30% in 2m','V: -20% then back','no view']
_,_,b0=run(t,'flat',B(),n=4); m0=min(shock(b0,t,-0.15,0.05),shock(b0,t,0.15,-0.03))
for name,p in [('25 x 42.5P, sell 12', B(long_n=25, itm=42.5/S0-1, short_n=12))]:
    r=summary(t,p); _,_,d0=run(t,'flat',p,n=4); mg=min(shock(d0,t,-0.15,0.05),shock(d0,t,0.15,-0.03))
    buy=[x for x in d0 if not (x[4]=='P' and x[0]<0)]; mgb=min(shock(buy,t,-0.15,0.05),shock(buy,t,0.15,-0.03))
    print(f"{name:30}"+''.join(f"{r[s]/1000:9.1f}" for s in SH)+f"{np.mean([r[s] for s in SH])/1000:7.1f}{(mg-m0)/1000:8.1f}{(mgb-m0)/1000:8.1f}{r['delta0']:7.0f}{r['negdays_nv']:6.2f}")
