/**
 * nvda-marks — the 60-second realtime feed for the per-ticker strategy stores.
 *
 * The name is now a misnomer and deliberately kept: it is what the
 * `nvda-marks-60s` cron calls, and renaming the function would mean
 * re-scheduling the cron for no gain. It prices every book in BOOKS.
 *
 * Every run (cron, every minute during market hours), per book:
 *   1. underlying + peers/ETFs spot  → public.<prefix>_quote      (latest-only upsert)
 *   2. per open option leg: mark + delta/gamma/theta/vega/iv + OI/volume
 *      from Polygon's option snapshot → public.<prefix>_option_marks
 *
 * TLT was previously fed from the generic ticker_quotes/option_greeks tables
 * via tlt_mirror, on mp-refresh's 15-minute cron — which also stopped at
 * 19:45 UTC, freezing the TLT price fifteen minutes BEFORE the US close. That
 * is the window in which assignment on a near-the-money weekly is decided, so
 * it was the part that actually mattered. Both books now run on the same
 * one-minute clock through 21:59 UTC.
 *
 * Writes with the service-role key (bypasses RLS). Greeks/marks that Polygon
 * doesn't return (thin/old contracts) are stored null → the app renders "—".
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

/** One book per store. `peers` is the spot list written to <prefix>_quote; the
 *  underlying itself must be first in it, since the app looks its own price up
 *  by ticker and finds nothing if it is missing. */
const BOOKS = [
  {
    under: 'NVDA',
    prefix: 'nvda',
    peers: ['NVDA', 'QQQ', 'SPY', 'SMH', 'AVGO', 'AMD', 'ARM', 'INTC'],
  },
  {
    // The bond complex: duration ladder (SHY/IEF/TLH) plus credit (AGG/LQD),
    // which is what TLT is read against.
    under: 'TLT',
    prefix: 'tlt',
    peers: ['TLT', 'IEF', 'SHY', 'TLH', 'AGG', 'LQD'],
  },
];

const pad = (n: number) => String(n).padStart(2, '0');

/** Build the OCC option symbol Polygon expects, e.g. O:NVDA260815C00215000 */
function occSymbol(under: string, type: string, strike: number, expiry: string): string {
  const d = new Date(expiry + 'T00:00:00Z');
  const yy = String(d.getUTCFullYear()).slice(2);
  const cp = type === 'call' ? 'C' : 'P';
  const strk = String(Math.round(strike * 1000)).padStart(8, '0');
  return `O:${under}${yy}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}${cp}${strk}`;
}

async function fetchSpot(tk: string, key: string) {
  try {
    const r = await fetch(`https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers/${tk}?apiKey=${key}`);
    if (!r.ok) return null;
    const t = (await r.json())?.ticker;
    if (!t) return null;
    // Truthy fallback (||, not ??): pre-open the last trade can be 0, which must
    // fall through to the day/previous close rather than write a zero spot.
    return {
      spot: t.lastTrade?.p || t.day?.c || t.prevDay?.c || null,
      prev: t.prevDay?.c ?? null,
      chg: t.todaysChangePerc ?? null,
    };
  } catch { return null; }
}

async function fetchOption(under: string, occ: string, key: string) {
  try {
    const r = await fetch(`https://api.polygon.io/v3/snapshot/options/${under}/${occ}?apiKey=${key}`);
    if (!r.ok) return null;
    const g = (await r.json())?.results;
    if (!g) return null;
    return {
      mark: g.last_quote?.midpoint ?? g.day?.close ?? null,
      delta: g.greeks?.delta ?? null,
      gamma: g.greeks?.gamma ?? null,
      theta: g.greeks?.theta ?? null,
      vega: g.greeks?.vega ?? null,
      iv: g.implied_volatility ?? null,
      open_interest: g.open_interest ?? null,
      volume: g.day?.volume ?? null,
    };
  } catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const url = Deno.env.get('SUPABASE_URL')!;
  const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const key = Deno.env.get('POLYGON_API_KEY');
  if (!key) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });

  const admin = createClient(url, svc, { auth: { autoRefreshToken: false, persistSession: false } });
  const now = new Date().toISOString();
  const report: Record<string, unknown> = {};

  // One book failing must not take the others down with it: a Polygon outage on
  // the TLT chain should still leave NVDA priced. Each book reports its own
  // error rather than throwing.
  for (const book of BOOKS) {
    try {
      // 1 · spot for the underlying + its peers
      let quotes = 0;
      for (const tk of book.peers) {
        const s = await fetchSpot(tk, key);
        if (!s || !s.spot) continue;   // skip null or zero
        const { error } = await admin.from(`${book.prefix}_quote`).upsert(
          { ticker: tk, spot: s.spot, day_change_pct: s.chg, prev_close: s.prev, captured_at: now },
          { onConflict: 'ticker' },
        );
        if (!error) quotes++;
      }

      // 2 · net-OPEN contracts only (open − close ≠ 0) → their open trade ids
      const { data: trades, error: tErr } = await admin
        .from(`${book.prefix}_option_trades`)
        .select('id, action, option_type, strike, expiry, contracts')
        .is('voided_at', null);
      if (tErr) { report[book.under] = { ok: false, error: tErr.message }; continue; }

      const byContract = new Map<string, { occ: string; net: number; ids: string[] }>();
      for (const t of trades ?? []) {
        const occ = occSymbol(book.under, t.option_type, Number(t.strike), t.expiry);
        const e = byContract.get(occ) ?? { occ, net: 0, ids: [] };
        e.net += (t.action === 'open' ? 1 : -1) * Number(t.contracts);
        if (t.action === 'open') e.ids.push(t.id);
        byContract.set(occ, e);
      }
      const contracts = [...byContract.values()].filter((c) => Math.abs(c.net) > 1e-6);

      // 3 · one Polygon snapshot per open contract → mark row per open trade of it.
      //     Only write NON-NULL fields. Polygon returns null greeks for thin,
      //     deep-ITM contracts intermittently; writing that null wiped the last good
      //     delta and made the app's position delta jump by thousands between polls.
      //     Omitting nulls keeps the last-known value (on-conflict updates only the
      //     provided columns).
      let marked = 0;
      for (const c of contracts) {
        const snap = await fetchOption(book.under, c.occ, key);
        if (!snap) continue;
        const fresh: Record<string, unknown> = { captured_at: now };
        for (const [k, v] of Object.entries(snap)) if (v !== null && v !== undefined) fresh[k] = v;
        for (const id of c.ids) {
          const { error } = await admin.from(`${book.prefix}_option_marks`).upsert(
            { option_trade_id: id, ...fresh },
            { onConflict: 'option_trade_id' },
          );
          if (!error) marked++;
        }
      }

      report[book.under] = { ok: true, quotes, contracts: contracts.length, marks: marked };
    } catch (e) {
      report[book.under] = { ok: false, error: String(e) };
    }
  }

  return json(200, { ok: true, captured_at: now, books: report });
});
