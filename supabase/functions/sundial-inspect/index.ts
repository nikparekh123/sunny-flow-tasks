/**
 * sundial-inspect: the inspector (Nik, 27 Nov 2026: "another layer of audit, almost like a managerial layer ... think of
 * it as a random inspection"). Once a trading day, at a time picked at random from the date, it inspects EVERY name
 * Sundial covers, working each one out again on its own: its own data reads, its own option maths (a different normal
 * curve and IV solver), its own count search, and the rules written out again from docs/SUNDIAL.md. It shares no code
 * with the engine (_shared/sundial.ts), so a mistake in the engine's maths or plumbing shows up as a disagreement.
 *
 * Per name it checks:
 *   settings   the engine's settings against what Nik agreed (test size, cadence, puts, cap, earnings, early close, drop)
 *   reads      this week's move, the 50- and 200-day trend, IV rich or cheap, against the card's words
 *   strike     the call and put distance from the 11 Nov tables, and the strike on the listed chain
 *   count      the calls the test allows (and the expiry cap), the puts the rule allows, against the board
 *   drop       the 2 and 3 daily SD lines
 *   earnings   no calls (or nothing, for the weekly names) on an expiry spanning a report; report dates on file
 *   credit     quantity x the real mid
 *   delta      the book's delta now and at +1 weekly SD (a problem if it is below zero now)
 *   health     price under 2 minutes old in the session, IV saved lately, IBKR synced in the last 30 minutes
 * Saved in sundial_inspections; a run with problems pushes Nik. POST { force: true } runs it now (the scheduler's key).
 * Then sundial-review (part 3) writes Claude's review of the run on the same row; a forced run asks for one only with
 * { force: true, review: true }.
 *
 * ⚠ DEPLOY WITH verify_jwt = false: the scheduler sends x-cron-key (vault cron_secret). No em dashes in any words here.
 */
const URL_ = Deno.env.get('SUPABASE_URL')!;
const SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const NIK = '85dd190f-9381-4acf-b123-7f1f6f778947';
const BUILD = '2026-11-27.5';
type Row = Record<string, any>;
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });

// ── What Nik agreed, written out again from docs/SUNDIAL.md (not read from the engine) ──
type Agreed = { book: string; cad: 'mwf' | 'weekly'; up: number; puts: number; putCap: number | 'target'; target?: number; earn: 'puts1sd' | 'nothing'; early: boolean; drop: boolean; dropPuts?: [number, number] };
const SIX = { book: 'S', cad: 'weekly', earn: 'nothing', early: false, drop: false } as const;
const AGREED: Record<string, Agreed> = {
  NFLX: { ...SIX, up: 0.15, puts: 10, putCap: 1000 },
  UBER: { ...SIX, up: 0.15, puts: 10, putCap: 1000 },
  BABA: { ...SIX, up: 0.20, puts: 4, putCap: 1000 },
  LULU: { ...SIX, up: 0.17, puts: 6, putCap: 1000 },
  NKE: { ...SIX, up: 0.11, puts: 5, putCap: 1000 },
  NVDA: { book: 'N', cad: 'mwf', up: 0.20, puts: 2, putCap: 30, earn: 'puts1sd', early: true, drop: true },
  SPCX: { book: 'N', cad: 'mwf', up: 0.20, puts: 2, putCap: 30, earn: 'puts1sd', early: true, drop: true },
  TLT: { book: 'N', cad: 'weekly', up: 0.065, puts: 10, putCap: 'target', target: 5000, earn: 'nothing', early: false, drop: true, dropPuts: [10, 20] },
};
const OFF = ['FIS'];

