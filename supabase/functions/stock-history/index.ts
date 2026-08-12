/**
 * stock-history — daily bars and dividends for an underlying.
 *
 * The sibling of opt-history, and it exists for the same reason: a backtest has
 * to be told what actually happened, not asked to reconstruct it. Reconstructing
 * TLT's spot from put-call parity landed 28 cents from the real close with a $2.10
 * spread across expiries — fine for a chart, useless for choosing between strikes
 * 50 cents apart, which is exactly what the strike-policy test turns on.
 *
 * Deliberately narrow, on the same principle as opt-history: two fixed Polygon
 * paths, a ticker that must match ^[A-Z.]{1,6}$, and nothing else. It cannot be
 * bent into a general proxy for the key.
 *
 * POST {
 *   ticker: "TLT",
 *   from: "2024-06-01", to: "2026-08-12",
 *   dividends: true            // optional, adds the distribution history
 * }
 * → { ok, ticker, bars: [{d,o,h,l,c,v}], dividends: [{ex,pay,amount}] }
 *
 * Bars are SPLIT-adjusted and dividend-UNadjusted (adjusted=true on Polygon's
 * aggregates), which is what an option backtest needs: strikes are struck against
 * the traded price, and distributions are then counted once, explicitly, as cash.
 * Feeding it a total-return series would pay the dividend twice.
 *
 * Env: POLYGON_API_KEY.
 */
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const TICKER = /^[A-Z.]{1,6}$/;
const ISO = /^\d{4}-\d{2}-\d{2}$/;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const key = Deno.env.get('POLYGON_API_KEY');
  if (!key) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });

  const b = await req.json().catch(() => ({})) as Record<string, unknown>;
  const ticker = String(b.ticker ?? '').toUpperCase();
  const from = String(b.from ?? '').slice(0, 10);
  const to = String(b.to ?? '').slice(0, 10);

  // Shape-checked rather than trusted — these go into a URL path.
  if (!TICKER.test(ticker)) return json(400, { ok: false, error: 'ticker must match ^[A-Z.]{1,6}$' });
  if (!ISO.test(from) || !ISO.test(to)) return json(400, { ok: false, error: 'from and to must be YYYY-MM-DD' });

  const out: Record<string, unknown> = { ok: true, ticker, from, to };

  try {
    const r = await fetch(`${POLY}/v2/aggs/ticker/${ticker}/range/1/day/${from}/${to}`
      + `?adjusted=true&sort=asc&limit=50000&apiKey=${key}`);
    if (!r.ok) return json(502, { ok: false, error: `polygon aggregates ${r.status}` });
    const j = await r.json() as { results?: Array<Record<string, number>> };
    out.bars = (j?.results ?? []).map((x) => ({
      d: new Date(x.t).toISOString().slice(0, 10),
      o: x.o, h: x.h, l: x.l, c: x.c, v: x.v,
    }));
  } catch (e) {
    return json(502, { ok: false, error: `aggregates fetch failed: ${e}` });
  }

  if (b.dividends) {
    try {
      const r = await fetch(`${POLY}/v3/reference/dividends?ticker=${ticker}`
        + `&limit=1000&order=asc&sort=ex_dividend_date&apiKey=${key}`);
      if (r.ok) {
        const j = await r.json() as { results?: Array<Record<string, string | number>> };
        out.dividends = (j?.results ?? [])
          .filter((x) => String(x.ex_dividend_date ?? '') >= from && String(x.ex_dividend_date ?? '') <= to)
          .map((x) => ({ ex: x.ex_dividend_date, pay: x.pay_date, amount: Number(x.cash_amount) }));
      } else out.dividends = [];
    } catch { out.dividends = []; }
  }

  return json(200, out);
});
