import json,urllib.request
K="sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U="https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/stock-history"
r=urllib.request.Request(U,data=json.dumps({"ticker":"TLT","from":"2002-01-01","to":"2026-08-12"}).encode(),
  headers={"apikey":K,"Authorization":"Bearer "+K,"content-type":"application/json"})
d=json.loads(urllib.request.urlopen(r,timeout=180).read())
json.dump(d,open("tlt.json","w")); b=d.get("bars") or []
print("TLT bars",len(b),b[0]["d"],"->",b[-1]["d"])
A="https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/auctions_query?fields=auction_date,security_term,bid_to_cover_ratio,indirect_bidder_accepted,total_accepted&filter=security_type:eq:Bond,security_term:eq:30-Year,bid_to_cover_ratio:gt:0&sort=-auction_date&page%5Bsize%5D=300"
a=json.loads(urllib.request.urlopen(A,timeout=90).read())["data"]
json.dump(a,open("auctions.json","w")); print("auctions",len(a))
