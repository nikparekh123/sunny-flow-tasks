/**
 * sunny-chart: the ticker chart a name tile or a heat-map tile opens on New Home (block 33, handoff 6 Nov 2026,
 * Pass 2). Five years of daily closes from Yahoo (the market feed's source), the price and the day's move, and
 * three layers for the chart: Positions (the legs the book holds in this name), Walls (the nearest weekly's
 * ceiling, floor and flip) and Technicals (20- and 50-day averages, the year's high and low). The phone only
 * draws it (Nik, 6 Nov 2026).
 *
 * POST { t: 'NKE', book?: 'S' | 'N' }.
 * ⚠ WHO MAY CALL: a signed-in user (their token, checked with Supabase auth) or the scheduler's key (x-cron-key,
 * for checks). The book's legs are read AS THE CALLER (RLS: members of the book only); a cron-key call reads
 * them with the service key. verify_jwt is off so the cron key can pass; the check below stands in for it.
 * No em dashes in any words written here (Nik).
 *
 * 8 Nov 2026 (type pass, SunnyTickerChart.dc.html): the walls also send the accelerator; the reply adds the move
 * priced by Friday (sd, the brief's one weekly SD: iv × √(5/252) × 100, in %) for the Walls band, and the sub line's
 * pieces: the name as the brief writes it (short), its strategy word, and whether it is on the watchlist.
 *
 * 9 Nov 2026 (Nik: "add the analyst targets to the ticker chart"): the reply adds `targets`, the analysts' 12-month
 * low, average and high from ticker_fundamentals (filled each morning by ticker-technicals for the book's names),
 * with how many analysts and the day it was read. Null when the name has no row from the last 30 days. Market data,
 * not the book's, so it is read with the service key.
 */
const BUILD = '2026-11-09.1';
const URL_ = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-key' };
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
const UA = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'application/json, text/plain, */*', 'Accept-Language': 'en-US,en;q=0.9',
};
type Row = Record<string, any>;

/** Who is calling: a user (their token) or the scheduler. */
async function caller(req: Request): Promise<{ auth: string; key: string } | null> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && req.headers.get('x-cron-key') === cron) return { auth: `Bearer ${SK}`, key: SK };
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return null;
  const r = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  await r.body?.cancel();
  return r.ok ? { auth, key: ANON } : null;
}

