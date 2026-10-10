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
 *
 * ⚠ THETA DATA, LIVE (9 Oct 2026). With the MARKS_SOURCE secret at `theta` (or
 * a body of {source:"theta"}), each chain comes from Theta Data's real-time
 * NBBO through our Fly.io terminal (infra/theta) and is reshaped into the
 * Polygon snapshot shape, so everything below it is unchanged. Real bid and ask
 * mean the Black-Scholes stand-in in midOf is no longer needed on that path. A
 * chain Theta cannot answer falls back to Polygon.
 */

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const BUILD = '2026-10-09.1';

const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
type TRow = { contract: { right: string; strike: number; expiration: string };
              data: Array<Record<string, number | string>> };
async function thetaGet(path: string): Promise<TRow[]> {
  const r = await fetch(`${THETA_URL}${path}&format=json`, {
    headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) });
  if (!r.ok) return [];
  return ((await r.json())?.response ?? []) as TRow[];
}
/** The stock price the chain's own quotes imply: C - P + K at the strike
    where the call and put are closest in price (both two-sided). Theta's
    `underlying_price` can come from a different moment than the option quotes
    (after the 9 Oct close it read 35.11 against quotes implying 34.73), and
    every IV and "1 SD" below is only as right as the spot it uses. */
function impliedSpot(rows: Array<{ side: string; k: number; bid: number; ask: number }>, T: number): number | null {
  const by = new Map<number, { c?: number; p?: number }>();
  for (const r of rows) {
    if (!(r.bid > 0 && r.ask > 0)) continue;
    const e = by.get(r.k) ?? {}; e[r.side === 'call' ? 'c' : 'p'] = (r.bid + r.ask) / 2; by.set(r.k, e);
  }
  let best: number | null = null, gap = Infinity;
  for (const [k, e] of by) {
    if (e.c == null || e.p == null) continue;
    if (Math.abs(e.c - e.p) < gap) { gap = Math.abs(e.c - e.p); best = e.c - e.p + k * Math.exp(-0.04 * T); }
  }
  return best;
}
/** IV from a price, by bisection on the same Black-Scholes the sheet prices with. */
function ivFrom(call: boolean, px: number, S: number, K: number, T: number): number | undefined {
  const intrinsic = Math.max(0, call ? S - K : K - S);
  if (!(px > intrinsic + 0.005) || T <= 0) return undefined;
  let lo = 0.01, hi = 4;
  for (let i = 0; i < 60; i++) { const m = (lo + hi) / 2; if (bs(call, S, K, T, m) < px) lo = m; else hi = m; }
  return (lo + hi) / 2;
}

function deltaOf(call: boolean, S: number, K: number, T: number, v: number): number {
  const d1 = (Math.log(S / K) + 0.5 * v * v * T) / (v * Math.sqrt(T));
  return call ? ncdf(d1) : ncdf(d1) - 1;
}

