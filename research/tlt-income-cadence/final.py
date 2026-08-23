src=open("forward4.py").read().split('def usd(')[0]; ns={}; exec(src,ns)
run,k_near,k_above=ns["run"],ns["k_near"],ns["k_above"]
BLOCK=10000; COST0=82.48
def usd(x): return ("-$" if x<-0.5 else "$")+"{:,.0f}".format(abs(x))
print("TLT INCOME, 24 Aug -> 24 Dec 2026.  Start 10,000 shares at $82.48, spot $82.05.")
print("Calls WEEKLY on shares held, struck at the next strike ABOVE spot.")
print("100 puts each week at the money, one expiry further out than the call.")
print("Floor 200 ATM four-month puts (shares/100 + puts sold). Spread 1c a leg.")
print("Let everything exercise, never buy back. Median of 800 paths.\n")
print("%5s %11s %8s %11s %11s %11s %9s %11s"%("TLT","credit","costs","floor net","share P&L","TOTAL","shares","vs holding"))
rows=[]
for term in range(78,86):
    r=run(term,5,1,k_above,paths=800)
    hold=BLOCK*(term-COST0); rows.append((term,r,hold))
    print("%5d %11s %8s %11s %11s %11s %9s %11s"%(term,usd(r["credit"]),usd(r["cost"]),
      usd(r["floor"]),usd(r["share"]),usd(r["tot"]),"{:,.0f}".format(r["sh"]),usd(r["tot"]-hold)))
avg=sum(r["tot"] for _,r,_ in rows)/len(rows)
print("\naverage across the range: %s   (holding alone averages %s)"%(
  usd(avg),usd(sum(h for _,_,h in rows)/len(rows))))
print("\nSpread sensitivity of the cadence choice (avg TOTAL across 78-85):")
for sp in (0.0,0.01,0.02):
    w=sum(run(t,5,1,k_above,paths=300,spread=sp)["tot"] for t in range(78,86))/8
    e=sum(run(t,2,1,k_above,paths=300,spread=sp)["tot"] for t in range(78,86))/8
    print("  %.0fc a leg   weekly %11s    every-expiry %11s   %s"%(sp*100,usd(w),usd(e),
          "weekly" if w>e else "every-expiry"))
