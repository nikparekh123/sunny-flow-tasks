import statistics,importlib.util,sys
spec=importlib.util.spec_from_file_location("f4","forward4.py")
# reuse the engine without re-printing
src=open("forward4.py").read().split('def usd(')[0]
ns={}; exec(src,ns)
run,k_near,k_above=ns["run"],ns["k_near"],ns["k_above"]
BLOCK=10000; COST0=82.48
def usd(x): return ("-$" if x<-0.5 else "$")+"{:,.0f}".format(abs(x))
PR=range(78,86)
def profile(call_td,gap,fn,label):
    rows=[run(t,call_td,gap,fn,paths=400) for t in PR]
    tot=[r["tot"] for r in rows]
    vs=[r["tot"]-BLOCK*(t-COST0) for r,t in zip(rows,PR)]
    sh=[r["sh"] for r in rows]
    print("%-42s %11s %11s %11s %11s %9s"%(label,usd(statistics.mean(tot)),usd(min(tot)),
          usd(max(tot)),usd(statistics.mean(vs)),"{:,.0f}".format(statistics.median(sh))))
print("Averaged across TLT 78-85. 400 paths each.\n")
print("%-42s %11s %11s %11s %11s %9s"%("variant","avg TOTAL","worst","best","avg vs hold","med shares"))
print("-"*100)
for gap,gl in ((0,"put SAME expiry"),(1,"put NEXT expiry")):
    for fn,fl in ((k_near,"call nearest"),(k_above,"call next-above")):
        profile(5,gap,fn,"WEEKLY   %-16s %s"%(gl,fl))
print()
for gap,gl in ((0,"put SAME expiry"),(1,"put NEXT expiry")):
    for fn,fl in ((k_near,"call nearest"),(k_above,"call next-above")):
        profile(2,gap,fn,"EVERY-EXP %-15s %s"%(gl,fl))
