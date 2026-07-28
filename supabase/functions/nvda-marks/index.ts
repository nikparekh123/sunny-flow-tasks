/**
 * nvda-marks — the 60-second realtime feed for the NVDA strategy store.
 *
 * Every run (cron, every minute during market hours):
 *   1. NVDA + peers/ETFs spot  → public.nvda_quote      (latest-only upsert)
 *   2. per open option leg: mark + delta/gamma/theta/vega/iv + OI/volume
 *      from Polygon's option snapshot → public.nvda_option_marks
 *
 * Writes with the service-role key (bypasses RLS). Greeks/marks that Polygon
 * doesn't return (thin/old contracts) are stored null → the app renders "—".
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const PEERS = ['NVDA', 'QQQ', 'SPY', 'SMH', 'AVGO', 'AMD', 'ARM', 'INTC'];
const pad = (n: number) => String(n).padStart(2, '0');

/** Build the OCC option symbol Polygon expects, e.g. O:NVDA260815C00215000 */
function occSymbol(type: string, strike: number, expiry: string): string {
  const d = new Date(expiry + 'T00:00:00Z');
  const yy = String(d.getUTCFullYear()).slice(2);
  const cp = type === 'call' ? 'C' : 'P';
  const strk = String(Math.round(strike * 1000)).padStart(8, '0');
  return `O:NVDA${yy}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}${cp}${strk}`;
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

async function fetchOption(occ: string, key: string) {
  try {
    const r = await fetch(`https://api.polygon.io/v3/snapshot/options/NVDA/${occ}?apiKey=${key}`);
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

  // 1 · spot for NVDA + peers
  let quotes = 0;
  for (const tk of PEERS) {
    const s = await fetchSpot(tk, key);
    if (!s || !s.spot) continue;   // skip null or zero
    const { error } = await admin.from('nvda_quote').upsert(
      { ticker: tk, spot: s.spot, day_change_pct: s.chg, prev_close: s.prev, captured_at: now },
      { onConflict: 'ticker' },
    );
    if (!error) quotes++;
  }

  // 2 · net-OPEN contracts only (open − close ≠ 0) → their open trade ids
  const { data: trades, error: tErr } = await admin
    .from('nvda_option_trades')
    .select('id, action, option_type, strike, expiry, contracts')
    .is('voided_at', null);
  if (tErr) return json(500, { ok: false, error: tErr.message });

  const byContract = new Map<string, { occ: string; net: number; ids: string[] }>();
  for (const t of trades ?? []) {
    const occ = occSymbol(t.option_type, Number(t.strike), t.expiry);
    const e = byContract.get(occ) ?? { occ, net: 0, ids: [] };
    e.net += (t.action === 'open' ? 1 : -1) * Number(t.contracts);
    if (t.action === 'open') e.ids.push(t.id);
    byContract.set(occ, e);
  }
  const contracts = [...byContract.values()].filter((c) => Math.abs(c.net) > 1e-6);

  // 3 · one Polygon snapshot per open contract → mark row per open trade of it
  let marked = 0;
  for (const c of contracts) {
    const snap = await fetchOption(c.occ, key);
    if (!snap) continue;
    for (const id of c.ids) {
      const { error } = await admin.from('nvda_option_marks').upsert(
        { option_trade_id: id, ...snap, captured_at: now },
        { onConflict: 'option_trade_id' },
      );
      if (!error) marked++;
    }
  }

  return json(200, { ok: true, captured_at: now, quotes, contracts: contracts.length, marks: marked });
});
