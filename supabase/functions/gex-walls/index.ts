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
 *   trading day; each run appends one row to gex_walls (the per-ticker log). For the book (no `tickers`)
 *   it also saves one row per expiry (handoff 31, the Walls screen): the next three weeklies, the
 *   monthlies to about six months and the next January, each on its own (`expiry` set).
 * POST { mode: 'backfill', days: ['2026-10-19', ...], tickers? }  the same per-expiry rows for past
 *   sessions, from Theta's history (end-of-day quotes, that day's open interest), priced at 4 PM.
 * An incomplete chain fails loudly: HTTP 422 with every problem named, and nothing is logged.
 */
import { buildStrikes, Chain, closeMs, Contract, findWalls, IncompleteChain, impliedSpot, isFresh, nearest,
  renderTable, sleeping, solveIv, summaryLine, target, yearsTo, zeroGamma } from './walls.ts';

const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const SB_URL = Deno.env.get('SUPABASE_URL')!;
const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
type Row = Record<string, any>;

class ThetaError extends Error {}
async function theta(path: string): Promise<Row[]> {
  for (let i = 0; ; i++) {
    const r = await fetch(`${THETA_URL}${path}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(60_000) });
    // "Too many concurrent requests": wait and ask again, 1, 2, then 4 s.
    if (r.status === 429 && i < 3) { await r.body?.cancel(); await new Promise((f) => setTimeout(f, 1000 * 2 ** i)); continue; }
    if (!r.ok) throw new ThetaError(`Theta ${r.status} on ${path.split('?')[0]}: ${(await r.text()).slice(0, 200)}`);
    return ((await r.json())?.response ?? []) as Row[];
  }
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

/** Is this a standard monthly: the third Friday, or the Thursday before when that Friday is a holiday. */
const isMonthly = (e: string) => { const d = new Date(e + 'T12:00:00Z'), wd = d.getUTCDay(), dd = d.getUTCDate();
  return (wd === 5 && dd >= 15 && dd <= 21) || (wd === 4 && dd >= 14 && dd <= 20); };

/** The expiries the Walls screen keeps (handoff 31, 13d): the next four weeklies (the screen shows three, and
    its week table reaches back to Monday, when the third was the fourth), the monthlies to about six months,
    and the next January (where the hedge calls sit) when it is further out. */
function logged(listed: string[], day: string): string[] {
  const fut = listed.filter((e) => e > day).sort();
  const weeklies = fut.filter((e) => !isMonthly(e) && dte(day, e) <= 28).slice(0, 4);
  const monthlies = fut.filter((e) => isMonthly(e) && dte(day, e) <= 186);
  const jan = fut.find((e) => isMonthly(e) && e.slice(5, 7) === '01');
  return [...new Set([...weeklies, ...monthlies, ...(jan ? [jan] : [])])].sort();
}

/** Pull the chain for the expiries `pick` wants (or the listed ones) and turn it into walls.ts's shape.
    `asOf` a past session: Theta's end-of-day quotes and that day's open interest, priced at its 4 PM close. */
async function loadChain(ticker: string, o: { days?: number; expiries?: string[]; pick?: (listed: string[], day: string) => string[];
  asOf?: string }): Promise<{ chain: Chain; warnings: string[]; nowMs: number; day: string }> {
  const live = nyNow(), day = o.asOf ?? live.day, afterClose = o.asOf ? true : live.afterClose;
  const nowMs = o.asOf ? closeMs(o.asOf) : Date.now();
  const D = day.replaceAll('-', '');
  // A past session: the whole end-of-day chain at once (its expiries are the listed ones), or, with named
  // expiries, just those (SPY's whole chain is too big for one call; the list keeps past expiries too).
  const named = !!(o.asOf && o.expiries?.length);
  const hist = o.asOf && !named ? await theta(`/v3/option/history/eod?symbol=${ticker}&expiration=*&start_date=${D}&end_date=${D}`) : [];
  const listed = o.asOf && !named ? [...new Set(hist.map((r) => String(r.contract.expiration)))].sort()
    : (await theta(`/v3/option/list/expirations?symbol=${ticker}`)).map((x) => String(x.expiration)).sort();
  if (!listed.length) throw new IncompleteChain([`Theta lists no expirations for ${ticker}${o.asOf ? ` on ${o.asOf}` : ''}`]);
  let want: string[];
  if (o.expiries?.length) {
    const missing = o.expiries.filter((e) => !listed.includes(e));
    if (missing.length) throw new IncompleteChain(missing.map((e) => `${e} is not a listed ${ticker} expiry`));
    want = [...o.expiries].sort();
  } else if (o.pick) {
    want = o.pick(listed, day);
  } else {
    want = listed.filter((e) => e >= day && dte(day, e) <= (o.days ?? 45));
  }
  // An expiry that closed today has no gamma left.
  want = want.filter((e) => !(e === day && afterClose));
  if (!want.length) throw new IncompleteChain([`no ${ticker} expiries to read`]);
  const span = Math.max(...want.map((e) => dte(day, e)));
  const q = (ep: string, e: string) => `/v3/option/snapshot/${ep}?symbol=${ticker}&expiration=${e}`;
  // A handful of named expiries one by one; a window (or a long list) in one call, cut to the ones wanted.
  const all = (ep: string, extra = '') => (o.expiries?.length && want.length <= 3) || span > 400
    ? Promise.all(want.map((e) => theta(q(ep, e.replaceAll('-', '')) + extra))).then((xs) => xs.flat())
    : theta(q(ep, '*') + `&max_dte=${span}` + extra).then((xs) => xs.filter((r) => want.includes(String(r.contract.expiration))));
  // The stock price is read from the two nearest expiries, whichever ones were asked for: a far
  // expiry's call - put carries the dividends paid before it (NKE January read 37.09 against 37.40,
  // 23 Oct 2026). Their quotes are fetched for the price only when they are not in the run.
  const nearest2 = listed.filter((e) => e >= day && !(e === day && afterClose)).slice(0, 2);
  const extra = nearest2.filter((e) => !want.includes(e));
  // Named expiries one call at a time: Theta's Standard plan refuses many at once (429, 24 Oct 2026).
  const each = async (paths: string[]) => { const out: Row[] = []; for (const p of paths) out.push(...(await theta(p))); return out; };
  const eodOf = (es: string[]) => each(es.map((e) => `/v3/option/history/eod?symbol=${ticker}&expiration=${e.replaceAll('-', '')}&start_date=${D}&end_date=${D}`));
  const [ivs, ois, ohlc, extraIvs] = named
    ? await (async () => { const q = await eodOf(want);
        const oi = await each(want.map((e) => `/v3/option/history/open_interest?symbol=${ticker}&expiration=${e.replaceAll('-', '')}&date=${D}`));
        return [q, oi, q, await eodOf(extra)]; })()
    : o.asOf
    ? [hist.filter((r) => want.includes(String(r.contract.expiration))),
       (await theta(`/v3/option/history/open_interest?symbol=${ticker}&expiration=*&date=${D}`)).filter((r) => want.includes(String(r.contract.expiration))),
       hist, hist.filter((r) => extra.includes(String(r.contract.expiration)))]
    // Today's volume is only there on a trading day (a weekend run reads none: Theta 472, 24 Oct 2026).
    : await Promise.all([all('greeks/implied_volatility'), all('open_interest'), all('ohlc', '&current_day_only=true').catch(() => [] as Row[]),
      Promise.all(extra.map((e) => theta(q('greeks/implied_volatility', e.replaceAll('-', ''))))).then((xs) => xs.flat())]);
  const oi = new Map(ois.map((r) => [key(r.contract), Number((r.data ?? []).at(-1)?.open_interest ?? 0)]));
  const vol = new Map(ohlc.map((r) => [key(r.contract), Number((r.data ?? []).at(-1)?.volume ?? 0)]));
  // Mids (two-sided quotes only), then the stock price they imply: the median of each nearest expiry's
  // at-the-money call - put + K e^(-rT). Each IV is then solved from its own mid.
  const now = nowMs;
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
  return { chain: { ticker, spot, expiries: want, contracts }, warnings, nowMs, day };
}

async function run(ticker: string, days: number, expiries?: string[], pct?: number, save = true, asOf?: string) {
  const { chain, warnings: w0, nowMs, day } = await loadChain(ticker, { days, expiries, asOf });
  const b = buildStrikes(chain, { nowMs });
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

/** One row per expiry (handoff 31, 13d): each expiry's own walls, flip, sleeping walls and strikes, saved
    for the day in place of any earlier run's. A failed expiry (too little quoted) is named, the rest saved. */
async function runExpiries(ticker: string, asOf?: string, save = true, expiries?: string[]) {
  const { chain, warnings, nowMs, day } = await loadChain(ticker, expiries?.length ? { expiries, asOf } : { pick: logged, asOf });
  const rows: Row[] = [], errors: string[] = [];
  const m = (v: number | undefined) => v == null ? null : Math.round(v);
  for (const e of chain.expiries) {
    try {
      const b = buildStrikes({ ...chain, expiries: [e], contracts: chain.contracts.filter((c) => c.exp === e) }, { nowMs });
      const w = findWalls(b.rows, chain.spot), flip = zeroGamma(b.legs, chain.spot), sl = sleeping(b.legs, chain.spot, w);
      const oi = new Map<number, { c: number; p: number }>();
      for (const l of b.legs) { const x = oi.get(l.k) ?? { c: 0, p: 0 }; x.c += l.coi; x.p += l.poi; oi.set(l.k, x); }
      // The strikes nearest the price, plus every wall and sleeping strike wherever it sits.
      const keep = new Set<number>([...nearest(b.rows, chain.spot, 16).map((r) => r.k), ...w.call.map((r) => r.k), ...w.put.map((r) => r.k),
        ...(sl.call ? [sl.call.k] : []), ...(sl.put ? [sl.put.k] : [])]);
      const net = b.rows.reduce((s, r) => s + r.netGex, 0);
      rows.push({ day, ticker, expiry: e, days: null, expiries: [e], spot: chain.spot, net_gex: Math.round(net), flip,
        call_wall: w.call[0]?.k ?? null, call_wall_gex: m(w.call[0]?.callGex), call_wall2: w.call[1]?.k ?? null, call_wall2_gex: m(w.call[1]?.callGex),
        put_wall: w.put[0]?.k ?? null, put_wall_gex: m(w.put[0]?.putGex), put_wall2: w.put[1]?.k ?? null, put_wall2_gex: m(w.put[1]?.putGex),
        sleep: sl, fresh: b.rows.filter(isFresh).map((r) => r.k),
        filled_oi_pct: b.totalOi ? +(b.filledOi / b.totalOi * 100).toFixed(2) : 0,
        summary: summaryLine(day, ticker, chain.spot, net, flip, w).replace(` ${ticker} `, ` ${ticker} ${e} `),
        strikes: b.rows.filter((r) => keep.has(r.k)).map((r) => ({ k: r.k, call: Math.round(r.callGex), put: Math.round(r.putGex),
          net: Math.round(r.netGex), coi: oi.get(r.k)?.c ?? 0, poi: oi.get(r.k)?.p ?? 0, oi: r.oi, vol: r.vol, fresh: isFresh(r) })) });
    } catch (err) {
      errors.push(`${e}: ${err instanceof IncompleteChain ? err.problems.join('; ') : String((err as Error).message)}`);
    }
  }
  if (save && rows.length) {
    await db(`gex_walls?ticker=eq.${ticker}&day=eq.${day}&expiry=not.is.null`, { method: 'DELETE' });
    await db('gex_walls', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify(rows) });
  }
  return { ticker, day, spot: chain.spot, saved: rows.map((r) => `${r.expiry} c ${r.call_wall}/${r.call_wall2} p ${r.put_wall}/${r.put_wall2}`),
    rows: rows.map((r) => ({ expiry: r.expiry, flip: r.flip, net_gex: r.net_gex,
      call: [[r.call_wall, r.call_wall_gex], [r.call_wall2, r.call_wall2_gex]], put: [[r.put_wall, r.put_wall_gex], [r.put_wall2, r.put_wall2_gex]], sleep: r.sleep })),
    errors, warnings };
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
  let body: { ticker?: string; tickers?: string[]; days?: number | string[]; expiries?: string[]; target?: number; save?: boolean;
    mode?: string; per_expiry?: boolean; as_of?: string } = {};
  // A body that does not parse is refused: it used to fall through to the daily save (24 Oct 2026, a
  // malformed request on a Saturday wrote the book's rows for a day with no session).
  if (req.method === 'POST') {
    const raw = await req.text();
    if (raw.trim()) { try { body = JSON.parse(raw); } catch { return json({ ok: false, error: 'body is not JSON' }, 400); } }
  }
  const days = Math.max(1, Math.min(400, Number(Array.isArray(body.days) ? 45 : body.days ?? 45)));
  const book = async () => Object.keys((await db('home_snapshot?id=eq.1&select=s:payload->strategies'))[0]?.s ?? {}).sort();
  try {
    if (body.mode === 'backfill') {
      const sessions = Array.isArray(body.days) ? body.days : [];
      const names = body.tickers?.length ? body.tickers : await book();
      const results = [];
      for (const d of sessions) for (const t of names) {
        try { results.push(await runExpiries(t.toUpperCase(), d, body.save ?? true)); }
        catch (e) { results.push({ ticker: t, day: d, error: e instanceof IncompleteChain ? e.problems : String((e as Error).message) }); }
      }
      return json({ ok: results.every((r) => !('error' in r) && !(r as Row).errors?.length), results });
    }
    if (body.ticker && body.per_expiry) return json({ ok: true, ...(await runExpiries(body.ticker.toUpperCase(), body.as_of, body.save ?? true, body.expiries)) });
    if (body.mode === 'daily') {
      const { day } = nyNow();
      const wd = new Date(day + 'T12:00:00Z').getUTCDay();
      const closed = wd === 0 || wd === 6 || (await db(`market_calendar?date=eq.${day}&kind=eq.closed&select=date`)).length > 0;
      if (closed) return json({ ok: true, day, skipped: 'market closed' });
      // The open names: Home's strategy map has one key per name with a leg (the chain table can
      // hold a closed name, and a read of it caps at 1,000 rows).
      const names = body.tickers?.length ? body.tickers : await book();
      // Each expiry on its own for the book only (the market names keep the combined row).
      const perExpiry = body.per_expiry ?? !body.tickers?.length;
      const results: Row[] = [];
      for (const t of names) {
        try { const r = await run(t.toUpperCase(), days, undefined, undefined, body.save ?? true); results.push({ ticker: t, summary: r.summary }); }
        catch (e) { results.push({ ticker: t, error: e instanceof IncompleteChain ? e.problems : String((e as Error).message) }); }
        if (perExpiry) {
          try { const r = await runExpiries(t.toUpperCase(), undefined, body.save ?? true); results.push({ ticker: t, expiries: r.saved, ...(r.errors.length ? { error: r.errors } : {}) }); }
          catch (e) { results.push({ ticker: t, error: e instanceof IncompleteChain ? e.problems : String((e as Error).message) }); }
        }
      }
      return json({ ok: results.every((r) => !('error' in r)), day, results });
    }
    if (!body.ticker) return json({ ok: false, error: 'ticker, or mode daily or backfill, is required' }, 400);
    return json(await run(body.ticker.toUpperCase(), days, body.expiries, body.target, body.save ?? true, body.as_of));
  } catch (e) {
    if (e instanceof IncompleteChain) return json({ ok: false, error: 'incomplete chain', problems: e.problems }, 422);
    if (e instanceof ThetaError) return json({ ok: false, error: e.message }, 502);
    return json({ ok: false, error: String((e as Error).message ?? e) }, 500);
  }
});
