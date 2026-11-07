/**
 * market-tape — the market around the book, from Yahoo, every 30 s from
 * 4:00 to 20:00 New York time on weekdays, and through the night while the
 * index futures trade (Sunday 18:00 to Friday 17:00, less the daily 17:00-18:00
 * break) so the Today cards can show them from 18:00 (Nik, 25 Oct 2026).
 *
 *   SPY QQQ IWM            the Today row, through pre-market and after hours
 *   ^VIX                   a level, not a price
 *   ^N225 ^GDAXI ^NSEI 000001.SS   the Overnight card (pre-market only)
 *   ^HSI ^TNX DX-Y.NYB CL=F GC=F BTC-USD   the rest of New Home's Overnight list and The world this
 *                          week (Hang Seng, 10y yield, Dollar, Oil, Gold, Bitcoin; handoff 6 Nov 2026)
 *   XLK XLE ... + 12 names each   Sectors and its 11 heat maps (market_sectors; tile = market cap)
 *   INTU ADBE PYPL VZ TMUS SPCX TSLA APP  the Watchlist (Nik, 12 and 14 Oct 2026)
 *   ES=F NQ=F RTY=F        front-month futures for the 18:00-9:30 cards (handoff 24,
 *                          block 09). Yahoo's are ~10 min delayed (measured 600 s);
 *                          Nik took that on 15 Oct. VX is not on Yahoo, so VIX has none.
 *                          Each one's 16:00 price is kept in daily_closes as the base.
 *
 * ⚠ YAHOO FOR NOW, THETA LATER. Our Theta plan is options only, and options
 * do not trade before 9:30 or after 4:00, so the option-implied spot cannot
 * move out of hours; VIX needs Theta's index plan. Nik (12 Oct 2026): start
 * with Yahoo, move to Theta stock prices in about a month. Yahoo is
 * unofficial: it wants a cookie and a "crumb", and it refuses my Mac outright
 * (429), so this only ever runs from Supabase.
 *
 * ONE REQUEST for all 16 symbols (v7 quote). Two passes per cron call, 30 s
 * apart, like mp-refresh. Writes `market_live` (one row per symbol) and,
 * once the regular session has closed, that day's close into `daily_closes`
 * for the symbols nothing else captures, so the range filters can look back.
 *
 * Body: { force?: true } runs outside the window; { backfill?: true } loads
 * three months of daily closes for every symbol here.
 *
 * ⚠ DEPLOY WITH verify_jwt = false, like every cron-called function here.
 * pg_cron's cron_invoke_function sends the vault's sb_secret key, which is
 * not a JWT, so a verify_jwt function answers 401 to every scheduled call
 * (12 Oct 2026: the first deploys did exactly that).
 */
const BUILD = '2026-11-07.3';
const UA = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    + '(KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'application/json, text/plain, */*',
  'Accept-Language': 'en-US,en;q=0.9',
};
const SYMBOLS: { s: string; label: string; kind: 'index' | 'vix' | 'global' | 'watch' | 'future' }[] = [
  { s: 'SPY', label: 'SPY', kind: 'index' },
  { s: 'QQQ', label: 'QQQ', kind: 'index' },
  { s: 'IWM', label: 'IWM', kind: 'index' },
  { s: '^VIX', label: 'VIX', kind: 'vix' },
  { s: '^N225', label: 'Nikkei 225', kind: 'global' },
  { s: '^GDAXI', label: 'DAX', kind: 'global' },
  { s: '^NSEI', label: 'Nifty 50', kind: 'global' },
  { s: '000001.SS', label: 'Shanghai Composite', kind: 'global' },
  { s: '^HSI', label: 'Hang Seng', kind: 'global' },
  { s: '^TNX', label: '10y yield', kind: 'global' },
  { s: 'DX-Y.NYB', label: 'Dollar', kind: 'global' },
  { s: 'CL=F', label: 'Oil', kind: 'global' },
  { s: 'GC=F', label: 'Gold', kind: 'global' },
  { s: 'BTC-USD', label: 'Bitcoin', kind: 'global' },
  { s: 'INTU', label: 'INTU', kind: 'watch' },
  { s: 'ADBE', label: 'ADBE', kind: 'watch' },
  { s: 'PYPL', label: 'PYPL', kind: 'watch' },
  { s: 'VZ', label: 'VZ', kind: 'watch' },
  { s: 'TMUS', label: 'TMUS', kind: 'watch' },
  { s: 'SPCX', label: 'SPCX', kind: 'watch' },
  { s: 'TSLA', label: 'TSLA', kind: 'watch' },
  { s: 'APP', label: 'APP', kind: 'watch' },
  { s: 'ES=F', label: 'ES', kind: 'future' },
  { s: 'NQ=F', label: 'NQ', kind: 'future' },
  { s: 'RTY=F', label: 'RTY', kind: 'future' },
];
const FUTURES = SYMBOLS.filter((x) => x.kind === 'future').map((x) => x.s);

/* Sectors (handoff 6 Nov 2026, block 29): each SPDR's move is the sector's, and its 12 biggest names make
   the heat map (tile area = Yahoo's market cap, colour = the move). The lists are the funds' top holdings as
   of 2026; a name Yahoo stops answering for just drops off its map. */
