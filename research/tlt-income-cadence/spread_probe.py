import json,urllib.request,datetime
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/option-chain"
def call(p):
    rq=urllib.request.Request(U,data=json.dumps(p).encode(),
      headers={"Authorization":"Bearer "+K,"apikey":K,"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(rq,timeout=120))
# next few TLT expiries
for exp in ["2026-08-24","2026-08-26","2026-08-28","2026-09-04","2026-09-18"]:
    try:
        r=call({"ticker":"TLT","expiry":exp,"contract_type":"put","window_pct":3})
    except Exception as e:
        print(exp,"ERR",str(e)[:80]); continue
    ks=r.get("strikes") or []
    spot=r.get("spot")
    if not ks: print(exp,"no strikes"); continue
    atm=min(ks,key=lambda x:abs(x["strike"]-(spot or 82)))
    print("%s spot %s  ATM %s  keys=%s"%(exp,spot,atm.get("strike"),list(atm.keys())))
