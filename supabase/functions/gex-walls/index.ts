/*
 * gex-walls · option gamma walls for a stock (Nik, 22 Oct 2026): the call wall above the price, the
 * put wall below, each with a runner-up, the flip level, FRESH strikes, and a table of the 15 strikes
 * nearest the price. The flip is the zero-gamma level. The maths is in walls.ts (tested on a fixed chain in walls_test.ts).
 *
 * Theta Data v3 through the fly.io proxy (THETA_URL, THETA_PROXY_KEY), Standard plan:
 *   /v3/option/list/expirations                 which expiries the window expects
 *   /v3/option/snapshot/greeks/implied_volatility  the chain and its bid/ask (Theta's IV and underlying
 *                                                  price are not used: see walls.ts impliedSpot)
 *   /v3/option/snapshot/open_interest           yesterday's open interest (OPRA, ~06:30 ET)
 *   /v3/option/snapshot/ohlc (current_day_only)  today's volume; a contract absent has not traded
 * Theta's gamma needs the Pro plan, so gamma is Black-Scholes at an IV solved from each mid (walls.ts).
 *
 * POST { ticker, days?: 45, expiries?: ['2026-10-30', ...], target?: 5, save?: true }
 *   -> { ok, ..., text }   text is the printable table and summary
 * POST { mode: 'daily', tickers? }  every name with a cached chain (the book), after the close each
 *   trading day; each run appends one row to gex_walls (the per-ticker log).
 * An incomplete chain fails loudly: HTTP 422 with every problem named, and nothing is logged.
 */
import { buildStrikes, Chain, Contract, findWalls, IncompleteChain, impliedSpot, isFresh, nearest,
  renderTable, solveIv, summaryLine, target, yearsTo, zeroGamma } from './walls.ts';

const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const SB_URL = Deno.env.get('SUPABASE_URL')!;
const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
type Row = Record<string, any>;