const SECTORS: { sector: string; etf: string; names: [string, string][] }[] = [
  { sector: 'Technology', etf: 'XLK', names: [['NVDA', 'Nvidia'], ['AAPL', 'Apple'], ['MSFT', 'Microsoft'], ['AVGO', 'Broadcom'],
    ['ORCL', 'Oracle'], ['PLTR', 'Palantir'], ['AMD', 'AMD'], ['CSCO', 'Cisco'], ['IBM', 'IBM'], ['MU', 'Micron'],
    ['CRM', 'Salesforce'], ['LRCX', 'Lam Research']] },
  { sector: 'Financials', etf: 'XLF', names: [['BRK-B', 'Berkshire'], ['JPM', 'JPMorgan'], ['V', 'Visa'], ['MA', 'Mastercard'],
    ['BAC', 'Bank of America'], ['WFC', 'Wells Fargo'], ['GS', 'Goldman Sachs'], ['MS', 'Morgan Stanley'],
    ['AXP', 'American Express'], ['C', 'Citigroup'], ['SCHW', 'Schwab'], ['BLK', 'BlackRock']] },
  { sector: 'Health care', etf: 'XLV', names: [['LLY', 'Eli Lilly'], ['JNJ', 'Johnson & Johnson'], ['ABBV', 'AbbVie'],
    ['UNH', 'UnitedHealth'], ['MRK', 'Merck'], ['ABT', 'Abbott'], ['TMO', 'Thermo Fisher'], ['ISRG', 'Intuitive Surgical'],
    ['AMGN', 'Amgen'], ['BSX', 'Boston Scientific'], ['GILD', 'Gilead'], ['PFE', 'Pfizer']] },
  { sector: 'Consumer discretionary', etf: 'XLY', names: [['AMZN', 'Amazon'], ['TSLA', 'Tesla'], ['HD', 'Home Depot'],
    ['MCD', 'McDonald’s'], ['BKNG', 'Booking'], ['TJX', 'TJX'], ['LOW', 'Lowe’s'], ['SBUX', 'Starbucks'], ['NKE', 'Nike'],
    ['ORLY', 'O’Reilly'], ['CMG', 'Chipotle'], ['ABNB', 'Airbnb']] },
  { sector: 'Communication', etf: 'XLC', names: [['META', 'Meta'], ['GOOGL', 'Alphabet'], ['NFLX', 'Netflix'], ['DIS', 'Disney'],
    ['TMUS', 'T-Mobile'], ['VZ', 'Verizon'], ['T', 'AT&T'], ['CMCSA', 'Comcast'], ['EA', 'Electronic Arts'],
    ['TTWO', 'Take-Two'], ['CHTR', 'Charter'], ['WBD', 'Warner Bros.']] },
  { sector: 'Industrials', etf: 'XLI', names: [['GE', 'GE Aerospace'], ['CAT', 'Caterpillar'], ['RTX', 'RTX'], ['UBER', 'Uber'],
    ['GEV', 'GE Vernova'], ['BA', 'Boeing'], ['HON', 'Honeywell'], ['UNP', 'Union Pacific'], ['ETN', 'Eaton'],
    ['DE', 'Deere'], ['LMT', 'Lockheed'], ['ADP', 'ADP']] },
  { sector: 'Consumer staples', etf: 'XLP', names: [['WMT', 'Walmart'], ['COST', 'Costco'], ['PG', 'Procter & Gamble'],
    ['KO', 'Coca-Cola'], ['PM', 'Philip Morris'], ['PEP', 'PepsiCo'], ['MDLZ', 'Mondelez'], ['MO', 'Altria'],
    ['CL', 'Colgate'], ['MNST', 'Monster'], ['KR', 'Kroger'], ['KMB', 'Kimberly-Clark']] },
  { sector: 'Energy', etf: 'XLE', names: [['XOM', 'Exxon'], ['CVX', 'Chevron'], ['COP', 'ConocoPhillips'], ['WMB', 'Williams'],
    ['EOG', 'EOG'], ['KMI', 'Kinder Morgan'], ['SLB', 'SLB'], ['PSX', 'Phillips 66'], ['MPC', 'Marathon Petroleum'],
    ['OKE', 'ONEOK'], ['VLO', 'Valero'], ['BKR', 'Baker Hughes']] },
  { sector: 'Utilities', etf: 'XLU', names: [['NEE', 'NextEra'], ['SO', 'Southern'], ['CEG', 'Constellation'], ['DUK', 'Duke'],
    ['VST', 'Vistra'], ['AEP', 'AEP'], ['SRE', 'Sempra'], ['D', 'Dominion'], ['EXC', 'Exelon'], ['XEL', 'Xcel'],
    ['PEG', 'PSEG'], ['ETR', 'Entergy']] },
  { sector: 'Real estate', etf: 'XLRE', names: [['PLD', 'Prologis'], ['AMT', 'American Tower'], ['WELL', 'Welltower'],
    ['EQIX', 'Equinix'], ['SPG', 'Simon'], ['O', 'Realty Income'], ['DLR', 'Digital Realty'], ['PSA', 'Public Storage'],
    ['CCI', 'Crown Castle'], ['CBRE', 'CBRE'], ['VTR', 'Ventas'], ['IRM', 'Iron Mountain']] },
  { sector: 'Materials', etf: 'XLB', names: [['LIN', 'Linde'], ['SHW', 'Sherwin-Williams'], ['ECL', 'Ecolab'],
    ['APD', 'Air Products'], ['NEM', 'Newmont'], ['FCX', 'Freeport'], ['CTVA', 'Corteva'], ['MLM', 'Martin Marietta'],
    ['VMC', 'Vulcan'], ['NUE', 'Nucor'], ['DD', 'DuPont'], ['PPG', 'PPG']] },
];
const SECTOR_ROWS = SECTORS.flatMap((x) => [{ symbol: x.etf, sector: x.sector, etf: true, name: x.sector },
  ...x.names.map(([symbol, name]) => ({ symbol, sector: x.sector, etf: false, name }))]);

