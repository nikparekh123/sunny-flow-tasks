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
import { aggregate, aggregateStream, csvPrints, medianSize, Print, seedOf, step } from './tape.ts';
import { Bar, centre, DContract, dealerFlip, dealerStrikes, dealerWalls, DWall, Label, median, netAt, regime, track } from './gamma.ts';

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
    // 472 is "no data found": nothing traded or listed for that request, an empty answer, not a failure.
    if (r.status === 472) { await r.body?.cancel(); return []; }
    if (!r.ok) throw new ThetaError(`Theta ${r.status} on ${path.split('?')[0]}: ${(await r.text()).slice(0, 200)}`);
    return ((await r.json())?.response ?? []) as Row[];
  }
}

/** The same as CSV, as a stream (the tape: TSLA's weekly is about 40,000 prints a day). null when Theta has none. */
async function thetaCsv(path: string): Promise<ReadableStream<Uint8Array> | null> {
  for (let i = 0; ; i++) {
    const r = await fetch(`${THETA_URL}${path}&format=csv`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(120_000) });
    if (r.status === 429 && i < 3) { await r.body?.cancel(); await new Promise((f) => setTimeout(f, 1000 * 2 ** i)); continue; }
    if (r.status === 472) { await r.body?.cancel(); return null; }
    if (!r.ok) throw new ThetaError(`Theta ${r.status} on ${path.split('?')[0]}: ${(await r.text()).slice(0, 200)}`);
    return r.body;
  }
}

async function db(path: string, init?: RequestInit): Promise<Row[]> {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, { ...init,
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json', ...(init?.headers ?? {}) } });
  if (!r.ok) throw new Error(`db ${r.status} on ${path.split('?')[0]}: ${(await r.text()).slice(0, 200)}`);
  // An upsert that only updates answers 200 with no body (return=minimal): an empty answer, not JSON.
  const text = await r.text();
  return text.trim() ? JSON.parse(text) : [];
}

/** Every row of a read, 1,000 at a time (PostgREST caps a read at 1,000 rows, silently). `path` carries its order. */
async function dbAll(path: string): Promise<Row[]> {
  const out: Row[] = [];
  for (let off = 0; ; off += 1000) {
    const page = await db(`${path}&limit=1000&offset=${off}`);
    out.push(...page);
    if (page.length < 1000) return out;
  }
}
/** Upsert in chunks of 1,000. */
async function upsert(table: string, conflict: string, rows: Row[]) {
  for (let i = 0; i < rows.length; i += 1000) {
    await db(`${table}?on_conflict=${conflict}`, { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows.slice(i, i + 1000)) });
  }
}

/** Today in New York, and whether its 4 PM close has passed. */
function nyNow(): { day: string; afterClose: boolean } {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit',
    day: '2-digit', hour: '2-digit', hourCycle: 'h23' }).formatToParts(new Date()).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, afterClose: Number(p.hour) >= 16 };
}
const dte = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / 864e5);
const addDays = (d: string, n: number) => new Date(Date.parse(d + 'T12:00:00Z') + n * 864e5).toISOString().slice(0, 10);
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


// ════════════════════════════════════════════════════════════════════════════════════════════════
// THE TAPE AND DEALER GAMMA (handoff 32, 25 Oct 2026). 'tape' reads one session's prints for a name, by
// expiry; 'gamma' moves the running dealer positions on by that session and builds the Gamma page's views.
// A backfill calls both for each past session in order (positions depend on the day before).
// ════════════════════════════════════════════════════════════════════════════════════════════════

/** The hedge expiry: January 2027, then March, June, September, December, each until it is under 8 weeks out
    (Nik, 23 Oct 2026; the same rule as chain-next). */
