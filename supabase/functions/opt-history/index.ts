/**
 * opt-history — daily bars for named option contracts.
 *
 * A thin, read-only passthrough to Polygon's options aggregates, so a backtest
 * can ask what a specific contract actually traded at rather than model what it
 * might have. Nothing is stored and nothing is computed here: the caller names
 * the contracts, this returns their bars.
 *
 * It exists because the questions we cannot currently answer — premium per delta
 * at the money against out of it, what an ATM roll really collected, whether a
 * long call bought on a dip paid for itself — all need option PRICES, and the
 * app only has underlying closes.
 *
 * POST {
 *   contracts: ["O:NVDA260814C00220000", ...],   // OCC symbols, max 60 a call
 *   from: "2024-01-01", to: "2024-12-31"
 * }
 * → { ok, bars: { "<contract>": [{ t, o, h, l, c, v }] }, missing: [...] }
 *
 * Deliberately narrow: options aggregates only, no arbitrary Polygon paths, so
 * exposing it cannot turn into a general proxy for the key.
 *
 * Env: POLYGON_API_KEY.
 */
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

/** O:NVDA260814C00220000 — underlying, yymmdd, C|P, strike × 1000 padded to 8. */
const OCC = /^O:[A-Z]{1,6}\d{6}[CP]\d{8}$/;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const key = Deno.env.get('POLYGON_API_KEY');
  if (!key) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });

  const b = await req.json().catch(() => ({})) as Record<string, unknown>;
  const from = String(b.from ?? '').slice(0, 10);
  const to = String(b.to ?? '').slice(0, 10);
  const raw = Array.isArray(b.contracts) ? b.contracts.map(String) : [];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to))
    return json(400, { ok: false, error: 'from and to must be YYYY-MM-DD' });

  // Shape-checked rather than trusted: this string goes into a URL path, and a
  // regex that only admits OCC symbols is what keeps this from being a proxy
  // for anything else on Polygon.
  const contracts = raw.filter((c) => OCC.test(c)).slice(0, 60);
  const rejected = raw.filter((c) => !OCC.test(c));

  const bars: Record<string, unknown[]> = {};
  const missing: string[] = [];

  // Serial rather than parallel: a burst of 60 trips Polygon's rate limit and the
  // 429s come back as empty series, which reads as "this contract never traded"
  // — a silent wrong answer, which is worse than a slow one.
  for (const c of contracts) {
    try {
      const u = `https://api.polygon.io/v2/aggs/ticker/${c}/range/1/day/${from}/${to}`
              + `?adjusted=true&sort=asc&limit=5000&apiKey=${key}`;
      const r = await fetch(u);
      if (!r.ok) { missing.push(c); continue; }
      const j = await r.json();
      const rows = (j?.results ?? []) as Record<string, number>[];
      if (!rows.length) { missing.push(c); continue; }
      bars[c] = rows.map((x) => ({
        d: new Date(x.t).toISOString().slice(0, 10),
        o: x.o, h: x.h, l: x.l, c: x.c, v: x.v,
      }));
    } catch { missing.push(c); }
  }

  return json(200, {
    ok: true, from, to,
    asked: contracts.length, returned: Object.keys(bars).length,
    // Named, not swallowed: a contract that never traded and one whose symbol was
    // malformed are different problems and both are silent otherwise.
    missing, rejected,
    bars,
  });
});