// ── Data ──
const db = async (path: string): Promise<Row[]> => {
  const out: Row[] = [];
  for (let from = 0; ; from += 1000) {
    const r = await fetch(`${URL_}/rest/v1/${path}`, { headers: { apikey: SK, Authorization: `Bearer ${SK}`, Range: `${from}-${from + 999}` } });
    if (!r.ok) { await r.body?.cancel(); return out; }
    const rows = await r.json() as Row[]; out.push(...rows);
    if (rows.length < 1000) return out;
  }
};
const send = async (path: string, body: unknown, prefer: string) => {
  const r = await fetch(`${URL_}/rest/v1/${path}`, { method: 'POST', headers: { apikey: SK, Authorization: `Bearer ${SK}`, 'Content-Type': 'application/json', Prefer: prefer }, body: JSON.stringify(body) });
  await r.body?.cancel(); return r.ok;
};
async function theta(path: string): Promise<Row[]> {
  if (!THETA_URL) return [];
  const r = await fetch(`${THETA_URL}${path}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) }).catch(() => null);
  if (!r || !r.ok) { await r?.body?.cancel(); return []; }
  return ((await r.json())?.response ?? []) as Row[];
}
async function engine(body: Row): Promise<Row> {
  const r = await fetch(`${URL_}/functions/v1/sundial`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-cron-key': Deno.env.get('CRON_SECRET') ?? '' }, body: JSON.stringify(body) });
  return r.ok ? await r.json() : { error: `sundial ${r.status}` };
}

// ── Its own option maths: Abramowitz and Stegun 26.2.17 for the normal curve (the engine uses an erf), bisection for IV ──
function nd(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x)), y = Math.exp(-x * x / 2) / Math.sqrt(2 * Math.PI);
  const p = y * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x >= 0 ? 1 - p : p;
}
const R = 0.04;
function price(S: number, K: number, T: number, v: number, put: boolean): number {
  if (T <= 0 || v <= 0) return Math.max(0, put ? K - S : S - K);
  const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + (R + v * v / 2) * T) / sq, d2 = d1 - sq, df = Math.exp(-R * T);
  return put ? K * df * nd(-d2) - S * nd(-d1) : S * nd(d1) - K * df * nd(d2);
}
function delta(S: number, K: number, T: number, v: number, put: boolean): number {
  if (T <= 0 || v <= 0) return put ? (S < K ? -1 : 0) : (S > K ? 1 : 0);
  const d1 = (Math.log(S / K) + (R + v * v / 2) * T) / (v * Math.sqrt(T));
  return put ? nd(d1) - 1 : nd(d1);
}
function impliedVol(px: number, S: number, K: number, T: number, put: boolean): number | null {
  if (!(px > 0) || T <= 0) return null;
  let lo = 0.01, hi = 4;
  if (price(S, K, T, hi, put) < px || price(S, K, T, lo, put) > px) return null;
  for (let i = 0; i < 80; i++) { const m = (lo + hi) / 2; if (price(S, K, T, m, put) > px) hi = m; else lo = m; }
  return (lo + hi) / 2;
}

// ── Time ──
const plusDays = (d: string, n: number) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const dow = (d: string) => new Date(d + 'T12:00:00Z').getUTCDay();
function nyClock() {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(new Date()).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, mins: (Number(p.hour) % 24) * 60 + Number(p.minute) };
}
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (d: string) => `${MO[Number(d.slice(5, 7)) - 1]} ${Number(d.slice(8, 10))}`;
const k$ = (x: number) => (x < 0 ? '-' : '') + '$' + (Math.abs(x) >= 1000 ? (Math.abs(x) / 1000).toFixed(1) + 'K' : Math.round(Math.abs(x)));

// ── The 11 Nov tables and Sundial's reads, written out again from the spec ──
type Reads = { z: number; trend: 'up' | 'mid' | 'down'; rich: boolean; cheap: boolean; freak: boolean; d52: number | null; hv20: number | null; rank: number };
function callDistance(r: Reads, earnings: boolean): number | null {
  if (earnings) return null;                                     // no calls on an expiry spanning a report
  let k: number;
  if (r.freak) k = 0;                                            // at the money only on a 20% up day
  else if (r.z >= 2) k = 0.25; else if (r.z >= 1) k = 0.5; else if (r.z <= -2) k = 0.5; else if (r.z <= -1) k = 0.75;
  else k = r.trend === 'up' ? 0.75 : 0.5;
  k += r.rich ? -0.25 : r.cheap ? 0.25 : 0;                      // rich 0.25 SD closer, cheap 0.25 SD wider
  k = Math.min(1.25, Math.max(r.freak ? 0 : 0.25, k));           // calls between 0.25 and 1.25 SD
  return Math.round(k * 4) / 4;
}
function putDistance(r: Reads, earnings: boolean): number {
  if (earnings) return 1;
  let k: number;
  if (r.z <= -2) k = r.trend === 'up' ? -0.25 : r.trend === 'mid' ? 0 : r.d52 == null ? 0.5 : r.d52 < 1 ? 0 : r.d52 < 2 ? 0.25 : 0.5;
  else if (r.z <= -1) k = r.trend === 'up' ? 0.5 : r.trend === 'mid' ? 0.75 : 1;
  else if (r.z >= 1) k = 1;
  else k = r.trend === 'up' ? 0.75 : 1;
  const floor = k === -0.25 ? -0.25 : 0;
  k += r.rich ? -0.25 : r.cheap ? 0.25 : 0;
  return Math.round(Math.min(1, Math.max(floor, k)) * 4) / 4;
}
const readWords = (r: Reads, hasMa50: boolean, earnOn: string | null) => [
  r.freak ? 'Up 20% today' : r.z >= 2 ? 'Big up week' : r.z >= 1 ? 'Up week' : r.z <= -2 ? 'Big down week' : r.z <= -1 ? 'Down week' : 'Flat week',
  r.trend === 'down' ? 'under the 50-day' : r.trend === 'up' ? 'over the 200-day' : hasMa50 ? 'over the 50-day' : null,
  r.rich ? 'options rich' : r.cheap ? 'options cheap' : 'options fair',
  earnOn,
].filter(Boolean).join(' · ');

// ── One name, inspected ──
type Leg = { put: boolean; K: number; ex: string; n: number; side: 1 | -1; iv: number };
async function inspect(t: string, a: Agreed, eng: Row | null, shown: Row | null, ctx: { day: string; mins: number; open: boolean; closeMins: number; closed: Set<string>; syncAt: Record<string, string> }) {
  const problems: string[] = [], notes: string[] = [], checks: Row = {};
  const { day, mins, open, closeMins, closed } = ctx;
  const sessions = (a0: string, b0: string) => { let n = 0; for (let d = plusDays(a0, 1); d <= b0; d = plusDays(d, 1)) if (dow(d) % 6 !== 0 && !closed.has(d)) n++; return n; };
  const minsLeft = open ? Math.max(0, closeMins - mins) : 0;
  const years = (ex: string, from = day, left = minsLeft) => (sessions(from, ex) + left / 390) / 252;
  if (!eng) { problems.push('settings: the engine does not cover this name'); return { t, problems, notes, checks }; }

  // settings
  const cfg = eng.cfg ?? {};
  const diff: string[] = [];
  if (Math.abs(Number(eng.up) - a.up) > 1e-9) diff.push(`test +${Number(eng.up) * 100}% (agreed +${a.up * 100}%)`);
  if (eng.cad !== a.cad) diff.push(`cadence ${eng.cad} (agreed ${a.cad})`);
  if (Number(cfg.puts) !== a.puts) diff.push(`${cfg.puts} puts (agreed ${a.puts})`);
  if (String(cfg.putCap) !== String(a.putCap)) diff.push(`put cap ${cfg.putCap} (agreed ${a.putCap})`);
  if (cfg.earn !== a.earn) diff.push(`earnings ${cfg.earn} (agreed ${a.earn})`);
  if (!!cfg.early !== a.early) diff.push(`early close ${cfg.early ? 'on' : 'off'} (agreed ${a.early ? 'on' : 'off'})`);
  if (!!cfg.drop !== a.drop) diff.push(`big drop ${cfg.drop ? 'on' : 'off'} (agreed ${a.drop ? 'on' : 'off'})`);
  if (JSON.stringify(cfg.dropPuts ?? null) !== JSON.stringify(a.dropPuts ?? null)) diff.push(`drop puts ${JSON.stringify(cfg.dropPuts)} (agreed ${JSON.stringify(a.dropPuts ?? null)})`);
  checks.settings = diff.length ? diff : 'as agreed';
  if (diff.length) problems.push(`settings: ${diff.join(', ')}`);

  // data, read on its own
  const [quote, closesR, ivR, earnR, trades, lots] = await Promise.all([
    db(`ticker_quotes_live?ticker=eq.${t}&select=spot,captured_at`),
    db(`daily_closes?ticker=eq.${t}&date=lt.${day}&order=date.desc&limit=260&select=date,close_price`),
    db(`ticker_iv_daily?ticker=eq.${t}&atm_iv=gt.0&snapshot_date=gte.${plusDays(day, -365)}&order=snapshot_date.asc&select=snapshot_date,atm_iv`),
    db(`earnings_events?ticker=eq.${t}&report_date=gte.${day}&order=report_date.asc&limit=2&select=report_date,report_time`),
    db(`option_trades?book_id=eq.${a.book}&ticker=eq.${t}&voided_at=is.null&expiry=gte.${day}&select=id,action,direction,option_type,strike,expiry,contracts`),
    db(`share_lots?book_id=eq.${a.book}&ticker=eq.${t}&voided_at=is.null&qty_remaining=gt.0&select=qty_remaining`),
  ]);
  // sessions only (a close stored on a holiday is not a session)
  const sess = closesR.slice().reverse().filter((r) => !closed.has(String(r.date)) && dow(String(r.date)) % 6 !== 0);
  const S = Number(quote[0]?.spot), closes = sess.map((r) => Number(r.close_price)), closeDays = sess.map((r) => String(r.date));
  if (!(S > 0) || closes.length < 30) { problems.push('data: no price or closes'); return { t, problems, notes, checks }; }

  // health
  const ageQ = (Date.now() - Date.parse(String(quote[0]?.captured_at))) / 60000;
  const inSession = open && mins >= 9 * 60 + 35 && mins < closeMins;
  const health: string[] = [];
  if (inSession && ageQ > 2) health.push(`price is ${Math.round(ageQ)} min old`);
  const lastIv = ivR.at(-1)?.snapshot_date ? String(ivR.at(-1)!.snapshot_date) : null;
  if (!lastIv || sessions(lastIv, day) > 2) health.push(`IV last saved ${lastIv ?? 'never'}`);
  const sync = ctx.syncAt[a.book];
  const ageS = sync ? (Date.now() - Date.parse(sync)) / 60000 : Infinity;
  if (inSession && ageS > 30) health.push(`IBKR last synced ${Number.isFinite(ageS) ? Math.round(ageS) + ' min' : 'never'} ago`);
  // the closes themselves (27 Nov 2026: TLT's close sat at $81.95 for 15 sessions after it left the price feed; the
  // review found it, as the engine and this inspector read the same table)
  let prevS = plusDays(day, -1); while (dow(prevS) % 6 === 0 || closed.has(prevS)) prevS = plusDays(prevS, -1);
  if (closeDays.at(-1)! < prevS) health.push(`the last close stored is ${md(closeDays.at(-1)!)}, the last session was ${md(prevS)}`);
  const last5 = closes.slice(-5);
  if (last5.length === 5 && last5.every((x) => x === last5[0])) health.push(`the last 5 closes are all $${last5[0].toFixed(2)}: the price feed stopped for ${t}`);
  // Every stored close the engine reads, against Theta's official closes: an outside source, so a bad table cannot pass
  // (27 Nov 2026: SPCX's closes were stuck at $110.95 for 3 Aug to 2 Sep and missing for 3 Sep to 13 Oct; its 50-day
  // line read 18 of the stuck ones). Off by more than 1%, or a session Theta has and the table does not.
  if (closeDays.length) {
    // Theta takes at most 365 days a request; the 260 sessions the engine reads run a little longer, so the last year
    const from = closeDays[0] > plusDays(prevS, -364) ? closeDays[0] : plusDays(prevS, -364);
    const eod = await theta(`/v3/stock/history/eod?symbol=${t}&start_date=${from.replaceAll('-', '')}&end_date=${prevS.replaceAll('-', '')}`);
    const real = new Map<string, number>(eod.filter((r) => Number(r.close) > 0).map((r) => [String(r.created ?? r.last_trade ?? '').slice(0, 10), Number(r.close)]));
    if (!real.size) notes.push('data: Theta had no closes to compare with');
    else {
      const stored = new Map(closeDays.map((d, i) => [d, closes[i]]));
      const off = closeDays.filter((d) => d >= from && real.has(d) && Math.abs(stored.get(d)! / real.get(d)! - 1) > 0.01);
      const gone = [...real.keys()].filter((d) => d >= from && d <= prevS && !stored.has(d)).sort();
      if (off.length) health.push(`${off.length} stored close${off.length > 1 ? 's' : ''} off Theta's by more than 1% (${md(off[0])}: $${stored.get(off[0])!.toFixed(2)} stored, $${real.get(off[0])!.toFixed(2)} real)`);
      if (gone.length) health.push(`${gone.length} session${gone.length > 1 ? 's' : ''} missing from the closes (first ${md(gone[0])})`);
      checks.closes = { compared: closeDays.filter((d) => real.has(d)).length, off: off.length, missing: gone.length };
    }
  }
  if (t !== 'TLT' && !earnR.length) health.push('no next report date on file');
  checks.health = health.length ? health : 'fresh';
  if (health.length) problems.push(`health: ${health.join(', ')}`);

  // the book, from IBKR's trades netted per contract, each leg's IV from its own saved mark
  const ids = trades.map((x) => x.id);
  const gk = ids.length ? await db(`option_greeks_live?option_trade_id=in.(${ids.join(',')})&select=option_trade_id,iv,captured_at&order=captured_at.desc`) : [];
  const ivById = new Map<string, number>(); for (const g of gk) if (!ivById.has(g.option_trade_id) && Number(g.iv) > 0.05) ivById.set(g.option_trade_id, Number(g.iv));
  const ivs = ivR.map((r) => ({ d: String(r.snapshot_date), v: Number(r.atm_iv) }));
  const ivToday = [...ivs].reverse().find((x) => x.d <= day)?.v ?? 0.4, ivYday = [...ivs].reverse().find((x) => x.d < day)?.v ?? ivToday;
  const net = new Map<string, Leg & { ivs: number[] }>();
  for (const x of trades) {
    const put = x.option_type === 'put', side = (x.direction === 'long' ? 1 : -1) as 1 | -1, k = `${put}|${side}|${Number(x.strike)}|${x.expiry}`;
    const e = net.get(k) ?? { put, K: Number(x.strike), ex: String(x.expiry), n: 0, side, iv: 0, ivs: [] };
    e.n += (x.action === 'open' ? 1 : -1) * Number(x.contracts); const v = ivById.get(x.id); if (v) e.ivs.push(v); net.set(k, e);
  }
  const afterClose = !open || mins >= closeMins;
  const all: Leg[] = [...net.values()].filter((l) => l.n > 0 && !(l.ex === day && afterClose)).map((l) => ({ ...l, iv: l.ivs[0] ?? ivToday }));
  const legs = all.filter((l) => l.ex > day);
  const shares = lots.reduce((s, r) => s + Number(r.qty_remaining), 0);

  // delta now and at +1 weekly SD
  const bookDelta = (P: number) => shares + legs.reduce((s, l) => s + l.side * l.n * 100 * delta(P, l.K, years(l.ex), l.iv, l.put), 0);
  const dNow = bookDelta(S), dUp = bookDelta(S * (1 + ivToday * Math.sqrt(5 / 252)));
  checks.delta = { now: Math.round(dNow), atPlus1Sd: Math.round(dUp) };
  if (dNow < 0) problems.push(`delta: the book is short ${Math.round(-dNow)} shares now`);
  else if (dUp < 0) notes.push(`delta: turns short (${Math.round(dUp)}) by +1 weekly SD`);

  // the reads (Sundial's definitions, worked out here)
  const S5 = closes.length >= 4 ? closes[closes.length - 4] : closes[0], iv5Day = closeDays[closeDays.length - 4] ?? closeDays[0];
  const iv5 = [...ivs].reverse().find((x) => x.d <= iv5Day)?.v ?? ivToday;
  const z = Math.log(S / S5) / (iv5 * Math.sqrt(5 / 252));
  const avg = (x: number[]) => x.reduce((p, q) => p + q, 0) / x.length;
  const ma50 = closes.length >= 50 ? avg(closes.slice(-50)) : null, ma200 = closes.length >= 200 ? avg(closes.slice(-200)) : null;
  const trend = !ma50 ? 'mid' : S <= ma50 ? 'down' : ma200 && S > ma200 ? 'up' : 'mid';
  const seq = [...closes, S], rets: number[] = []; for (let i = seq.length - 20; i < seq.length; i++) rets.push(Math.log(seq[i] / seq[i - 1]));
  const mu = avg(rets), hv20 = seq.length > 21 ? Math.sqrt(rets.reduce((p, q) => p + (q - mu) ** 2, 0) / (rets.length - 1) * 252) : null;
  const hist = ivs.map((x) => x.v), lo = Math.min(...hist, ivToday), hi = Math.max(...hist, ivToday), rank = hi > lo ? (ivToday - lo) / (hi - lo) * 100 : 50;
  const ratio = hv20 ? ivToday / hv20 : 1, cheapWins = hv20 != null && hv20 > ivToday;
  const rich = !cheapWins && (rank >= 70 || ratio >= 1.3), cheap = cheapWins || (!rich && (rank <= 20 || ratio <= 1.0));
  const low52 = Math.min(...closes.slice(-252), S), d52 = low52 > 0 ? Math.log(S / low52) / (ivToday * Math.sqrt(5 / 252)) : null;
  const reads: Reads = { z, trend, rich, cheap, freak: S / closes.at(-1)! - 1 >= 0.2, d52, hv20, rank };
  checks.reads = { z: Math.round(z * 100) / 100, trend, rich, cheap, rank: Math.round(rank), hv20: hv20 && Math.round(hv20 * 1000) / 1000, iv: Math.round(ivToday * 1000) / 1000 };
  const es = eng.signals ?? {};
  if (es.trend !== trend || !!es.rich !== rich || !!es.cheap !== cheap || Math.abs(Number(es.z) - z) > 0.25)
    problems.push(`reads: engine says z ${es.z} ${es.trend} ${es.rich ? 'rich' : es.cheap ? 'cheap' : 'fair'}, inspector z ${z.toFixed(2)} ${trend} ${rich ? 'rich' : cheap ? 'cheap' : 'fair'}`);

  // the big-drop lines
  const prevClose = closes.at(-1)!, line2 = prevClose * (1 - 2 * ivYday / Math.sqrt(252)), line3 = prevClose * (1 - 3 * ivYday / Math.sqrt(252));
  checks.drop = { at2Sd: Math.round(line2 * 100) / 100, at3Sd: Math.round(line3 * 100) / 100, fired: S <= line2 };
  if (a.drop && !eng.drop?.fired && Math.abs(Number(eng.drop?.line) - line2) / line2 > 0.005) problems.push(`drop: engine's line $${eng.drop?.line}, inspector's $${line2.toFixed(2)}`);
  if (a.drop && S <= line2 && open && !afterClose && !eng.drop?.fired) problems.push(`drop: ${t} is under its line ($${line2.toFixed(2)}) and the engine has no drop`);

  // the sale: target expiry, earnings, distances, strikes and counts
  const saleDay = open && (a.cad === 'mwf' ? [1, 3, 5].includes(dow(day)) : dow(day) === 5 || (dow(day) === 4 && closed.has(plusDays(day, 1))));
  const exps = (await theta(`/v3/option/list/expirations?symbol=${t}`)).map((x) => String(x.expiration ?? x.date ?? '')).filter(Boolean).map((e) => (e.includes('-') ? e : `${e.slice(0, 4)}-${e.slice(4, 6)}-${e.slice(6, 8)}`)).sort();
  const fri = (e: string) => dow(e) === 5 || (dow(e) === 4 && closed.has(plusDays(e, 1)));
  const target = exps.find((e) => e >= plusDays(day, 7) && (a.cad === 'mwf' || fri(e))) ?? null;
  checks.target = target;
  if (target !== eng.target) problems.push(`target: engine ${eng.target}, inspector ${target}`);
  if (!target) return { t, problems, notes, checks };
  const er = earnR[0] ? { d: String(earnR[0].report_date), when: String(earnR[0].report_time ?? 'amc') } : null;
  const earnings = !!er && ((er.d > day && er.d < target) || (er.d === day && er.when !== 'bmo') || (er.d === target && er.when === 'bmo'));
  const quiet = earnings && a.earn === 'nothing';
  const kc = quiet ? null : callDistance(reads, earnings), kp = putDistance(reads, earnings);
  checks.distance = { call: kc, put: kp, earnings };
  if ((eng.plan?.calls?.sd ?? null) !== kc && !(kc == null && eng.plan?.calls?.n === 0)) problems.push(`strike: engine's calls ${eng.plan?.calls?.sd} SD, inspector ${kc} SD`);
  if (Number(eng.plan?.puts?.sd) !== kp) problems.push(`strike: engine's puts ${eng.plan?.puts?.sd} SD, inspector ${kp} SD`);
  const want = readWords(reads, !!ma50, earnings && er ? `earnings ${md(er.d)}` : null);
  const card = (shown?.toSell?.cards ?? []).find((c: Row) => c.t === t);
  if (card?.reason && card.reason !== want) notes.push(`reads: the card says "${card.reason}", the inspector "${want}"`);

  // the chain and its own IV
  const chain = (await theta(`/v3/option/snapshot/quote?symbol=${t}&expiration=${target.replaceAll('-', '')}`)).filter((r) => r.data?.[0]).map((r) => {
    const b = Number(r.data[0].bid), x = Number(r.data[0].ask);
    return { K: Number(r.contract.strike), put: String(r.contract.right).toLowerCase() !== 'call', bid: b, ask: x, mid: b > 0 && x > 0 ? (b + x) / 2 : null };
  });
  const T = years(target);
  const near = (put: boolean) => chain.filter((q) => q.put === put && q.mid).sort((p, q) => Math.abs(p.K - S) - Math.abs(q.K - S))[0];
  const ivList = [near(false), near(true)].map((q) => (q ? impliedVol(q.mid!, S, q.K, T, q.put) : null)).filter((x): x is number => !!x);
  const ivEx = ivList.length ? ivList.reduce((p, q) => p + q, 0) / ivList.length : ivToday;
  const listed = (put: boolean) => [...new Set(chain.filter((q) => q.put === put).map((q) => q.K))].sort((p, q) => p - q);
  const snap = (K: number, put: boolean) => { const ks = listed(put); return ks.length ? ks.reduce((p, q) => (Math.abs(q - K) < Math.abs(p - K) ? q : p)) : Math.round(K * 2) / 2; };
  const step = (put: boolean) => { const ks = listed(put); let s = Infinity; for (let i = 1; i < ks.length; i++) s = Math.min(s, ks[i] - ks[i - 1]); return Number.isFinite(s) ? s : 1; };
  const Kc = kc == null ? null : snap(S * Math.exp(kc * ivEx * Math.sqrt(Math.max(T, 1 / 252))), false);
  const Kp = kp < 0 ? (listed(true).find((k) => k > S) ?? Math.ceil(S)) : snap(S * Math.exp(-kp * ivEx * Math.sqrt(Math.max(T, 1 / 252))), true);
  checks.strikes = { call: Kc, put: Kp, iv: Math.round(ivEx * 1000) / 1000 };
  if (Kc != null && eng.plan?.calls?.K != null && Math.abs(Number(eng.plan.calls.K) - Kc) > step(false) + 1e-9) problems.push(`strike: engine's call $${eng.plan.calls.K}, inspector $${Kc}`);
  if (eng.plan?.puts?.K != null && Math.abs(Number(eng.plan.puts.K) - Kp) > step(true) + 1e-9) problems.push(`strike: engine's put $${eng.plan.puts.K}, inspector $${Kp}`);

  // its own test: no loss vs now at any rise up to the size, at any close of the next 5 sessions (sold legs in full,
  // bought legs only what the move does)
  const horizons: string[] = []; for (let d = plusDays(day, 1); horizons.length < 5; d = plusDays(d, 1)) if (dow(d) % 6 !== 0 && !closed.has(d)) horizons.push(d);
  const worst = (book: Leg[]) => {
    let w = Infinity;
    const now = book.map((l) => (l.side < 0 ? price(S, l.K, years(l.ex), l.iv, l.put) : 0));
    for (const h of horizons) {
      const Th = book.map((l) => (l.ex < h ? 0 : years(l.ex, h, 0)));
      const base = book.map((l, i) => (l.side > 0 ? price(S, l.K, Th[i], l.iv, l.put) : 0));
      for (let i = 0; i <= 20; i++) {
        const P = S * (1 + a.up * i / 20);
        let v = shares * (P - S);
        book.forEach((l, j) => { const x = price(P, l.K, Th[j], l.iv, l.put); v += l.side < 0 ? l.n * 100 * (now[j] - x) : l.n * 100 * (x - base[j]); });
        w = Math.min(w, v);
      }
    }
    return w;
  };
  const capPuts = a.putCap === 'target' ? Math.max(0, Math.floor(((a.target ?? 0) - shares) / 100)) : a.putCap;
  const openPuts = all.filter((l) => l.side < 0 && l.put).reduce((s, l) => s + l.n, 0);
  const onTarget = legs.filter((l) => l.side < 0 && l.put && l.ex === target).reduce((s, l) => s + l.n, 0);
  const nP = saleDay && !quiet ? Math.max(0, Math.min(a.puts - onTarget, capPuts - openPuts)) : 0;
  const withPuts = nP ? [...legs, { put: true, K: Kp, ex: target, n: nP, side: -1 as const, iv: ivEx }] : legs;
  const fits = (n: number) => worst([...withPuts, { put: false, K: Kc!, ex: target, n, side: -1, iv: ivEx }]) >= 0;
  let roomN = 0;
  if (Kc != null && worst(withPuts) >= 0) { while (roomN < 200 && fits(roomN + 1)) roomN++; }
  let nC = roomN;
  if (a.cad === 'mwf' && Kc != null) {
    const bare = withPuts.filter((l) => !(l.side < 0 && !l.put));
    let empty = 0; while (empty < 200 && worst([...bare, { put: false, K: Kc, ex: target, n: empty + 1, side: -1, iv: ivEx }]) >= 0) empty++;
    const onEx = legs.filter((l) => l.side < 0 && !l.put && l.ex === target).reduce((s, l) => s + l.n, 0);
    nC = Math.min(roomN, Math.max(0, Math.floor(empty * 0.5) - onEx));
  }
  checks.count = { calls: saleDay ? nC : 0, puts: nP, bookNow: Math.round(worst(legs)) };
  // against the engine's live plan (the board locks it after the final time, so compare the live answer)
  const engCalls = Number(eng.plan?.calls?.n ?? 0), engPuts = Number(eng.plan?.puts?.n ?? 0);
  // Close cards (NVDA, SPCX) free room: the engine sizes the sale as if they are bought back first, so compare loosely then
  const closing = (eng.close ?? []).length > 0;
  if (saleDay && Kc != null && !closing && Math.abs(engCalls - nC) > Math.max(1, Math.round(0.1 * Math.max(engCalls, nC)))) problems.push(`count: engine allows ${engCalls} calls, inspector ${nC}`);
  if (saleDay && closing) notes.push(`count: Close cards free room (engine ${engCalls} calls, inspector without the buy-backs ${nC})`);
  if (saleDay && engPuts !== nP) problems.push(`count: engine's ${engPuts} puts, inspector's ${nP}`);
  if (worst(legs) < -100) notes.push(`book: as it stands it loses ${k$(-worst(legs))} before +${a.up * 100}% (the price moved after the sales)`);

  // the credit on the board's legs: quantity x the real mid
  for (const l of card?.legs ?? []) {
    const q = chain.find((x) => x.put === (l.type === 'put') && x.K === Number(l.strike));
    if (!q?.mid) { problems.push(`credit: no live quote for ${l.qty} $${l.strike} ${l.type}s`); continue; }
    if (!(q.bid > 0)) problems.push(`credit: $${l.strike} ${l.type}s have no bid`);
    const exp = Math.round(Number(l.qty) * q.mid * 100);
    if (Math.abs(exp - Number(l.credit)) > Math.max(25, 0.15 * exp)) notes.push(`credit: card ${k$(Number(l.credit))} for ${l.qty} $${l.strike} ${l.type}s, live mid gives ${k$(exp)}`);
  }
  return { t, problems, notes, checks };
}