function hedgeExpiry(fut: string[], day: string): string | null {
  return fut.filter((e) => e >= '2027-01-01' && isMonthly(e) && (e.startsWith('2027-01') || [3, 6, 9, 12].includes(Number(e.slice(5, 7))))
    && dte(day, e) >= 56).sort()[0] ?? null;
}
/** A week's expiry: a Friday, or the Thursday before a holiday Friday (no Friday listed that week). */
function weekEnd(e: string, listed: string[]): boolean {
  const wd = new Date(e + 'T12:00:00Z').getUTCDay();
  if (wd === 5) return true;
  if (wd !== 4) return false;
  const fri = new Date(Date.parse(e + 'T12:00:00Z') + 864e5).toISOString().slice(0, 10);
  return !listed.includes(fri);
}
/** The expiries the tape follows on a day: every week's expiry within 45 days, the monthlies within 186 (the hedge
    rungs, 26 Oct 2026: near 45-90 days and far 90-180 days, any monthly; was 100), and the hedge expiry. Monday and
    Wednesday expiries (TSLA) are left out. */
function tracked(listed: string[], day: string): { all: string[]; weeklies: string[]; near: string[]; hedge: string | null } {
  const fut = listed.filter((e) => e > day).sort();
  const near = fut.filter((e) => weekEnd(e, listed) && dte(day, e) <= 45);
  const weeklies = fut.filter((e) => weekEnd(e, listed) && !isMonthly(e)).slice(0, 3);
  const hedge = hedgeExpiry(fut, day);
  const all = [...new Set([...near, ...fut.filter((e) => isMonthly(e) && dte(day, e) <= 186), ...(hedge ? [hedge] : [])])].sort();
  return { all, weeklies, near, hedge };
}

/** The stock's close that day (Theta's end of day), else its live price. */
async function spotOn(ticker: string, day: string): Promise<number | null> {
  const D = day.replaceAll('-', '');
  const r = await theta(`/v3/stock/history/eod?symbol=${ticker}&start_date=${D}&end_date=${D}`);
  const c = Number((r[0] as Row)?.close ?? r.at(-1)?.close);
  if (c > 0) return c;
  const q = await db(`ticker_quotes_live?ticker=eq.${ticker}&select=spot`);
  return Number(q[0]?.spot) || null;
}

/** One session's tape for a name: per contract (strikes within 40% of the price) and per expiry. */
async function tapeDay(ticker: string, day: string, only?: string[]) {
  const listed = (await theta(`/v3/option/list/expirations?symbol=${ticker}`)).map((x) => String(x.expiration)).sort();
  const tr = tracked(listed, day), D = day.replaceAll('-', '');
  if (only?.length) tr.all = tr.all.filter((e) => only.includes(e));
  const spot = await spotOn(ticker, day);
  const band: [number, number] | undefined = spot ? [spot * 0.6, spot * 1.4] : undefined;
  const contracts: Row[] = [], expiries: Row[] = [];
  for (const e of tr.all) {
    const E = e.replaceAll('-', '');
    const body = await thetaCsv(`/v3/option/history/trade_quote?symbol=${ticker}&expiration=${E}&date=${D}`);
    const agg = body ? await aggregateStream(csvPrints(body), band) : aggregate([], band);
    const ois = await theta(`/v3/option/history/open_interest?symbol=${ticker}&expiration=${E}&date=${D}`);
    const oi = new Map<string, number>();
    for (const r of ois) {
      const k = Number(r.contract.strike), cp = r.contract.right === 'CALL' ? 'C' : 'P';
      if (band && (k < band[0] || k > band[1])) continue;
      oi.set(`${k}|${cp}`, Number((r.data ?? []).at(-1)?.open_interest ?? 0));
    }
    const seen = new Set<string>();
    for (const c of agg.contracts) {
      const kk = `${c.k}|${c.cp}`; seen.add(kk);
      contracts.push({ ticker, day, expiry: e, strike: c.k, cp: c.cp, vol: c.vol, cust_buy: +c.buy.toFixed(2), cust_sell: +c.sell.toFixed(2),
        unclassified: +c.uncl.toFixed(2), oi: oi.get(kk) ?? 0 });
    }
    for (const [kk, n] of oi) {
      if (seen.has(kk) || !n) continue;
      const [k, cp] = kk.split('|');
      contracts.push({ ticker, day, expiry: e, strike: Number(k), cp, vol: 0, cust_buy: 0, cust_sell: 0, unclassified: 0, oi: n });
    }
    const d = agg.day;
    expiries.push({ ticker, day, expiry: e, vol: d.vol, classified: +d.classified.toFixed(2), trades: d.trades, small_trades: d.small,
      call_vol: d.callVol, put_vol: d.putVol, sizes: d.sizes, v_single: d.byKind.single, v_multi: d.byKind.multi, v_tied: d.byKind.tied,
      v_auction: d.byKind.auction, v_other: d.byKind.other, built_at: new Date().toISOString() });
  }
  await upsert('tape_contract_day', 'ticker,day,expiry,strike,cp', contracts);
  await upsert('tape_expiry_day', 'ticker,day,expiry', expiries);
  const vol = expiries.reduce((a, x) => a + x.vol, 0), cls = expiries.reduce((a, x) => a + x.classified, 0);
  return { ticker, day, spot, expiries: tr.all, contracts: contracts.length, vol, coverage: vol ? +(cls / vol).toFixed(3) : null };
}