class ThetaError extends Error {}
async function theta(path: string): Promise<Row[]> {
  const r = await fetch(`${THETA_URL}${path}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(60_000) });
  if (!r.ok) throw new ThetaError(`Theta ${r.status} on ${path.split('?')[0]}: ${(await r.text()).slice(0, 200)}`);
  return ((await r.json())?.response ?? []) as Row[];
}

async function db(path: string, init?: RequestInit): Promise<Row[]> {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, { ...init,
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json', ...(init?.headers ?? {}) } });
  if (!r.ok) throw new Error(`db ${r.status} on ${path.split('?')[0]}: ${(await r.text()).slice(0, 200)}`);
  return r.status === 204 || r.status === 201 ? [] : await r.json();
}

/** Today in New York, and whether its 4 PM close has passed. */
function nyNow(): { day: string; afterClose: boolean } {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit',
    day: '2-digit', hour: '2-digit', hourCycle: 'h23' }).formatToParts(new Date()).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, afterClose: Number(p.hour) >= 16 };
}
const dte = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / 864e5);
const key = (c: Row) => `${c.expiration}|${Number(c.strike)}|${c.right}`;

/** Pull the chain for the window (or the listed expiries) and turn it into walls.ts's shape. */
async function loadChain(ticker: string, days: number, expiries?: string[]): Promise<{ chain: Chain; warnings: string[] }> {
  const { day, afterClose } = nyNow();
  const listed = (await theta(`/v3/option/list/expirations?symbol=${ticker}`)).map((x) => String(x.expiration));
  if (!listed.length) throw new IncompleteChain([`Theta lists no expirations for ${ticker}`]);
  let want: string[];
  if (expiries?.length) {
    const missing = expiries.filter((e) => !listed.includes(e));
    if (missing.length) throw new IncompleteChain(missing.map((e) => `${e} is not a listed ${ticker} expiry`));
    want = [...expiries].sort();
  } else {
    want = listed.filter((e) => e >= day && dte(day, e) <= days);
  }
  // An expiry that closed today has no gamma left.
  want = want.filter((e) => !(e === day && afterClose));
  if (!want.length) throw new IncompleteChain([`no ${ticker} expiries in the next ${days} days`]);
  const q = (ep: string, e: string) => `/v3/option/snapshot/${ep}?symbol=${ticker}&expiration=${e}`;
  const all = (ep: string, extra = '') => expiries?.length
    ? Promise.all(want.map((e) => theta(q(ep, e.replaceAll('-', '')) + extra))).then((xs) => xs.flat())
    : theta(q(ep, '*') + `&max_dte=${days}` + extra);
  // The stock price is read from the two nearest expiries, whichever ones were asked for: a far
  // expiry's call - put carries the dividends paid before it (NKE January read 37.09 against 37.40,
  // 23 Oct 2026). Their quotes are fetched for the price only when they are not in the run.
  const nearest2 = listed.filter((e) => e >= day && !(e === day && afterClose)).slice(0, 2);
  const extra = nearest2.filter((e) => !want.includes(e));
  const [ivs, ois, ohlc, extraIvs] = await Promise.all([all('greeks/implied_volatility'), all('open_interest'), all('ohlc', '&current_day_only=true'),
    Promise.all(extra.map((e) => theta(q('greeks/implied_volatility', e.replaceAll('-', ''))))).then((xs) => xs.flat())]);
  const oi = new Map(ois.map((r) => [key(r.contract), Number((r.data ?? []).at(-1)?.open_interest ?? 0)]));
  const vol = new Map(ohlc.map((r) => [key(r.contract), Number((r.data ?? []).at(-1)?.volume ?? 0)]));
  // Mids (two-sided quotes only), then the stock price they imply: the median of each nearest expiry's
  // at-the-money call - put + K e^(-rT). Each IV is then solved from its own mid.
  const now = Date.now();
  let thetaSpot = 0;
  type Quote = { exp: string; k: number; right: 'C' | 'P'; mid: number | null; c: Row };
  const parse = (r: Row): Quote => {
    const c = r.contract, d = (r.data ?? []).at(-1) ?? {}, b = Number(d.bid), a = Number(d.ask);
    thetaSpot = Number(d.underlying_price) || thetaSpot;
    return { exp: String(c.expiration), k: Number(c.strike), right: c.right === 'CALL' ? 'C' : 'P', mid: b > 0 && a >= b ? (a + b) / 2 : null, c };
  };
  const quotes = ivs.filter((r) => want.includes(String(r.contract.expiration))).map(parse);
  const forPrice = [...ivs.filter((r) => nearest2.includes(String(r.contract.expiration))), ...extraIvs].map(parse);
  const spotOf = (qs: Quote[], exps: string[]) => exps.map((e) => {
    const pairs = new Map<number, { k: number; c: number; p: number }>();
    for (const x of qs.filter((x) => x.exp === e && x.mid)) {
      const p = pairs.get(x.k) ?? { k: x.k, c: 0, p: 0 };
      if (x.right === 'C') p.c = x.mid!; else p.p = x.mid!;
      pairs.set(x.k, p);
    }
    return impliedSpot([...pairs.values()], yearsTo(e, now));
  }).filter((s): s is number => !!s);
  // Fallback: the run's own expiries within two weeks, then any of them.
  let pool = spotOf(forPrice, nearest2);
  if (!pool.length) pool = spotOf(quotes, want.filter((e) => dte(day, e) <= 14));
  if (!pool.length) pool = spotOf(quotes, want);
  pool.sort((a, b) => a - b);
  const spot = pool.length ? pool[Math.floor(pool.length / 2)] : 0;
  if (!(spot > 0)) throw new IncompleteChain([`no at-the-money call and put quotes to read ${ticker}'s price from`]);
  const contracts: Contract[] = quotes.map((x) => ({ exp: x.exp, k: x.k, right: x.right,
    iv: x.mid ? solveIv(x.mid, spot, x.k, yearsTo(x.exp, now), x.right === 'C') : null,
    oi: oi.get(key(x.c)) ?? 0, vol: vol.get(key(x.c)) ?? 0 }));
  // Open interest Theta has for a contract it sent no quote for: name it, it cannot be priced.
  const quoted = new Set(contracts.map((c) => `${c.exp}|${c.k}|${c.right === 'C' ? 'CALL' : 'PUT'}`));
  const orphan = ois.filter((r) => want.includes(String(r.contract.expiration)) && !quoted.has(key(r.contract)) && Number((r.data ?? []).at(-1)?.open_interest ?? 0) > 0);
  const warnings = orphan.length ? [`${orphan.length} contracts have open interest but no quote (${orphan.slice(0, 3).map((r) => key(r.contract)).join(', ')})`] : [];
  if (thetaSpot > 0 && Math.abs(thetaSpot / spot - 1) > 0.005) {
    warnings.push(`Theta's stock price ${thetaSpot.toFixed(2)} differs from the ${spot.toFixed(2)} the option quotes imply; the quotes are used`);
  }
  return { chain: { ticker, spot, expiries: want, contracts }, warnings };
}

async function run(ticker: string, days: number, expiries?: string[], pct?: number, save = true) {
  const { day } = nyNow();
  const { chain, warnings: w0 } = await loadChain(ticker, days, expiries);
  const b = buildStrikes(chain, { nowMs: Date.now() });
  // The flip is the zero-gamma level (Nik, 22 Oct 2026: the spec's cumulative crossing is dropped).
  const walls = findWalls(b.rows, chain.spot), flip = zeroGamma(b.legs, chain.spot);
  const net = b.rows.reduce((s, r) => s + r.netGex, 0);
  const near = nearest(b.rows, chain.spot, 15);
  const summary = summaryLine(day, ticker, chain.spot, net, flip, walls);
  const tgt = pct != null ? target(b.rows, chain.spot, pct, walls) : null;
  const say = (side: 'call' | 'put', t: { k: number; wall: number | null; vs: string } | null) => !t ? `no ${side} strike`
    : t.vs === 'no wall' ? `${side} ${t.k} (no ${side} wall)` : `${side} ${t.k} is ${t.vs === 'on' ? 'on' : t.vs} the ${side} wall ${t.wall}`;
  const filledPct = b.totalOi ? b.filledOi / b.totalOi * 100 : 0;
  const warnings = [...w0, ...b.warnings,
    ...(b.filledOi ? [`${b.filledOi} open interest (${filledPct.toFixed(1)}%) had no usable quote; its vol was filled from the neighbouring strikes`] : [])];
  const text = [
    `${ticker} · ${chain.expiries.length} expiries ${chain.expiries[0]} to ${chain.expiries.at(-1)} · GEX in $ per 1% move`,
    renderTable(near, chain.spot, walls), '', summary,
    ...(tgt ? [`target ${pct}%: ${say('call', tgt.call)} · ${say('put', tgt.put)}`] : []),
    ...warnings.map((x) => `note: ${x}`),
  ].join('\n');
  const out = {
    ok: true, ticker, day, spot: chain.spot, days, expiries: chain.expiries, net_gex: Math.round(net), flip,
    call_wall: walls.call.map((r) => ({ k: r.k, gex: Math.round(r.callGex) })),
    put_wall: walls.put.map((r) => ({ k: r.k, gex: Math.round(r.putGex) })),
    fresh: b.rows.filter(isFresh).map((r) => r.k), target: tgt, warnings, filled_oi_pct: +filledPct.toFixed(2),
    strikes: near.map((r) => ({ k: r.k, call: Math.round(r.callGex), put: Math.round(r.putGex), net: Math.round(r.netGex), oi: r.oi, vol: r.vol, fresh: isFresh(r) })),
    summary, text,
  };
  if (save) {
    await db('gex_walls', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({
      day, ticker, days: expiries?.length ? null : days, expiries: chain.expiries, spot: chain.spot, net_gex: out.net_gex, flip,
      call_wall: walls.call[0]?.k ?? null, call_wall_gex: out.call_wall[0]?.gex ?? null, call_wall2: walls.call[1]?.k ?? null,
      put_wall: walls.put[0]?.k ?? null, put_wall_gex: out.put_wall[0]?.gex ?? null, put_wall2: walls.put[1]?.k ?? null,
      fresh: out.fresh, filled_oi_pct: out.filled_oi_pct, summary, strikes: out.strikes }) });
  }
  return out;
}