Deno.serve(async (req) => {
  const cron = Deno.env.get('CRON_SECRET');
  if (!cron || (req.headers.get('x-cron-key') !== cron && req.headers.get('x-admin-key') !== cron)) return json(401, { error: 'not allowed' });
  const body = await req.json().catch(() => ({})) as Row;
  const { day, mins } = nyClock();
  const cal = await db(`market_calendar?date=gte.${plusDays(day, -400)}&date=lte.${plusDays(day, 60)}&select=date,kind,closes`);
  const closed = new Set(cal.filter((r) => r.kind === 'closed').map((r) => String(r.date)));
  const todayRow = cal.find((r) => String(r.date) === day);
  const closeMins = todayRow?.kind === 'early_close' && todayRow.closes ? Number(String(todayRow.closes).slice(0, 2)) * 60 + Number(String(todayRow.closes).slice(3, 5)) : 16 * 60;
  const open = dow(day) % 6 !== 0 && !closed.has(day);
  // the random time: one 15-minute slot a day between 10:00 AM and 30 minutes before the close, picked from the date
  if (!body.force) {
    if (!open) return json(200, { build: BUILD, skip: 'market closed' });
    let h = 0; for (const ch of day) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
    const slots = Math.max(1, Math.floor((closeMins - 30 - 600) / 15)), slot = 600 + (h % slots) * 15;
    if (mins < slot || mins >= slot + 15) return json(200, { build: BUILD, skip: 'not the inspection time', at: `${Math.floor(slot / 60)}:${String(slot % 60).padStart(2, '0')}` });
    const done = await db(`sundial_inspections?day=eq.${day}&forced=eq.false&select=id`);
    if (done.length) return json(200, { build: BUILD, skip: 'already inspected today' });
  }
  const [view, board, syncs] = await Promise.all([engine({ mode: 'view' }), engine({ mode: 'board', account: 'ab', name: 'all' }),
    db(`ibkr_sync_runs?finished_at=not.is.null&order=finished_at.desc&limit=40&select=book_id,finished_at`)]);
  const syncAt: Record<string, string> = {}; for (const s of syncs) if (!syncAt[s.book_id]) syncAt[s.book_id] = String(s.finished_at);
  const engNames: Row[] = view.names ?? [];
  const ctx = { day, mins, open, closeMins, closed, syncAt };
  const results = await Promise.all(Object.entries(AGREED).map(([t, a]) => inspect(t, a, engNames.find((n) => n.t === t) ?? null, board.views?.[t] ?? null, ctx)
    .catch((e) => ({ t, problems: [`error: ${String((e as Error)?.message ?? e)}`], notes: [], checks: {} }))));
  for (const t of OFF) if (engNames.some((n) => n.t === t)) results.push({ t, problems: [`settings: ${t} is off but the engine covers it`], notes: [], checks: {} });
  for (const n of engNames) if (!AGREED[n.t] && !OFF.includes(n.t)) results.push({ t: n.t, problems: [`settings: the engine covers ${n.t}, which nobody agreed`], notes: [], checks: {} });
  const problems = results.reduce((s, r) => s + r.problems.length, 0);
  const ins = await fetch(`${URL_}/rest/v1/sundial_inspections?select=id`, { method: 'POST', headers: { apikey: SK, Authorization: `Bearer ${SK}`, 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify([{ day, at_mins: mins, forced: !!body.force, build: BUILD, engine_build: view.build ?? null, problems, results }]) });
  const id = ins.ok ? Number((await ins.json())?.[0]?.id) : (await ins.body?.cancel(), null);
  // Part 3: Claude's written review of this inspection (sundial-review). Every scheduled run; a forced one only with
  // { review: true }. It answers at once and writes the review in the background.
  if (id && (!body.force || body.review)) {
    const rv = fetch(`${URL_}/functions/v1/sundial-review`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-cron-key': Deno.env.get('CRON_SECRET') ?? '' }, body: JSON.stringify({ id }) })
      .then((r) => r.body?.cancel()).catch(() => {});
    try { EdgeRuntime.waitUntil(rv); } catch { await rv; }
  }
  if (problems && !body.force) {
    const lines = results.filter((r) => r.problems.length).map((r) => `${r.t}: ${r.problems[0]}`);
    await send('alert_dispatch?on_conflict=dedup_key', [{ category: 'sundial', dedup_key: `sundial:inspect:${day}`, ticker: null, title: `Sundial inspection: ${problems} to look at`, body: lines.slice(0, 4).join('. '), deep_link: null, book_id: 'S', meta: { user_id: NIK, src: 'sundial-inspect' } }], 'resolution=ignore-duplicates,return=minimal');
  }
  return json(200, { build: BUILD, id, day, at: `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, '0')}`, engine: view.build, problems, results });
});