/** The day's tape in parts, two expiries per call, each call its own worker: one call for every expiry ran out of
    compute on TSLA's busiest days (546 WORKER_RESOURCE_LIMIT on 3 and 17 Sep, 26 Oct 2026). Rows are keyed per
    expiry, so the parts add up to the whole day. */
async function tapeSplit(ticker: string, day: string) {
  const listed = (await theta(`/v3/option/list/expirations?symbol=${ticker}`)).map((x) => String(x.expiration)).sort();
  const all = tracked(listed, day).all;
  let contracts = 0, vol = 0, cls = 0, spot: number | null = null;
  for (let i = 0; i < all.length; i += 2) {
    const part = all.slice(i, i + 2);
    let j: Row = {};
    for (let a = 0; a < 3; a++) {
      const r = await fetch(`${SB_URL}/functions/v1/gex-walls`, { method: 'POST',
        headers: { Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: 'tape', ticker, as_of: day, expiries: part }) });
      j = await r.json().catch(() => ({ ok: false, error: `status ${r.status}` }));
      if (j.ok) break;
      await new Promise((res) => setTimeout(res, 5000 * (a + 1)));
    }
    if (!j.ok) throw new Error(`tape ${ticker} ${day} ${part.join(',')}: ${JSON.stringify(j.error ?? j).slice(0, 200)}`);
    contracts += Number(j.contracts ?? 0); vol += Number(j.vol ?? 0); cls += Number(j.vol ?? 0) * Number(j.coverage ?? 0); spot = j.spot ?? spot;
  }
  return { ticker, day, spot, expiries: all, contracts, vol, coverage: vol ? +(cls / vol).toFixed(3) : null, parts: Math.ceil(all.length / 2) };
}

const sessionsBack = (days: string[], day: string, n: number) => days.filter((d) => d < day).sort().reverse()[n - 1] ?? null;