/** One expiry's chain from Theta, in Polygon's snapshot shape. */
async function thetaChain(ticker: string, expiry: string): Promise<Snap[]> {
  const ex = expiry.replaceAll('-', '');
  const [gr, oi] = await Promise.all([
    thetaGet(`/v3/option/snapshot/quote?symbol=${ticker}&expiration=${ex}`),
    thetaGet(`/v3/option/snapshot/open_interest?symbol=${ticker}&expiration=${ex}`),
  ]);
  const key = (r: TRow) => `${r.contract.right.toLowerCase()}|${Number(r.contract.strike)}`;
  const oiBy = new Map(oi.map((r) => [key(r), Number(r.data?.[0]?.open_interest)]));
  const out: Snap[] = [];
  const flat = gr.filter((r) => r.data?.[0]).map((r) => ({
    side: r.contract.right.toLowerCase(), k: Number(r.contract.strike),
    bid: Number(r.data[0].bid), ask: Number(r.data[0].ask) }));
  /* The quote endpoint carries no underlying price; this stays as the last
     resort only if Theta ever adds one. */
  const S0 = Number(gr.find((r) => Number(r.data?.[0]?.underlying_price) > 0)?.data[0].underlying_price);
  const Sx = impliedSpot(flat, yearsTo(expiry));
  /* ⚠ THE IMPLIED SPOT WINS WHENEVER THERE IS ONE. Theta's stock price comes
     from its FREE stock tier and is not reliable: on 9 Oct it read BABA at
     57.00 on every contract while BABA traded 111 and its own option quotes
     said so. Its underlying_price is used only when no strike has a two-sided
     call and put to work the spot out from. */
  const S = Sx ?? S0;
  const T = yearsTo(expiry);
  for (const r of gr) {
    const d = r.data?.[0]; if (!d) continue;
    const bid = Number(d.bid), ask = Number(d.ask);
    const side = r.contract.right.toLowerCase();
    const mid = bid > 0 && ask > 0 ? (bid + ask) / 2 : ask > 0 ? ask / 2 : undefined;
    const iv = mid != null && S > 0 ? ivFrom(side === 'call', mid, S, Number(r.contract.strike), T) : undefined;
    out.push({
      details: { contract_type: side, strike_price: Number(r.contract.strike), expiration_date: expiry },
      /* Delta from the same Black-Scholes and IV, never Theta's own greeks,
         which ride on its unreliable underlying price. */
      greeks: { delta: iv && S > 0 ? deltaOf(side === 'call', S, Number(r.contract.strike), T, iv) : undefined },
      /* The IV is worked out here from the mid at the implied spot, so the
         price, the IV and the 1 SD all describe the same market. */
      implied_volatility: iv,
      open_interest: Number.isFinite(oiBy.get(key(r))) ? oiBy.get(key(r)) : undefined,
      /* A one-sided market (no bid) marks at half the ask, as mp-refresh does. */
      last_quote: { bid: bid > 0 ? bid : undefined, ask: ask > 0 ? ask : undefined, midpoint: mid },
      underlying_asset: { price: S > 0 ? S : undefined },
    });
  }
  return out;
}
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

/** Standard normal CDF (Abramowitz-Stegun 7.1.26 via erf). */
function ncdf(x: number): number {
  const t = 1 / (1 + 0.3275911 * Math.abs(x) / Math.SQRT2);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
    + 0.254829592) * t * Math.exp(-x * x / 2);
  return x >= 0 ? (1 + y) / 2 : (1 - y) / 2;
}
/** Black-Scholes, no rate, no dividend: a week out, both are noise. */
function bs(call: boolean, S: number, K: number, T: number, v: number): number {
  const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * v * v * T) / sq, d2 = d1 - sq;
  return call ? S * ncdf(d1) - K * ncdf(d2) : K * ncdf(-d2) - S * ncdf(-d1);
}
/** Years from now to 16:00 New York on the expiry (20:00 UTC, near enough). */
const yearsTo = (expiry: string) =>
  Math.max(1 / 365 / 24, (Date.parse(expiry + 'T20:00:00Z') - Date.now()) / (365 * 86_400_000));

/** ⚠ THE PRICE IS WORKED OUT, NOT THE LAST TRADE (24 Sep 2026). This plan
    carries no bid or ask, so the "mid" was the last print, which can be hours
    old: BABA's 2 Oct 113 read 1.70 against IBKR's live 1.59. Black-Scholes on
    the chain's own IV at the current spot landed within 3% of IBKR's mid on
    every strike checked (111 2.28 v 2.36, 112 1.90 v 1.93, 113 1.59 v 1.59).
    A real two-sided quote still wins when the plan ever sends one. */
