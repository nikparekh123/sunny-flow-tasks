/**
 * chain-next — the next two Fridays' option chain for every held name.
 *
 * The roll sheet (long press on a sold leg, `docs` export 24) asks what to
 * write on this name next Friday: the strike at or beyond spot, what it pays
 * NOW, its delta, and the open interest on the five nearest strikes. None of
 * that exists in `option_greeks_latest`, which only ever covers legs already
 * held, so this feed stores the band around spot instead.
 *
 * ⚠ TWO FRIDAYS, NOT ONE. "Next Friday" means the first Friday after the leg
 * you pressed expires, and a leg expiring this Friday and one expiring next
 * Friday therefore point at different weeks. Both are stored; the reader
 * picks.
 *
 * ⚠ THE PREMIUM IS THE LIVE MID, not the credit the old leg opened at. Nik,
 * 22 Sep 2026 (decision a): the sheet's hero and its percent on strike have to
 * be what the market pays this minute, or the floor test is answered with last
 * week's number.
 *
 * Polygon's snapshot carries quote, greeks, IV and open interest in one call,
 * so this is 2 calls a name a run. Marks are ~15 min delayed on the plan; the
 * sheet is a planning tool, which is the same trade every other card makes.
 *
 * Run by `chain-next-15min` (pg_cron, market hours). POST { dry_run: true } to
 * see what it would write without writing it.
 */

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const BUILD = '2026-09-22.1';
/** Strikes within this much of spot, each side. Five tiles need far less; the
    band is wide enough that a big day does not empty it before the next run. */
const BAND_PCT = 12;

interface Snap {
  details?: { contract_type?: string; strike_price?: number; expiration_date?: string };
  greeks?: { delta?: number };
  implied_volatility?: number;
  open_interest?: number;
  last_quote?: { midpoint?: number; bid?: number; ask?: number };
  last_trade?: { price?: number };
  day?: { close?: number };
  fair_market_value?: number;
  underlying_asset?: { price?: number };
}

/** The mid if there is a two-sided quote, else the last trade, else the day's
    close. A strike with no price at all is dropped rather than shipped at 0. */
function midOf(c: Snap): number | null {
  const b = c.last_quote?.bid, a = c.last_quote?.ask;
  if (typeof b === 'number' && typeof a === 'number' && b > 0 && a > 0) return (b + a) / 2;
  if (typeof c.last_quote?.midpoint === 'number' && c.last_quote.midpoint > 0) return c.last_quote.midpoint;
  if (typeof c.last_trade?.price === 'number' && c.last_trade.price > 0) return c.last_trade.price;
  if (typeof c.day?.close === 'number' && c.day.close > 0) return c.day.close;
  if (typeof c.fair_market_value === 'number' && c.fair_market_value > 0) return c.fair_market_value;
  return null;
}

/** The next `n` Fridays strictly after `from` (New York's date, not UTC's). */
function fridays(from: string, n: number): string[] {
  const out: string[] = [];
  const d = new Date(from + 'T12:00:00Z');
  while (out.length < n) {
    d.setUTCDate(d.getUTCDate() + 1);
    if (d.getUTCDay() === 5) out.push(d.toISOString().slice(0, 10));
  }
  return out;
}

const nyToday = () =>
  new Date(new Date().toLocaleString('en-US', { timeZone: 'America/New_York' }))
    .toLocaleDateString('en-CA');

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const t0 = Date.now();
  try {
    const SB_URL = Deno.env.get('SUPABASE_URL')!;
    const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const POLY = Deno.env.get('POLYGON_API_KEY');
    if (!POLY) return json(500, { ok: false, error: 'POLYGON_API_KEY is not set' });

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch { /* cron sends none */ }
    const dryRun = body.dry_run === true;

    const rest = async (path: string) => {
      const r = await fetch(`${SB_URL}/rest/v1/${path}`, {
        headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
      });
      return r.ok ? (await r.json()) as Record<string, unknown>[] : [];
    };

    const today = nyToday();

    /* ⚠ THE UNIVERSE IS WHAT IS OPEN, netted on the contract key. A name whose
       legs have all run off still has rows in `option_trades`, and pulling its
       chain every quarter hour would pay Polygon to watch a book that is not
       there. */
    const trades = await rest('option_trades?voided_at=is.null'
      + '&select=ticker,option_type,strike,expiry,direction,action,contracts&limit=10000');
    const net = new Map<string, number>();
    for (const t of trades) {
      const key = [t.ticker, t.option_type, t.strike, t.expiry, t.direction].join('|');
      const n = Number(t.contracts) || 0;
      net.set(key, (net.get(key) ?? 0) + (String(t.action) === 'open' ? n : -n));
    }
    const names = new Set<string>();
    for (const [key, n] of net) {
      if (n <= 0.0001) continue;
      const [ticker, , , expiry] = key.split('|');
      if (String(expiry) >= today) names.add(String(ticker));
    }

    const weeks = fridays(today, 2);
    const rows: Record<string, unknown>[] = [];
    const notes: string[] = [];

    for (const ticker of [...names].sort()) {
      for (const expiry of weeks) {
        const u = new URL(`https://api.polygon.io/v3/snapshot/options/${ticker}`);
        u.searchParams.set('expiration_date', expiry);
        u.searchParams.set('limit', '250');
        u.searchParams.set('apiKey', POLY);
        const r = await fetch(u.toString());
        if (!r.ok) { notes.push(`${ticker} ${expiry}: HTTP ${r.status}`); continue; }
        const d = await r.json() as { results?: Snap[] };
        const items = d.results ?? [];
        const spot = items.find((c) => c.underlying_asset?.price)?.underlying_asset?.price ?? null;
        if (!spot) { notes.push(`${ticker} ${expiry}: no spot`); continue; }
        let kept = 0;
        for (const c of items) {
          const strike = c.details?.strike_price;
          const side = c.details?.contract_type;
          if (typeof strike !== 'number' || (side !== 'call' && side !== 'put')) continue;
          if (Math.abs(strike - spot) > spot * BAND_PCT / 100) continue;
          const mid = midOf(c);
          if (mid == null) continue;
          kept++;
          rows.push({
            ticker, expiry, side, strike,
            bid: c.last_quote?.bid ?? null, ask: c.last_quote?.ask ?? null,
            mid: Math.round(mid * 100) / 100,
            delta: c.greeks?.delta ?? null,
            iv: c.implied_volatility ?? null,
            oi: c.open_interest ?? null,
            spot, snapshot_at: new Date().toISOString(),
          });
        }
        notes.push(`${ticker} ${expiry}: ${kept}`);
      }
    }

    if (!dryRun && rows.length) {
      /* One upsert a chunk; the primary key is (ticker, expiry, side, strike),
         so a run rewrites the band in place and yesterday's far strikes age
         out on their own. */
      for (let i = 0; i < rows.length; i += 500) {
        const r = await fetch(`${SB_URL}/rest/v1/option_chain_next?on_conflict=ticker,expiry,side,strike`, {
          method: 'POST',
          headers: {
            apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`,
            'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates',
          },
          body: JSON.stringify(rows.slice(i, i + 500)),
        });
        if (!r.ok) return json(502, { ok: false, build: BUILD, error: (await r.text()).slice(0, 300) });
      }
    }

    return json(200, {
      ok: true, build: BUILD, dryRun, names: [...names].sort(), weeks,
      rows: rows.length, ms: Date.now() - t0, notes,
    });
  } catch (e) {
    return json(500, { ok: false, build: BUILD, error: (e as Error).message });
  }
});