/* SPY, QQQ and IWM closes already come from mp-refresh's tapes. */
const CLOSES_HERE = SYMBOLS.filter((x) => x.kind === 'vix' || x.kind === 'watch').map((x) => x.s);

/* Kept for the life of the isolate; refetched once on any refusal. */
let session: { cookie: string; crumb: string } | null = null;

async function newSession(): Promise<{ cookie: string; crumb: string }> {
  const c = await fetch('https://fc.yahoo.com', { headers: UA, redirect: 'manual' });
  const cookie = (c.headers.get('set-cookie') ?? '').split(';')[0];
  await c.body?.cancel();
  if (!cookie) throw new Error('yahoo: no cookie');
  const r = await fetch('https://query2.finance.yahoo.com/v1/test/getcrumb', { headers: { ...UA, Cookie: cookie } });
  const crumb = (await r.text()).trim();
  if (!r.ok || !crumb || crumb.length > 40) throw new Error(`yahoo crumb ${r.status}`);
  return { cookie, crumb };
}

// deno-lint-ignore no-explicit-any
async function quotes(symbols: string[] = SYMBOLS.map((x) => x.s)): Promise<any[]> {
  // deno-lint-ignore no-explicit-any
  if (symbols.length > 60) { const out: any[] = []; for (let i = 0; i < symbols.length; i += 60) out.push(...await quotes(symbols.slice(i, i + 60))); return out; }
  for (let attempt = 0; attempt < 2; attempt++) {
    if (!session) session = await newSession();
    const r = await fetch(`https://query2.finance.yahoo.com/v7/finance/quote?symbols=`
      + `${encodeURIComponent(symbols.join(','))}&crumb=${encodeURIComponent(session.crumb)}`,
      { headers: { ...UA, Cookie: session.cookie }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 401 || r.status === 403) { await r.body?.cancel(); session = null; continue; }
    if (!r.ok) throw new Error(`yahoo quote ${r.status}`);
    const j = await r.json();
    return j?.quoteResponse?.result ?? [];
  }
  throw new Error('yahoo refused twice');
}

/* Daily closes for up to 20 symbols a call (v8 spark), for each symbol's week base. */
async function spark(symbols: string[]): Promise<Map<string, { d: string; c: number }[]>> {
  const out = new Map<string, { d: string; c: number }[]>();
  for (let i = 0; i < symbols.length; i += 20) {
    const part = symbols.slice(i, i + 20);
    if (!session) session = await newSession();
    const r = await fetch(`https://query2.finance.yahoo.com/v8/finance/spark?symbols=${encodeURIComponent(part.join(','))}`
      + `&range=1mo&interval=1d&crumb=${encodeURIComponent(session.crumb)}`,
      { headers: { ...UA, Cookie: session.cookie }, signal: AbortSignal.timeout(10_000) });
    if (!r.ok) { await r.body?.cancel(); continue; }
    // deno-lint-ignore no-explicit-any
    const j = await r.json() as Record<string, any>;
    for (const sym of part) {
      const x = j[sym] ?? (j.spark?.result ?? []).find((y: { symbol: string }) => y.symbol === sym)?.response?.[0];
      const t: number[] = x?.timestamp ?? [];
      const c: (number | null)[] = x?.close ?? x?.indicators?.quote?.[0]?.close ?? [];
      /* ⚠ The bar's UTC date, not New York's: a daily bar is stamped at its session's open in local time,
         so Tokyo's Monday (9:00 JST = 00:00 UTC) is Sunday evening in New York and would pass for last week. */
      out.set(sym, t.map((v, k) => ({ d: new Date(v * 1000).toISOString().slice(0, 10), c: c[k] as number })).filter((y) => y.c != null));
    }
  }
  return out;
}
/* Monday of the week a New York date falls in (Mon to Sun). */
function mondayOf(date: string): string {
  const d = new Date(`${date}T12:00:00Z`), wd = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - wd);
  return d.toISOString().slice(0, 10);
}