/** Move the dealer positions on by one session, then build the Gamma page's views for it. */
async function gammaDay(ticker: string, day: string, live = false, withTrack = true, positionsOnly = false) {
  const tape = await dbAll(`tape_contract_day?ticker=eq.${ticker}&day=eq.${day}&select=expiry,strike,cp,vol,cust_buy,cust_sell,unclassified,oi&order=expiry,strike,cp`);
  if (!tape.length) throw new IncompleteChain([`no tape stored for ${ticker} on ${day}: run mode tape first`]);
  const held = await dbAll(`dealer_pos?ticker=eq.${ticker}&select=expiry,strike,cp,pos,seed,tape_vol,classified_vol,cum_buy,cum_sell,oi,asof&order=expiry,strike,cp`);
  const P = new Map(held.map((r) => [`${r.expiry}|${Number(r.strike)}|${r.cp}`, r]));
  const moved: Row[] = [];
  for (const r of tape) {
    const kk = `${r.expiry}|${Number(r.strike)}|${r.cp}`, p = P.get(kk);
    if (p && String(p.asof) >= day) continue;                 // this session is already in
    const oi = Number(r.oi ?? 0), vol = Number(r.vol);
    // First sight: whatever was already open is seeded from the open-interest model (Nik, 25 Oct 2026).
    const seed = p ? Number(p.seed) : seedOf(r.cp, oi);
    const pos = step(p ? Number(p.pos) : seed, { buy: Number(r.cust_buy), sell: Number(r.cust_sell) }, oi + vol);
    const row = { ticker, expiry: r.expiry, strike: Number(r.strike), cp: r.cp, pos: +pos.toFixed(2), seed,
      tape_vol: +(Number(p?.tape_vol ?? 0) + vol).toFixed(2), classified_vol: +(Number(p?.classified_vol ?? 0) + vol - Number(r.unclassified)).toFixed(2),
      // Readable buys and sells since tracking began, for one-sidedness (26 Oct 2026).
      cum_buy: +(Number(p?.cum_buy ?? 0) + Number(r.cust_buy)).toFixed(2), cum_sell: +(Number(p?.cum_sell ?? 0) + Number(r.cust_sell)).toFixed(2),
      oi, asof: day };
    moved.push(row); P.set(kk, row);
  }
  if (!live) {
    await upsert('dealer_pos', 'ticker,expiry,strike,cp', moved);
    await db(`dealer_pos?ticker=eq.${ticker}&expiry=lte.${day}`, { method: 'DELETE' });   // expired
  }
  /* Positions only: a past session replayed for expiries newly tracked (the far hedge rungs, 26 Oct 2026). The
     stored views of that day stay as they were; every other expiry is already past it (the asof guard). */
  if (positionsOnly) return { ticker, day, positions: moved.length };
  // The chain at that close (or now, live): IVs, time left, the price the quotes imply.
  const exps = [...new Set(tape.map((r) => String(r.expiry)))].filter((e) => e > day).sort();
  const { chain, nowMs } = await loadChain(ticker, live ? { expiries: exps } : { expiries: exps, asOf: day });
  const spot = chain.spot;
  const ivAt = new Map<string, number>();
  for (const c of chain.contracts) if (c.iv) ivAt.set(`${c.exp}|${c.k}|${c.right}`, c.iv);
  const cs: DContract[] = [];
  for (const [kk, p] of P) {
    const [exp, k, cp] = kk.split('|');
    if (exp <= day || !exps.includes(exp)) continue;
    const iv = ivAt.get(kk) ?? ivAt.get(`${exp}|${k}|${cp === 'C' ? 'P' : 'C'}`);
    if (!iv) continue;
    cs.push({ exp, k: Number(k), cp: cp as 'C' | 'P', T: yearsTo(exp, nowMs), iv, pos: Number(p.pos), oi: Number(p.oi ?? 0),
      seed: Number(p.seed), tapeVol: Number(p.tape_vol), classifiedVol: Number(p.classified_vol),
      buy: Number(p.cum_buy ?? 0), sell: Number(p.cum_sell ?? 0) });
  }
  // The day's coverage: the share of its volume classified by side; the print types; and the flow inputs over
  // the last 20 sessions (volume under 7 days to expiry, calls to puts, the median trade, trades of 10 or fewer).
  const ed = await db(`tape_expiry_day?ticker=eq.${ticker}&day=eq.${day}&select=vol,classified,v_single,v_multi,v_tied,v_auction,v_other`);
  const tv = ed.reduce((a, x) => a + Number(x.vol), 0), coverage = tv ? ed.reduce((a, x) => a + Number(x.classified), 0) / tv : null;
  const sumK = (k: string) => ed.reduce((a, x) => a + Number(x[k] ?? 0), 0);
  const prints = tv ? Object.fromEntries(['single', 'multi', 'tied', 'auction', 'other'].map((k) => [k, +(sumK(`v_${k}`) / tv).toFixed(3)])) : null;
  const f20 = await dbAll(`tape_expiry_day?ticker=eq.${ticker}&day=lte.${day}&day=gte.${new Date(Date.parse(day) - 30 * 864e5).toISOString().slice(0, 10)}`
    + '&select=day,expiry,vol,trades,small_trades,call_vol,put_vol,sizes&order=day.desc,expiry');
  const fDays = [...new Set(f20.map((r) => String(r.day)))].slice(0, 20), fr = f20.filter((r) => fDays.includes(String(r.day)));
  const fVol = fr.reduce((a, r) => a + Number(r.vol), 0), fTrades = fr.reduce((a, r) => a + Number(r.trades), 0);
  const sizes: Record<string, number> = {};
  for (const r of fr) for (const [k, n] of Object.entries((r.sizes ?? {}) as Record<string, number>)) sizes[k] = (sizes[k] ?? 0) + Number(n);
  const flow = fVol ? { sessions: fDays.length,
    under7: +(fr.filter((r) => dte(String(r.day), String(r.expiry)) < 7).reduce((a, r) => a + Number(r.vol), 0) / fVol).toFixed(3),
    callPut: +(fr.reduce((a, r) => a + Number(r.call_vol), 0) / Math.max(1, fr.reduce((a, r) => a + Number(r.put_vol), 0))).toFixed(2),
    median: medianSize(sizes), small: fTrades ? +(fr.reduce((a, r) => a + Number(r.small_trades), 0) / fTrades).toFixed(3) : null } : null;
  // The views: each expiry, the next three weeklies together, and everything within 45 days.
  const listed = (await theta(`/v3/option/list/expirations?symbol=${ticker}`)).map((x) => String(x.expiration)).sort();
  const tr = tracked(listed, day);
  const views: [string, string[]][] = [...exps.map((e) => [e, [e]] as [string, string[]]),
    ['weeklies', tr.weeklies.filter((e) => exps.includes(e))], ['all', tr.near.filter((e) => exps.includes(e))]];
  const prev = await dbAll(`gamma_view_day?ticker=eq.${ticker}&day=lt.${day}&day=gte.${new Date(Date.parse(day) - 12 * 864e5).toISOString().slice(0, 10)}`
    + '&select=day,view,data&order=day.desc,view');
  const prevDays = [...new Set(prev.map((r) => String(r.day)))];
  const out: Row[] = [];
  for (const [view, ve] of views) {
    if (!ve.length) continue;
    const vc = cs.filter((c) => ve.includes(c.exp));
    const rows = dealerStrikes(vc, spot);
    const yRow = prev.find((r) => r.view === view && r.day === prevDays[0]);
    const yWalls: DWall[] = yRow?.data?.walls ?? [];
    // A normal wall for the name: the median size of this view's walls over the stored sessions (up to 12 days).
    const normal = median(prev.filter((r) => r.view === view).flatMap((r) => ((r.data?.walls ?? []) as DWall[]).map((w) => Math.abs(w.gex))));
    const walls = dealerWalls(rows, spot, { coverage, normal, held: (k: number, label: Label) => {
      const w = yWalls.find((x) => x.k === k && x.label === label); return w ? w.held + 1 : 1; } });
    // The move the nearest expiry prices, 1 and 1.5 SD, at the IV of the strike nearest the price.
    const first = ve[0], atm = vc.filter((c) => c.exp === first).sort((a, b) => Math.abs(a.k - spot) - Math.abs(b.k - spot))[0];
    const sd = atm ? spot * atm.iv * Math.sqrt(atm.T) : null;
    // A week ago: five sessions back, the same view.
    const wDay = sessionsBack(prevDays, day, 5), wRow = prev.find((r) => r.view === view && r.day === wDay);
    const four = (ws: DWall[]) => ws.filter((w) => w.rank <= 2);
    const c0 = wRow ? centre(four(wRow.data.walls)) : null, c1 = centre(four(walls));
    const total = rows.reduce((a, r) => a + Math.abs(r.gex), 0);
    const nextExp = ve[0];
    out.push({ ticker, day, view, built_at: new Date().toISOString(), data: {
      spot: +spot.toFixed(3), expiries: ve, coverage: coverage == null ? null : +coverage.toFixed(3),
      ...(view === 'weeklies' ? { prints, flow } : {}),
      flip: dealerFlip(vc, spot), regime: regime(vc, spot), net: Math.round(netAt(vc, spot)),
      priced: sd ? { exp: first, sd1: +sd.toFixed(3), sd1_pct: +(sd / spot * 100).toFixed(2), sd15: +(1.5 * sd).toFixed(3) } : null,
      walls,
      // All: the share of dealer gamma that expires next (the roll-off).
      rolloff: view === 'all' && total > 0 ? { exp: nextExp, share: +(rows.reduce((a, r) => a + Math.abs(r.byExp[nextExp] ?? 0), 0) / total).toFixed(3) } : null,
      drift: c0 && c1 ? { from: +c0.toFixed(3), to: +c1.toFixed(3), pct: +((c1 / c0 - 1) * 100).toFixed(2), since: wDay } : null,
      week: wRow ? (wRow.data.walls as DWall[]).map((w) => ({ side: w.side, rank: w.rank, k: w.k, gex: w.gex, label: w.label,
        exp: Object.entries(w.byExp ?? {}).sort((a, b) => Math.abs(Number(b[1])) - Math.abs(Number(a[1])))[0]?.[0] ?? null })) : null,
    } });
  }
  // Live (during the session): the views are saved for today, the positions are not moved on (the close does that).
  // At the close: how the labels have held, on the Weeklies view (handoff 32, brief 15).
  if (!live && withTrack) {
    const wk = out.find((r) => r.view === 'weeklies');
    if (wk) { try { wk.data.track = await trackFor(ticker, day, { day, spot, walls: wk.data.walls }); } catch (e) { console.error('track', ticker, (e as Error).message); } }
  }
  await upsert('gamma_view_day', 'ticker,day,view', out);
  return { ticker, day, spot, positions: moved.length, contracts: cs.length, coverage, views: out.map((r) => `${r.view}: ` + (r.data.walls as DWall[])
    .map((w) => `${w.side[0]}${w.rank} ${w.k} ${w.label}${'●'.repeat(w.conf)}`).join(' ')), out: live ? out : undefined };
}

