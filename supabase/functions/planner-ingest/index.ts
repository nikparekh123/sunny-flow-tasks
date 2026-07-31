/**
 * planner-ingest — auto-populate the Planner's calibration log from real trades.
 *
 * For every NVDA short-call OPEN in nvda_option_trades this logs one planner_intent:
 *   • at ingest — inverts the implied vol from the fill (premium), then records the
 *     predicted assignment odds N(d2) and the implied move IV·√T at the sale.
 *   • at settlement (once the expiry has passed) — marks assigned (held to expiry &
 *     finished ITM) or expired, and the realized move.
 *
 * Deliberately separate from ibkr-flex-sync so that function's void/cancellation
 * logic is never touched. Idempotent: one row per open trade (id = trade id),
 * upserted, so re-runs only fill in newly-settled outcomes.
 *
 * NOTE: mid == fill here. IBKR trade confirmations carry no execution-time NBBO,
 * so the "average fill vs mid" slip cannot be reconstructed post-hoc — it needs a
 * live mid captured at order time. Assignment rate, the predicted/actual buckets,
 * and hit rate are all real.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Secret: none extra.
 * Trigger: cron (every 30 min) or manual POST. Owner: nik@sunnyfi.co.
 */

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const OWNER_EMAIL = 'nik@sunnyfi.co';
const R = 0.045;

// ── Black-Scholes call + N(d2) + IV inversion ──
function ncdf(x: number): number {
  const a1 = .254829592, a2 = -.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429, p = .3275911;
  const s = x < 0 ? -1 : 1, z = Math.abs(x) / Math.SQRT2, t = 1 / (1 + p * z);
  const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-z * z);
  return .5 * (1 + s * y);
}
function callPrice(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return Math.max(S - K, 0);
  const sq = v * Math.sqrt(T);
  const d1 = (Math.log(S / K) + (R + v * v / 2) * T) / sq;
  return S * ncdf(d1) - K * Math.exp(-R * T) * ncdf(d1 - sq);
}
function assignProb(S: number, K: number, T: number, v: number): number {
  if (T <= 0) return S > K ? 1 : 0;
  const sq = v * Math.sqrt(T);
  return ncdf((Math.log(S / K) + (R + v * v / 2) * T) / sq - sq);
}
/** Bisection IV from an observed call price. null if outside [intrinsic, huge]. */
function invertIV(price: number, S: number, K: number, T: number): number | null {
  if (T <= 0 || price <= Math.max(S - K, 0) + 1e-6) return null;
  let lo = 0.01, hi = 5;
  if (callPrice(S, K, T, hi) < price) return null;
  for (let i = 0; i < 60; i++) {
    const mid = (lo + hi) / 2;
    if (callPrice(S, K, T, mid) > price) hi = mid; else lo = mid;
  }
  return (lo + hi) / 2;
}

// ── dates ──
const DAY = 86400000;
const parse = (s: string) => new Date(s + 'T00:00:00Z');
const yearFrac = (from: string, to: string) => Math.max(0, (parse(to).getTime() - parse(from).getTime()) / (365 * DAY));

