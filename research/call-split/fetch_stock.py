import json, urllib.request
K = "sb_publishable_DFe2lqBrxeSbwJqGWWtRLg_e0Neyh-g"
U = "https://ziwoutsnuywjnsyfbzsp.supabase.co/functions/v1/stock-history"
for t in ["NKE", "BABA", "NFLX", "LULU", "FIS", "PEP", "UBER", "KR"]:
    r = urllib.request.Request(U, data=json.dumps({"ticker": t, "from": "2024-01-01", "to": "2026-09-22"}).encode(),
        headers={"apikey": K, "Authorization": "Bearer " + K, "content-type": "application/json"})
    d = json.loads(urllib.request.urlopen(r, timeout=180).read())
    json.dump(d, open(t.lower() + ".json", "w"))
    b = d.get("bars") or []
    print(t, len(b), b[0]["d"] if b else "-", b[-1]["d"] if b else "-", flush=True)