/** Daily high, low and close from Theta's hourly bars (regular session; a bar with no trades or a zero price is skipped). */
async function dailyBars(ticker: string, from: string, to: string): Promise<Bar[]> {
  // Theta serves a month of bars per request at most: 28-day pieces, one at a time.
  const rows: Row[] = [];
  for (let a = from; a <= to; a = addDays(a, 28)) {
    const e = addDays(a, 27) < to ? addDays(a, 27) : to;
    rows.push(...(await theta(`/v3/stock/history/ohlc?symbol=${ticker}&start_date=${a.replaceAll('-', '')}&end_date=${e.replaceAll('-', '')}&interval=1h`)));
  }
  const by = new Map<string, Bar>();
  for (const b of rows) {
    if (!Number(b.count) || Math.min(Number(b.open), Number(b.high), Number(b.low), Number(b.close)) <= 0) continue;
    const d = String(b.timestamp).slice(0, 10), x = by.get(d);
    if (!x) by.set(d, { d, h: Number(b.high), l: Number(b.low), c: Number(b.close) });
    else { x.h = Math.max(x.h, Number(b.high)); x.l = Math.min(x.l, Number(b.low)); x.c = Number(b.close); }
  }
  return [...by.values()].sort((a, b) => a.d.localeCompare(b.d));
}