let session: { cookie: string; crumb: string } | null = null;
async function yahooSession() {
  const c = await fetch('https://fc.yahoo.com', { headers: UA, redirect: 'manual' });
  await c.body?.cancel();
  const cookie = (c.headers.get('set-cookie') ?? '').split(';')[0];
  if (!cookie) throw new Error('yahoo: no cookie');
  const r = await fetch('https://query2.finance.yahoo.com/v1/test/getcrumb', { headers: { ...UA, Cookie: cookie } });
  const crumb = (await r.text()).trim();
  if (!r.ok || !crumb || crumb.length > 40) throw new Error(`yahoo crumb ${r.status}`);
  return { cookie, crumb };
}
async function chart(t: string): Promise<Row> {
  for (let attempt = 0; attempt < 2; attempt++) {
    if (!session) session = await yahooSession();
    const r = await fetch(`https://query2.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(t)}?range=5y&interval=1d&includePrePost=false`
      + `&crumb=${encodeURIComponent(session.crumb)}`, { headers: { ...UA, Cookie: session.cookie }, signal: AbortSignal.timeout(12_000) });
    if (r.status === 401 || r.status === 403) { await r.body?.cancel(); session = null; continue; }
    if (!r.ok) { await r.body?.cancel(); throw new Error(`yahoo chart ${r.status}`); }
    const res = (await r.json())?.chart?.result?.[0];
    if (!res) throw new Error('yahoo chart: no result');
    return res;
  }
  throw new Error('yahoo chart: refused');
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (d: string) => `${MON[Number(d.slice(5, 7)) - 1]} ${Number(d.slice(8, 10))}`;
const fk = (k: number) => (k % 1 ? String(+k.toFixed(2)) : String(k));
const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;

/** The analysts' latest 12-month targets for a name, or null when none are fresh (30 days). */
async function targets(t: string): Promise<Row | null> {
  const since = new Date(Date.now() - 30 * 86400_000).toISOString().slice(0, 10);
  const r = await fetch(`${URL_}/rest/v1/ticker_fundamentals?ticker=eq.${encodeURIComponent(t)}&day=gte.${since}`
    + `&analyst_target=not.is.null&select=day,analyst_low,analyst_target,analyst_high,n_buy,n_hold,n_sell&order=day.desc&limit=1`,
    { headers: { apikey: SK, Authorization: `Bearer ${SK}` } });
  if (!r.ok) { await r.body?.cancel(); return null; }
  const x = ((await r.json()) as Row[])[0];
  if (!x) return null;
  const n = (v: unknown) => (v == null ? null : +Number(v).toFixed(2));
  const low = n(x.analyst_low), mid = n(x.analyst_target), high = n(x.analyst_high);
  if (low == null || mid == null || high == null) return null;
  return { low, avg: mid, high, analysts: (x.n_buy ?? 0) + (x.n_hold ?? 0) + (x.n_sell ?? 0), day: x.day };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const who = await caller(req);
  if (!who) return json(401, { error: 'sign in' });
  const body = await req.json().catch(() => ({})) as Row;
  const t = String(body.t ?? '').toUpperCase(), book = String(body.book ?? '').toUpperCase();
  if (!/^[A-Z.^=-]{1,12}$/.test(t)) return json(400, { error: 'send t' });

  try {
    const [res, tgt] = await Promise.all([chart(t), targets(t).catch(() => null)]);
    const meta = res.meta ?? {}, ts: number[] = res.timestamp ?? [], cl: (number | null)[] = res.indicators?.quote?.[0]?.close ?? [];
    const pts = ts.map((s, i) => ({ d: new Date(s * 1000).toISOString().slice(0, 10), c: cl[i] })).filter((p) => p.c != null) as { d: string; c: number }[];
    const price = Number(meta.regularMarketPrice ?? pts.at(-1)?.c ?? 0);
    /* The previous session's close: the bar before the latest when the latest is the price now (after the close,
       on a weekend), else the latest bar. Never meta.chartPreviousClose: that is the close before the chart's first
       bar, five years back. */
    const lastD = pts.at(-1)?.d, prevBar = pts.length > 1 ? (Math.abs(pts.at(-1)!.c - price) < 0.005 ? pts.at(-2) : pts.at(-1)) : null;
    const prev = Number(meta.previousClose ?? prevBar?.c ?? price);
    const closes = pts.map((p) => +p.c.toFixed(4)), last252 = closes.slice(-252);
    const tech = {
      sma20: closes.length >= 20 ? +avg(closes.slice(-20)).toFixed(2) : null,
      sma50: closes.length >= 50 ? +avg(closes.slice(-50)).toFixed(2) : null,
      hi52: last252.length ? +Math.max(...last252).toFixed(2) : null, lo52: last252.length ? +Math.min(...last252).toFixed(2) : null,
    };

    // The book's legs and walls in this name, read as the caller.
    let positions: Row[] = [], walls: Row[] = [];
    let sd: number | null = null, short: string | null = null, strategy: string | null = null, watch = false;
    if (/^[A-Z]$/.test(book)) {
      const r = await fetch(`${URL_}/rest/v1/home_snapshot?book_id=eq.${book}&select=inputs:payload->brief_inputs,names:payload->brief->names,`
        + `strategies:payload->strategies,watchlist:payload->watchlist`, { headers: { apikey: who.key, Authorization: who.auth } });
      const rows = r.ok ? await r.json() as Row[] : [];
      const row = rows[0] ?? {};
      const bn = ((row.names ?? []) as Row[]).find((x) => x?.t === t);
      if (bn?.name) short = String(bn.name);
      const st = (row.strategies ?? {})[t] ?? bn?.strategy;
      if (st) strategy = String(st);
      watch = ((row.watchlist ?? []) as Row[]).some((w) => w?.ticker === t);
      const n = (row.inputs?.names ?? []).find((x: Row) => x.t === t);
      if (n) {
        if (!n.noIv && Number(n.iv) > 0) sd = +(Number(n.iv) * Math.sqrt(5 / 252) * 100).toFixed(3);
        const legs = n.legs as Row[];
        for (const l of legs.filter((x) => x.kind === 'leaps' || x.kind === 'otm')) positions.push({ k: l.K, label: `${l.kind === 'leaps' ? 'LEAPS' : 'Hedge'} ${fk(l.K)} ×${l.q}`, solid: false });
        for (const l of legs.filter((x) => x.kind === 'sc' || x.kind === 'sp')) positions.push({ k: l.K, label: `Sold ${l.kind === 'sc' ? 'call' : 'put'} ${fk(l.K)} ×${-l.q}, ${md(String(l.ex))}`, solid: true });
        for (const l of legs.filter((x) => x.kind === 'ins')) positions.push({ k: l.K, label: `Puts ${fk(l.K)} ×${l.q}`, solid: false });
        const sh = legs.find((x) => x.kind === 'shares');
        if (sh && sh.K > 0) positions.push({ k: +Number(sh.K).toFixed(2), label: `Shares cost ${Number(sh.K).toFixed(2)}`, solid: false });
        const w = ((n.walls ?? []) as Row[]).find((c) => c.kind === 'Weekly') ?? (n.walls ?? [])[0];
        if (w) {
          if (w.c) walls.push({ k: w.c.k, label: `Ceiling · ${w.label}` });
          if (w.f) walls.push({ k: w.f.k, label: `Floor · ${w.label}` });
          if (w.a) walls.push({ k: w.a.k, label: `Accelerator · ${w.label}` });
          if (w.flip != null) walls.push({ k: w.flip, label: `Flip · ${w.label}` });
        }
      }
      // Merge legs on the same strike into one label (two sold expiries at 40 read as one line).
      const byK = new Map<number, Row>();
      for (const p of positions) { const e = byK.get(p.k); if (e) { e.label += ` · ${p.label}`; e.solid = e.solid || p.solid; } else byK.set(p.k, { ...p }); }
      positions = [...byK.values()];
    }
    return json(200, { v: 1, build: BUILD, t, name: String(meta.shortName ?? meta.longName ?? t), price: +price.toFixed(4), prev: +prev.toFixed(4),
      last_bar: lastD ?? null, dates: pts.map((p) => p.d), closes, positions, walls, tech, sd, short, strategy, watch, targets: tgt });
  } catch (e) {
    return json(502, { error: String((e as Error)?.message ?? e) });
  }
});