interface Trade { id: string; trade_date: string; action: string; option_type: string; direction: string; contracts: number; strike: number; premium: number; expiry: string; voided_at: string | null; }
interface Close { date: string; close_price: number | null; }
interface Intent { id: string; settled: boolean; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json(500, { ok: false, error: 'service env not set' });
  const H = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };

  // resolve the app's user id (shared login)
  const usersRes = await fetch(`${url}/auth/v1/admin/users?per_page=200`, { headers: H });
  const usersBody = await usersRes.json().catch(() => ({}));
  const users = (usersBody.users ?? usersBody) as { id: string; email?: string }[];
  const owner = Array.isArray(users) ? users.find((u) => u.email === OWNER_EMAIL) : null;
  if (!owner) return json(500, { ok: false, error: `owner ${OWNER_EMAIL} not found` });
  const userId = owner.id;

  // data
  const q = async <T,>(path: string): Promise<T> => (await fetch(`${url}/rest/v1/${path}`, { headers: H })).json();
  const trades = await q<Trade[]>('nvda_option_trades?select=id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,voided_at&voided_at=is.null');
  const closesRows = await q<Close[]>('nvda_daily_closes?select=date,close_price&ticker=eq.NVDA&order=date.asc');
  const existing = await q<Intent[]>(`planner_intents?select=id,settled&user_id=eq.${userId}`);

  const closeByDate = new Map<string, number>();
  const closesSorted: { date: string; c: number }[] = [];
  for (const r of closesRows) if (r.close_price != null) { closeByDate.set(r.date, r.close_price); closesSorted.push({ date: r.date, c: r.close_price }); }
  const lastClose = closesSorted.length ? closesSorted[closesSorted.length - 1].c : null;
  // spot on or after a date (first close >= date), for settlement
  const closeOnOrAfter = (d: string) => closesSorted.find((r) => r.date >= d)?.c ?? null;
  const spotAt = (d: string) => closeByDate.get(d) ?? [...closeByDate.entries()].filter(([dt]) => dt <= d).sort().pop()?.[1] ?? lastClose;

  const today = new Date().toISOString().slice(0, 10);
  const shorts = trades.filter((t) => t.option_type === 'call' && t.direction === 'short' && t.action === 'open');
  const existingIds = new Set(existing.map((e) => e.id));
  const settledIds = new Set(existing.filter((e) => e.settled).map((e) => e.id));

  const rows: Record<string, unknown>[] = [];
  let ingested = 0, settled = 0;

  for (const t of shorts) {
    const alreadySettled = settledIds.has(t.id);
    if (alreadySettled) continue;                                   // nothing left to do for it

    const sSale = spotAt(t.trade_date);
    const T = yearFrac(t.trade_date, t.expiry);
    if (!sSale || T <= 0) continue;
    const iv = invertIV(t.premium, sSale, t.strike, T);
    const pAssign = iv != null ? assignProb(sSale, t.strike, T, iv) : null;
    const impliedMove = iv != null ? iv * Math.sqrt(T) * 100 : null;

    // settlement — only once the expiry has passed
    const expired = t.expiry < today;
    let assigned: boolean | null = null, realizedMove: number | null = null, isSettled = false;
    if (expired) {
      const sExp = closeOnOrAfter(t.expiry) ?? spotAt(t.expiry);
      // held to expiry == no buy-to-close for the same leg
      const closedEarly = trades.some((x) => x.direction === 'short' && x.option_type === 'call'
        && x.strike === t.strike && x.expiry === t.expiry && x.action !== 'open');
      assigned = !closedEarly && sExp != null && sExp >= t.strike;
      realizedMove = (sExp != null && sSale) ? Math.abs(sExp - sSale) / sSale * 100 : null;
      isSettled = true;
    } else if (existingIds.has(t.id)) {
      continue;                                                     // already logged, not yet settled
    }

    rows.push({
      user_id: userId, id: t.id, ts: `${t.trade_date}T00:00:00Z`, expiry: t.expiry,
      strike: t.strike, ct: t.contracts, mid: t.premium, fill: t.premium,
      p_assign: pAssign, assigned, implied_move: impliedMove, realized_move: realizedMove, settled: isSettled,
    });
    if (isSettled) settled++; else ingested++;
  }

  if (rows.length) {
    const res = await fetch(`${url}/rest/v1/planner_intents?on_conflict=user_id,id`, {
      method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify(rows),
    });
    if (!res.ok) return json(500, { ok: false, error: `upsert failed ${res.status}`, detail: await res.text() });
  }

  return json(200, { ok: true, user: userId, shortCalls: shorts.length, newlyIngested: ingested, newlySettled: settled, written: rows.length });
});