/** The track record from every stored Weeklies view to `day` (plus today's, not stored yet), against the
    daily bars since the first. Sessions counts the views, so the app can show "Building: N of 45". */
async function trackFor(ticker: string, day: string, todayView?: { day: string; spot: number; walls: unknown }) {
  const stored = await dbAll(`gamma_view_day?ticker=eq.${ticker}&view=eq.weeklies&day=lt.${day}&select=day,spot:data->spot,walls:data->walls&order=day`);
  const views = [...stored, ...(todayView ? [todayView] : [])].map((v) => ({ day: String(v.day), spot: Number(v.spot),
    walls: ((v.walls ?? []) as Row[]).map((w) => ({ side: String(w.side), k: Number(w.k), label: String(w.label) })) }));
  if (!views.length) return { sessions: 0, rows: [] };
  const bars = await dailyBars(ticker, views[0].day, day);
  return { sessions: views.length, asof: day, rows: track(views, bars) };
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
    mode?: string; per_expiry?: boolean; as_of?: string; live?: boolean; split?: boolean; no_track?: boolean; positions_only?: boolean } = {};
  // A body that does not parse is refused: it used to fall through to the daily save (24 Oct 2026, a
  // malformed request on a Saturday wrote the book's rows for a day with no session).
  if (req.method === 'POST') {
    const raw = await req.text();
    if (raw.trim()) { try { body = JSON.parse(raw); } catch { return json({ ok: false, error: 'body is not JSON' }, 400); } }
  }
  const days = Math.max(1, Math.min(400, Number(Array.isArray(body.days) ? 45 : body.days ?? 45)));
  const book = async () => Object.keys((await db('home_snapshot?id=eq.1&select=s:payload->strategies'))[0]?.s ?? {}).sort();
  try {
    if (body.mode === 'tape' && body.ticker) {
      const t = body.ticker.toUpperCase(), d = body.as_of ?? nyNow().day;
      return json({ ok: true, ...(body.split ? await tapeSplit(t, d) : await tapeDay(t, d, body.expiries)) });
    }
    /* The scheduled run, one name per call: today's tape, then the gamma views. After the close it moves the
       positions on; during the session (live) it only refreshes today's views. Weekends and holidays skip. */
    if (body.mode === 'tape_gamma' && body.ticker) {
      const { day } = nyNow();
      const wd = new Date(day + 'T12:00:00Z').getUTCDay();
      if (wd === 0 || wd === 6 || (await db(`market_calendar?date=eq.${day}&kind=eq.closed&select=date`)).length) return json({ ok: true, day, skipped: 'market closed' });
      // Positions move on only from 18:00 New York, once Theta's end of day is complete; earlier runs are live.
      const hour = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hourCycle: 'h23' }).format(new Date()));
      const t = body.ticker.toUpperCase(), a = await tapeSplit(t, day), b = await gammaDay(t, day, hour < 18);
      return json({ ok: true, day, live: hour < 18, tape: { contracts: a.contracts, coverage: a.coverage }, gamma: b.views });
    }
    // A backfill skips the track record on past days (no_track): only the last day's is read.
    if (body.mode === 'gamma' && body.ticker) return json({ ok: true, ...(await gammaDay(body.ticker.toUpperCase(), body.as_of ?? nyNow().day, !!body.live, !body.no_track, !!body.positions_only)) });
    /* The track record now, onto the latest stored Weeklies view (the close job does this every night). */
    if (body.mode === 'track' && body.ticker) {
      const t = body.ticker.toUpperCase();
      const [last] = await db(`gamma_view_day?ticker=eq.${t}&view=eq.weeklies&select=day,data&order=day.desc&limit=1`);
      if (!last) return json({ ok: false, error: `no Weeklies view for ${t}` }, 404);
      const tr = await trackFor(t, String(last.day), { day: String(last.day), spot: Number(last.data.spot), walls: last.data.walls });
      await db(`gamma_view_day?ticker=eq.${t}&view=eq.weeklies&day=eq.${last.day}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ data: { ...last.data, track: tr } }) });
      return json({ ok: true, ticker: t, day: last.day, track: tr });
    }
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