/* Who may call: the scheduler's x-cron-key, the service-role key, or a signed-in user of the app. */
async function callerOk(req: Request): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  const auth = req.headers.get('authorization') ?? '';
  if (auth && auth === `Bearer ${SB_KEY}`) return true;
  if (!auth.startsWith('Bearer ')) return false;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: auth } });
  await r.body?.cancel();
  return r.ok;
}
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (!(await callerOk(req))) return json({ ok: false, error: 'not allowed' }, 401);
  if (!THETA_URL || !THETA_KEY) return json({ ok: false, error: 'THETA_URL / THETA_PROXY_KEY not set' }, 500);
  let body: { ticker?: string; tickers?: string[]; days?: number; expiries?: string[]; target?: number; save?: boolean; mode?: string } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* empty body */ }
  const days = Math.max(1, Math.min(400, Number(body.days ?? 45)));
  try {
    if (body.mode === 'daily' || !body.ticker) {
      const { day } = nyNow();
      const closed = await db(`market_calendar?date=eq.${day}&kind=eq.closed&select=date`);
      if (closed.length) return json({ ok: true, day, skipped: 'market closed' });
      // The open names: Home's strategy map has one key per name with a leg (the chain table can
      // hold a closed name, and a read of it caps at 1,000 rows).
      const names = body.tickers?.length ? body.tickers
        : Object.keys((await db('home_snapshot?id=eq.1&select=s:payload->strategies'))[0]?.s ?? {}).sort();
      const results = [];
      for (const t of names) {
        try { const r = await run(t.toUpperCase(), days, undefined, undefined, body.save ?? true); results.push({ ticker: t, summary: r.summary }); }
        catch (e) { results.push({ ticker: t, error: e instanceof IncompleteChain ? e.problems : String((e as Error).message) }); }
      }
      return json({ ok: results.every((r) => !('error' in r)), day, results });
    }
    return json(await run(body.ticker.toUpperCase(), days, body.expiries, body.target, body.save ?? true));
  } catch (e) {
    if (e instanceof IncompleteChain) return json({ ok: false, error: 'incomplete chain', problems: e.problems }, 422);
    if (e instanceof ThetaError) return json({ ok: false, error: e.message }, 502);
    return json({ ok: false, error: String((e as Error).message ?? e) }, 500);
  }
});