function midOf(c: Snap, spot?: number | null): number | null {
  const b = c.last_quote?.bid, a = c.last_quote?.ask;
  if (typeof b === 'number' && typeof a === 'number' && b > 0 && a > 0) return (b + a) / 2;
  if (typeof c.last_quote?.midpoint === 'number' && c.last_quote.midpoint > 0) return c.last_quote.midpoint;
  const k = c.details?.strike_price, ex = c.details?.expiration_date, iv = c.implied_volatility;
  const side = c.details?.contract_type;
  if (spot && k && ex && iv && iv > 0 && (side === 'call' || side === 'put')) {
    const p = bs(side === 'call', spot, k, yearsTo(ex), iv);
    if (p > 0.005) return p;
  }
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
  let src = 'polygon';
  try {
    const SB_URL = Deno.env.get('SUPABASE_URL')!;
    const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const POLY = Deno.env.get('POLYGON_API_KEY');
    if (!POLY) return json(500, { ok: false, error: 'POLYGON_API_KEY is not set' });

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch { /* cron sends none */ }
    const dryRun = body.dry_run === true;
    const today0 = nyToday();
    const useTheta = String(body.source ?? Deno.env.get('MARKS_SOURCE') ?? 'polygon').toLowerCase() === 'theta'
      && !!THETA_URL && !!THETA_KEY;
    src = useTheta ? 'theta' : 'polygon';
    /** One expiry's chain: Theta when on (falling back to Polygon if it has
        nothing), otherwise Polygon. `null` means the call itself failed. */
    const chain = async (ticker: string, expiry: string): Promise<Snap[] | null> => {
      if (useTheta) {
        /* No two-sided call and put to find the spot from: fall back. */
        try {
          const t = await thetaChain(ticker, expiry);
          if (t.some((c) => c.underlying_asset?.price)) return t;
        } catch { /* fall back */ }
      }
      const u = new URL(`https://api.polygon.io/v3/snapshot/options/${ticker}`);
      u.searchParams.set('expiration_date', expiry);
      u.searchParams.set('limit', '250');
      u.searchParams.set('apiKey', POLY);
      const r = await fetch(u.toString());
      if (!r.ok) return null;
      return ((await r.json()) as { results?: Snap[] }).results ?? [];
    };

    /* ⚠ LIVE, ONE NAME (24 Sep 2026). The roll sheet asks for this every time
       it opens: Nik saw BABA at 110 and a write at 112, because the app had
       loaded at yesterday's 111. Nothing is written; the next two Fridays for
       `ticker`, shaped the way options-cards ships `rollCard.names[t].weeks`. */
    if (typeof body.ticker === 'string') {
      const ticker = body.ticker.toUpperCase();
      if (!/^[A-Z.]{1,6}$/.test(ticker)) return json(400, { ok: false, error: 'bad ticker' });
      type K = { k: number; oi: number | null; mid: number; dl: number | null; iv: number | null };
      const weeksOut = [];
      let spotOut: number | null = null;
      for (const expiry of fridays(today0, 2)) {
        const items = await chain(ticker, expiry);
        if (!items) continue;
        const spot = items.find((c) => c.underlying_asset?.price)?.underlying_asset?.price ?? null;
        if (!spot) continue;
        spotOut = spot;
        const calls: K[] = [], puts: K[] = [];
        let sd: number | null = null, near = Infinity;
        for (const c of items) {
          const k = c.details?.strike_price, side = c.details?.contract_type;
          if (typeof k !== 'number' || (side !== 'call' && side !== 'put')) continue;
          if (Math.abs(k - spot) > spot * BAND_PCT / 100) continue;
          const mid = midOf(c, spot);
          if (mid == null) continue;
          const iv = c.implied_volatility ?? null;
          const row: K = { k, oi: c.open_interest ?? null, mid: Math.round(mid * 100) / 100,
                           dl: c.greeks?.delta == null ? null : Math.round(c.greeks.delta * 100) / 100, iv };
          (side === 'call' ? calls : puts).push(row);
          /* One SD from the IV at the strike nearest spot, as options-cards does. */
          if (iv && Math.abs(k - spot) < near) {
            near = Math.abs(k - spot);
            sd = Math.round(spot * iv * Math.sqrt(Math.max(1, yearsTo(expiry) * 365) / 365) * 100) / 100;
          }
        }
        const nearest = (xs: K[], t: number) =>
          xs.length ? xs.reduce((a, b) => Math.abs(b.k - t) < Math.abs(a.k - t) ? b : a) : null;
        const up = calls.filter((x) => x.k >= spot).sort((a, b) => a.k - b.k);
        const dn = puts.filter((x) => x.k <= spot).sort((a, b) => b.k - a.k);
        weeksOut.push({
          w: expiry, sd,
          calls: up.slice(0, 5), puts: dn.slice(0, 5).sort((a, b) => a.k - b.k),
          sdCall: sd ? nearest(calls.filter((x) => x.k > spot), spot + sd) : null,
          sdPut: sd ? nearest(puts.filter((x) => x.k < spot), spot - sd) : null,
          /* the whole call side above spot, for the tiles and the write */
          above: up,
        });
      }
      return json(200, { ok: true, build: BUILD, source: src, ticker, asOf: new Date().toISOString(),
                         spot: spotOut, weeks: weeksOut });
    }

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
    /* One stamp for the whole run, so the rows it did NOT touch can be found. */
    const runAt = new Date().toISOString();
    const rows: Record<string, unknown>[] = [];
    const notes: string[] = [];

    for (const ticker of [...names].sort()) {
      for (const expiry of weeks) {
        const items = await chain(ticker, expiry);
        if (!items) { notes.push(`${ticker} ${expiry}: no chain`); continue; }
        const spot = items.find((c) => c.underlying_asset?.price)?.underlying_asset?.price ?? null;
        if (!spot) { notes.push(`${ticker} ${expiry}: no spot`); continue; }
        let kept = 0;
        for (const c of items) {
          const strike = c.details?.strike_price;
          const side = c.details?.contract_type;
          if (typeof strike !== 'number' || (side !== 'call' && side !== 'put')) continue;
          if (Math.abs(strike - spot) > spot * BAND_PCT / 100) continue;
          const mid = midOf(c, spot);
          if (mid == null) continue;
          kept++;
          rows.push({
            ticker, expiry, side, strike,
            bid: c.last_quote?.bid ?? null, ask: c.last_quote?.ask ?? null,
            mid: Math.round(mid * 100) / 100,
            delta: c.greeks?.delta ?? null,
            iv: c.implied_volatility ?? null,
            oi: c.open_interest ?? null,
            spot, snapshot_at: runAt,
          });
        }
        notes.push(`${ticker} ${expiry}: ${kept}`);
      }
    }

    if (!dryRun && rows.length) {
      /* One upsert a chunk; the primary key is (ticker, expiry, side, strike),
         so a run rewrites the band in place. Strikes that left the band are
         NOT rewritten, which is why the delete below exists. */
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
      /* ⚠ A STRIKE THAT LEFT THE BAND MUST LEAVE THE TABLE. The upsert only
         rewrites what is still within 12% of spot, so on 23 Sep BABA's 126-130
         calls sat on at yesterday's prices, priced off a spot of 116.51 while
         it traded 111. The roll sheet's 1 SD pick reads that far out. Every row
         this run did not write, and every week that has expired, goes. */
      const del = async (q: string) => {
        const r = await fetch(`${SB_URL}/rest/v1/option_chain_next?${q}`, {
          method: 'DELETE', headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
        });
        if (!r.ok) notes.push(`delete ${q}: HTTP ${r.status}`);
      };
      /* Only the name-weeks this run rewrote: a name Polygon failed on keeps
         its last good chain rather than losing it. */
      const done = new Set(rows.map((r) => `${r.ticker}|${r.expiry}`));
      for (const k of done) {
        const [tk, ex] = k.split('|');
        await del(`ticker=eq.${tk}&expiry=eq.${ex}&snapshot_at=lt.${encodeURIComponent(runAt)}`);
      }
      await del(`expiry=lt.${today}`);
    }

    return json(200, {
      ok: true, build: BUILD, source: src, dryRun, names: [...names].sort(), weeks,
      rows: rows.length, ms: Date.now() - t0, notes,
    });
  } catch (e) {
    return json(500, { ok: false, build: BUILD, error: (e as Error).message });
  }
});