const ts = (s?: number) => (s ? new Date(s * 1000).toISOString() : null);
const n = (v: unknown) => (typeof v === 'number' && isFinite(v) ? v : null);

function nyParts(d = new Date()) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', weekday: 'short', hour: '2-digit', minute: '2-digit',
    year: 'numeric', month: '2-digit', day: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).map((x) => [x.type, x.value]));
  return { wd: p.weekday, mins: Number(p.hour) * 60 + Number(p.minute), date: `${p.year}-${p.month}-${p.day}` };
}

/* ⚠ WHO MAY CALL (audit, 13 Oct 2026). verify_jwt is off so pg_cron can call
   in, so the function checks instead: the scheduler's x-cron-key (vault
   `cron_secret`, secret CRON_SECRET; sent as x-admin-key for a manual
   admin call), the service-role key, or, where `users`
   is set, a signed-in user of the app or website. Anyone else gets a 401. */
async function callerOk(req: Request, users: boolean): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  const auth = req.headers.get('authorization') ?? '';
  if (auth && auth === `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) return true;
  if (!users || !auth.startsWith('Bearer ')) return false;
  const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`,
    { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: auth } });
  await r.body?.cancel();
  return r.ok;
}
const refused = () => new Response(JSON.stringify({ ok: false, error: 'not allowed' }),
  { status: 401, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'OPTIONS' && !(await callerOk(req, false))) return refused();
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  const upsert = async (table: string, conflict: string, rows: unknown[]) => {
    if (!rows.length) return;
    const r = await fetch(`${url}/rest/v1/${table}?on_conflict=${conflict}`, {
      method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    });
    if (!r.ok) throw new Error(`${table} ${r.status} ${(await r.text()).slice(0, 200)}`);
  };
  let body: { force?: boolean; backfill?: boolean } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is fine */ }

  try {
    if (body.backfill) {
      const out: Record<string, number> = {};
      for (const s of CLOSES_HERE) {
        const r = await fetch(`https://query2.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(s)}`
          + `?range=3mo&interval=1d`, { headers: UA });
        if (!r.ok) { out[s] = -r.status; await r.body?.cancel(); continue; }
        const res = (await r.json())?.chart?.result?.[0];
        const t: number[] = res?.timestamp ?? [];
        const c: (number | null)[] = res?.indicators?.quote?.[0]?.close ?? [];
        const rows = t.map((x, i) => ({ ticker: s, date: nyParts(new Date(x * 1000)).date, close_price: c[i] }))
          .filter((x) => x.close_price != null);
        await upsert('daily_closes', 'ticker,date', rows);
        out[s] = rows.length;
      }
      return new Response(JSON.stringify({ ok: true, build: BUILD, backfill: out }),
        { headers: { 'Content-Type': 'application/json' } });
    }

    const ny = nyParts();
    const weekday = !['Sat', 'Sun'].includes(ny.wd);
    /* CME's equity index futures: Sunday 18:00 to Friday 17:00 New York, with a 17:00-18:00 break each
       weekday. The cron calls every minute; outside both windows this returns at once. */
    const futuresOpen = (ny.wd === 'Sun' && ny.mins >= 18 * 60)
      || (['Mon', 'Tue', 'Wed', 'Thu'].includes(ny.wd) && !(ny.mins >= 17 * 60 && ny.mins < 18 * 60))
      || (ny.wd === 'Fri' && ny.mins < 17 * 60);
    if (!body.force && !(weekday && ny.mins >= 4 * 60 && ny.mins < 20 * 60) && !futuresOpen) {
      return new Response(JSON.stringify({ ok: true, build: BUILD, skipped: 'outside 4:00-20:00 ET weekdays and the futures hours' }),
        { headers: { 'Content-Type': 'application/json' } });
    }

    /* The books' own names (New Home's pre-market lede and after-hours moves): every ticker mp-refresh prices,
       less any already listed above. Kind 'name': no closes kept here (mp-refresh owns those). */
    const known = new Set(SYMBOLS.map((x) => x.s));
    const bookNames: { s: string; label: string; kind: 'name' }[] = await fetch(`${url}/rest/v1/ticker_quotes_live?select=ticker`, { headers: h })
      .then((r) => (r.ok ? r.json() : [])).then((rs: { ticker: string }[]) => [...new Set(rs.map((x) => String(x.ticker).toUpperCase()))]
        .filter((t) => /^[A-Z.]{1,6}$/.test(t) && !known.has(t)).map((t) => ({ s: t, label: t, kind: 'name' as const })))
      .catch(() => []);

    /* Each symbol's week base (the last close before this week's Monday), filled once a week per symbol. */
    const monday = mondayOf(ny.date);
    type Wk = { week_base: number | null; week_base_date: string | null; week_start: string | null };
    const weekOf = new Map<string, Wk>();
    let sparked = 0;
    try {
      for (const t of ['market_live', 'market_sectors']) {
        const r = await fetch(`${url}/rest/v1/${t}?select=symbol,week_base,week_base_date,week_start`, { headers: h });
        if (r.ok) for (const x of await r.json() as (Wk & { symbol: string })[]) weekOf.set(x.symbol, x);
        else await r.body?.cancel();
      }
      const need = [...SYMBOLS.filter((x) => x.kind !== 'future').map((x) => x.s), ...bookNames.map((x) => x.s),
        ...SECTOR_ROWS.map((x) => x.symbol)].filter((s) => weekOf.get(s)?.week_start !== monday);
      if (need.length) {
        const sp = await spark(need);
        for (const s of need) {
          const b = (sp.get(s) ?? []).filter((x) => x.d < monday).at(-1);
          if (b) { weekOf.set(s, { week_base: b.c, week_base_date: b.d, week_start: monday }); sparked++; }
        }
      }
    } catch { /* the week's moves wait for the next call */ }
    const wk = (s: string) => {
      const w = weekOf.get(s);
      return w ? { week_base: w.week_base, week_base_date: w.week_base_date, week_start: w.week_start } : {};
    };

    /* Each sector's share of the S&P 500 (the heat map's header), from SPY's holdings by sector (Yahoo, Morningstar's
       sectors), once a day onto the sector fund's row. Never allowed to stop the quotes. */
    let spWeights = 0;
    try {
      const r = await fetch(`${url}/rest/v1/market_sectors?etf=eq.true&select=symbol,sp_weight_at`, { headers: h });
      const have = r.ok ? await r.json() as { symbol: string; sp_weight_at: string | null }[] : [];
      const stale = !have.length || have.some((x) => !x.sp_weight_at || Date.now() - Date.parse(x.sp_weight_at) > 20 * 3600e3);
      if (stale) {
        if (!session) session = await newSession();
        const q = await fetch(`https://query2.finance.yahoo.com/v10/finance/quoteSummary/SPY?modules=topHoldings&crumb=${encodeURIComponent(session.crumb)}`,
          { headers: { ...UA, Cookie: session.cookie }, signal: AbortSignal.timeout(10_000) });
        // deno-lint-ignore no-explicit-any
        const sw = q.ok ? ((await q.json())?.quoteSummary?.result?.[0]?.topHoldings?.sectorWeightings ?? []) as Record<string, any>[] : [];
        if (!q.ok) await q.body?.cancel();
        const MAP: Record<string, string> = { technology: 'Technology', financial_services: 'Financials', healthcare: 'Health care',
          consumer_cyclical: 'Consumer discretionary', communication_services: 'Communication', industrials: 'Industrials',
          consumer_defensive: 'Consumer staples', energy: 'Energy', utilities: 'Utilities', realestate: 'Real estate', basic_materials: 'Materials' };
        const at = new Date().toISOString();
        const wrows = sw.flatMap((o) => Object.entries(o)).map(([k, v]) => {
          const sec = MAP[k], w = n((v as { raw?: number })?.raw ?? v), x = SECTORS.find((y) => y.sector === sec);
          return sec && w != null && x ? { symbol: x.etf, sector: sec, etf: true, name: sec, sp_weight: +(w * 100).toFixed(2), sp_weight_at: at } : null;
        }).filter(Boolean) as Record<string, unknown>[];
        if (wrows.length) { await upsert('market_sectors', 'symbol', wrows); spWeights = wrows.length; }
      }
    } catch { /* tomorrow's call tries again */ }

    const passes: Record<string, unknown>[] = [];
    for (let pass = 0; pass < 2; pass++) {
      if (pass === 1) await new Promise((r) => setTimeout(r, 30_000 - (Date.now() % 30_000)));
      const t0 = Date.now();
      const res = await quotes([...SYMBOLS.map((x) => x.s), ...bookNames.map((x) => x.s)]);
      const now = new Date().toISOString();
      const rows = [...SYMBOLS, ...bookNames].map((x) => {
        const q = res.find((r) => r.symbol === x.s);
        if (!q || n(q.regularMarketPrice) == null) return null;
        const state = String(q.marketState ?? '');
        const pre = n(q.preMarketPrice), post = n(q.postMarketPrice);
        /* The figure a card shows: the session it is in, or the last one. */
        const price = state.startsWith('PRE') && pre != null ? pre
          : state.startsWith('POST') && post != null ? post : n(q.regularMarketPrice);
        return {
          symbol: x.s, label: x.label, kind: x.kind, market_state: state || null,
          price, prev_close: n(q.regularMarketPreviousClose),
          regular_price: n(q.regularMarketPrice), regular_change: n(q.regularMarketChange),
          regular_change_pct: n(q.regularMarketChangePercent),
          pre_price: pre, pre_change_pct: n(q.preMarketChangePercent),
          post_price: post, post_change_pct: n(q.postMarketChangePercent),
          regular_time: ts(q.regularMarketTime),
          ext_time: ts(state.startsWith('PRE') ? q.preMarketTime : q.postMarketTime),
          market_cap: n(q.marketCap),
          ...wk(x.s),
          captured_at: now,
        };
      }).filter(Boolean) as Record<string, unknown>[];
      await upsert('market_live', 'symbol', rows);

      /* Sectors and their heat maps: never allowed to stop the rows above. */
      let sectors = 0;
      try {
        const sq = await quotes(SECTOR_ROWS.map((x) => x.symbol));
        const srows = SECTOR_ROWS.map((x) => {
          const q = sq.find((r) => r.symbol === x.symbol);
          if (!q || n(q.regularMarketPrice) == null) return null;
          return { symbol: x.symbol, sector: x.sector, etf: x.etf, name: x.name, market_cap: n(q.marketCap),
            price: n(q.regularMarketPrice), prev_close: n(q.regularMarketPreviousClose),
            day_pct: n(q.regularMarketChangePercent), market_state: q.marketState ?? null,
            regular_time: ts(q.regularMarketTime), ...wk(x.symbol), captured_at: now };
        }).filter(Boolean) as Record<string, unknown>[];
        await upsert('market_sectors', 'symbol', srows);
        sectors = srows.length;
      } catch { /* next pass */ }

      /* After the US close, today's regular close is final: keep it. */
      if (ny.mins >= 16 * 60 + 5) {
        const closes = rows
          .filter((r) => CLOSES_HERE.includes(String(r.symbol)) && r.regular_time
            && nyParts(new Date(String(r.regular_time))).date === ny.date)
          .map((r) => ({ ticker: r.symbol, date: ny.date, close_price: r.regular_price }));
        await upsert('daily_closes', 'ticker,date', closes);
      }
      passes.push({ pass, symbols: rows.length, sectors, ms: Date.now() - t0 });
    }

    /* Each future's 16:00 price, the base the morning cards divide by: the
       close of the 15:59 one-minute bar. Yahoo runs ~10 min behind, so it is
       read from 16:12, once a day (skipped when today's rows are in). */
    let bases = 0;
    if (ny.mins >= 16 * 60 + 12) {
      const have = await fetch(`${url}/rest/v1/daily_closes?date=eq.${ny.date}&ticker=in.(${FUTURES.map((x) => `"${x}"`).join(',')})&select=ticker`,
        { headers: h }).then((r) => r.ok ? r.json() : []) as Array<{ ticker: string }>;
      const need = FUTURES.filter((f) => !have.some((x) => x.ticker === f));
      const rows: Array<{ ticker: string; date: string; close_price: number }> = [];
      for (const f of need) {
        const r = await fetch(`https://query2.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(f)}?range=1d&interval=1m`,
          { headers: UA, signal: AbortSignal.timeout(10_000) });
        if (!r.ok) { await r.body?.cancel(); continue; }
        const res = (await r.json())?.chart?.result?.[0];
        const t: number[] = res?.timestamp ?? [];
        const c: (number | null)[] = res?.indicators?.quote?.[0]?.close ?? [];
        let best: number | null = null;
        for (let i = 0; i < t.length; i++) {
          const p = nyParts(new Date(t[i] * 1000));
          if (p.date === ny.date && p.mins < 16 * 60 && c[i] != null) best = c[i];   // last bar starting before 16:00
        }
        if (best != null) rows.push({ ticker: f, date: ny.date, close_price: best });
      }
      await upsert('daily_closes', 'ticker,date', rows);
      bases = rows.length;
    }

    await upsert('sync_heartbeat', 'feed', [{
      feed: 'market-tape', ran_at: new Date().toISOString(), rows_written: Number(passes.at(-1)?.symbols ?? 0),
      detail: `yahoo · ${passes.map((p) => p.symbols).join('/')} symbols · ${passes.map((p) => p.sectors).join('/')} sector rows${sparked ? ` · ${sparked} week bases` : ''}${bases ? ` · ${bases} futures bases` : ''}`,
    }]);
    return new Response(JSON.stringify({ ok: true, build: BUILD, passes }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
