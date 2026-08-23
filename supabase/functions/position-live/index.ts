/**
 * position-live — what a position you ALREADY HOLD is doing, and what it needs.
 *
 * Not a score. Ranking one position against itself says nothing. Five sections:
 *
 *   ANALYSTS        rating changes, the re-rating cluster, target, consensus
 *   PRICE           moving averages, drawdown, extension, and option flow
 *   COMPANY         guidance and the earnings date
 *   HEADLINES       two, linked, filtered to ones about this company
 *   WHERE YOU STAND the grind: what you paid, what premium took off, all-in
 *   WHAT IS COVERED calls against shares, assignment risk
 *   THE FLOOR       the only genuine decision here
 *   DO              what actually needs doing
 *
 * ⚠ NO STRIKE PROPOSAL. The obvious feature is "write further out when the
 * stock is extended". It was simulated on 6,000 paired paths and it LOSES: at
 * flat drift it costs 0.09 to 0.29 points at every threshold and offset tried,
 * and it does not break even until roughly +40% annual drift. Extension is
 * shown because it explains why a week feels uncomfortable. It changes nothing.
 *
 * ⚠ TWO LAYOUTS FAILED HERE. Do not reintroduce either.
 *
 * Bearish / Supportive HEADINGS failed because two labelled buckets are a
 * QUOTA: the card had to fill both every day whether or not anything had
 * happened, so it reached for what is permanently true, a 120-day aggregate,
 * which then counted one event many times. NKE's "27 analyst actions" were 14
 * firms answering a single earnings report. Nik: "reading this every day, it
 * feels like I'm repeating the same thing."
 *
 * A DATED FEED failed the opposite way. With the substance moved out to WHERE
 * YOU STAND, the wire filled the space it left. Nik: "everything is news,
 * where is the analyst upgrade or consensus, technical indicator", and he did
 * not want today/yesterday stamps either.
 *
 * What works is DOMAIN grouping with direction as a per-bullet TAG. A tag
 * rides on a bullet that already earned its place, so unlike a heading it can
 * never manufacture content. Freshness lives in the NEW tag and the counter.
 *
 * ⚠ THE CONSENSUS TARGET IS NOT USED against spot. That feed aggregates every
 * analyst who ever covered the name: NKE reads 91.56 against a spot of 40.91.
 * The usable number is the rolling 120-day median of analyst_actions, and the
 * count of raises against cuts matters more than either.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday, daysBetween } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-23.5';
const POLY = 'https://api.polygon.io';

/** The Friday at least 5 sessions out: the contract actually written. */
function writeFriday(from: Date): string {
  const d = new Date(from.getTime());
  do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() !== 5);
  if (daysBetween(from, d) < 5) d.setUTCDate(d.getUTCDate() + 7);
  return ymd(d);
}

/** Live chain for one expiry, narrowed around spot. */
async function chain(t: string, expiry: string, spot: number, k: string, window = 0) {
  const u = new URL(`${POLY}/v3/snapshot/options/${t}`);
  if (window) {
    /* A floor is "about four months out", and an exact date is almost never a
       listed expiry, so asking for one returns nothing and the top-up silently
       goes unpriced. Ask for a window and take whichever expiry the chain
       actually offers. */
    u.searchParams.set('expiration_date.gte', ymd(addDays(parseISO(expiry), -window)));
    u.searchParams.set('expiration_date.lte', ymd(addDays(parseISO(expiry), window)));
  } else {
    u.searchParams.set('expiration_date', expiry);
  }
  u.searchParams.set('strike_price.gte', String(Math.floor(spot * 0.88)));
  u.searchParams.set('strike_price.lte', String(Math.ceil(spot * 1.12)));
  u.searchParams.set('limit', '250');
  u.searchParams.set('apiKey', k);
  try {
    const r = await fetch(u.toString());
    if (!r.ok) return [];
    const j = await r.json();
    return (j?.results ?? []).map((c: Record<string, any>) => ({
      strike: Number(c.details?.strike_price), type: String(c.details?.contract_type),
      expiry: String(c.details?.expiration_date ?? ''),
      mid: (c.last_quote?.bid > 0 && c.last_quote?.ask > 0)
        ? (c.last_quote.bid + c.last_quote.ask) / 2 : Number(c.day?.close ?? 0),
    })).filter((c: { strike: number }) => c.strike > 0);
  } catch { return []; }
}
/** The company's name, so a headline tagged to NKE that is actually about
 *  Dick's Sporting Goods can be dropped. Falls back to showing everything:
 *  a failed lookup must not silently blank the headlines. */
async function tickerName(t: string, k: string): Promise<string> {
  try {
    // NOT /v3/reference/ticker-details, which 404s. Verified against the
    // scanner's own probe before trusting it.
    const r = await fetch(`${POLY}/v3/reference/tickers/${t}?apiKey=${k}`);
    if (!r.ok) return '';
    const j = await r.json();
    return String(j?.results?.name ?? '');
  } catch { return ''; }
}

const N = (v: unknown, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v));
const usd = (v: number) => `$${Math.round(v).toLocaleString('en-US')}`;
const pct = (v: number, dp = 1) => `${v >= 0 ? '+' : ''}${v.toFixed(dp)}%`;
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
/** 2026-09-24 -> 24 Sep. Nobody reads a date aloud as an ISO string. */
const day = (iso: string) => {
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  return `${Number(d)} ${MON[Number(m) - 1]}${y !== String(new Date().getUTCFullYear()) ? ` ${y}` : ''}`;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const pk = Deno.env.get('POLYGON_API_KEY')!;
    const D = db(url, key);
    let body: { tickers?: string[]; peek?: boolean } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* none */ }
    const today = parseISO(nyToday());
    const todayISO = ymd(today);
    const d120 = ymd(addDays(today, -120));

    /* ⚠ INCOME SLEEVE NAMES ONLY. This card is built on the sleeve's rules:
       one call and one put per 100 shares, a floor sized to shares PLUS puts
       sold. TLT does not work that way at all. It has no block, no conviction
       and no floor; the put IS the trade, sold on the second red day. See
       docs/STRATEGIES.md.

       Rendering every ticker with shares pulled TLT in and produced
       "sell -27 puts" and "your floor needs 49", which is the sleeve's rule
       applied to a book that has never had one. Same confusion as CPB, and
       the strategies file exists precisely to stop it. */
    const [lots, sleeveRows] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker,qty_remaining,cost_per_share'),
      D.get('income_sleeve_names?active=is.true&select=ticker'),
    ]);
    const sleeve = new Set(sleeveRows.map((r) => String(r.ticker)));
    const names = body.tickers ?? [...new Set(lots.map((r) => String(r.ticker)))].filter((t) => sleeve.has(t));
    if (!names.length) return json(200, { ok: true, empty: true, note: 'no shares held' });
    const inList = `(${names.join(',')})`;

    const [trades, quotes, closes, pers, scan, earn, guide, acts, cons, news, divs, seen, ohist] = await Promise.all([
      D.get(`option_trades?ticker=in.${inList}&voided_at=is.null`
        + '&select=ticker,action,option_type,direction,contracts,strike,premium,expiry'),
      D.get(`ticker_quotes_latest?ticker=in.${inList}&select=ticker,spot`),
      /* DESC, then reversed. Ascending hits PostgREST's row cap and returns
         the OLDEST rows, so the 20-day mean was computed on 2024 prices: NKE's
         50-day read 52.24 against a true 42.49. */
      D.get(`scanner_closes?ticker=in.${inList}&select=ticker,date,close&order=date.desc&limit=6000`),
      D.get(`scanner_persistence?ticker=in.${inList}&select=ticker,persistence,measured`),
      D.get(`income_scanner_results?ticker=in.${inList}&select=ticker,asof,edge,atm_straddle_pct,pos_52w,score&order=asof.desc`),
      D.get(`earnings_events?ticker=in.${inList}&report_date=gte.${todayISO}`
        + '&select=ticker,report_date,report_time,date_estimated&order=report_date.asc'),
      D.get(`guidance_events?ticker=in.${inList}&select=ticker,date,direction,fiscal_period,notes,importance&order=date.desc`),
      D.get(`analyst_actions?ticker=in.${inList}&date=gte.${d120}`
        + '&select=ticker,date,firm,rating,rating_action,price_target,previous_price_target,price_target_action&order=date.desc'),
      D.get(`analyst_consensus?ticker=in.${inList}&select=*&order=as_of_date.desc`),
      D.get(`name_news?ticker=in.${inList}&select=ticker,published,title,publisher,url&order=published.desc`),
      D.get(`dividends?ticker=in.${inList}&select=ticker,ex_date,cash_amount,frequency&order=ex_date.desc`),
      D.get('income_card_seen?select=ticker,since_on,visit_on'),
      /* Ordered DESC and generously capped: the OI comparison must line up
         SAME EXPIRY against SAME EXPIRY, so it needs several days back. */
      D.get(`scanner_option_history?ticker=in.${inList}`
        + '&select=ticker,asof,expiry,option_oi,option_vol&order=asof.desc&limit=2000'),
    ]);

    const first = (a: Record<string, unknown>[], t: string) =>
      a.find((x) => String(x.ticker) === t) as Record<string, unknown> | undefined;
    const out = await Promise.all(names.map(async (t) => {
      const mine = lots.filter((l) => String(l.ticker) === t);
      const shares = mine.reduce((s, l) => s + N(l.qty_remaining), 0);
      const paid = mine.reduce((s, l) => s + N(l.qty_remaining) * N(l.cost_per_share), 0);
      const avg = shares ? paid / shares : 0;
      const spot = N(first(quotes as Record<string, unknown>[], t)?.spot);
      const lots100 = Math.floor(shares / 100);

      // legs, netted by contract
      const leg = new Map<string, { t: string; d: string; k: number; e: string; n: number; prem: number }>();
      let premTaken = 0, floorCost = 0;
      for (const x of trades.filter((r) => String(r.ticker) === t)) {
        const k = `${x.option_type}|${x.direction}|${N(x.strike)}|${String(x.expiry).slice(0, 10)}`;
        const e = leg.get(k) ?? { t: String(x.option_type), d: String(x.direction), k: N(x.strike), e: String(x.expiry).slice(0, 10), n: 0, prem: 0 };
        e.n += (x.action === 'open' ? 1 : -1) * N(x.contracts);
        leg.set(k, e);
        /* ⚠ SHORT LEGS ONLY. Subtracting the long puts here AND adding
           floorCost into all-in charges the floor twice, which is the exact
           double-count flagged in the Aug wheel study: it made NKE read
           premium -$6,615 and an effective cost ABOVE what was paid. */
        if (x.direction === 'short') {
          premTaken += N(x.contracts) * N(x.premium) * 100 * (x.action === 'open' ? 1 : -1);
        }
        if (x.direction === 'long' && x.option_type === 'put' && x.action === 'open') floorCost += N(x.contracts) * N(x.premium) * 100;
      }
      const live = [...leg.values()].filter((l) => l.n > 0.0001 && l.e >= todayISO);
      const calls = live.filter((l) => l.t === 'call' && l.d === 'short');
      const sputs = live.filter((l) => l.t === 'put' && l.d === 'short');
      const floor = live.filter((l) => l.t === 'put' && l.d === 'long');
      const nCalls = calls.reduce((s, l) => s + l.n, 0);
      const nPuts = sputs.reduce((s, l) => s + l.n, 0);
      const nFloor = floor.reduce((s, l) => s + l.n, 0);
      const fk = floor.length ? Math.max(...floor.map((l) => l.k)) : 0;
      const itmCall = calls.filter((l) => spot >= l.k);
      const nextExp = live.filter((l) => l.d === 'short').map((l) => l.e).sort()[0];

      const x0 = premTaken;
      const effective = shares ? avg - premTaken / shares : 0;
      const allIn = shares ? effective + floorCost / shares : 0;

      // technicals from stored history
      const px = closes.filter((r) => String(r.ticker) === t).map((r) => N(r.close)).reverse();
      const mean = (a: number[]) => a.reduce((s, x) => s + x, 0) / (a.length || 1);
      const m20 = px.length >= 20 ? mean(px.slice(-20)) : 0;
      const sd20 = px.length >= 20 ? Math.sqrt(mean(px.slice(-20).map((x) => (x - m20) ** 2))) : 0;
      const ext = sd20 ? (spot - m20) / sd20 : 0;
      const m50 = px.length >= 50 ? mean(px.slice(-50)) : 0;
      const m200 = px.length >= 200 ? mean(px.slice(-200)) : 0;
      const hi52 = px.length ? Math.max(...px.slice(-252)) : 0;

      // analysts: the 120-day median, NOT the all-time consensus target
      const a = acts.filter((r) => String(r.ticker) === t);
      const tg = a.map((r) => N(r.price_target)).filter((x) => x > 0).sort((p, q) => p - q);
      const med = tg.length ? tg[Math.floor(tg.length / 2)] : 0;
      const cuts = a.filter((r) => r.price_target_action === 'lowers').length;
      const raises = a.filter((r) => r.price_target_action === 'raises').length;
      const downs = a.filter((r) => r.rating_action === 'downgrades').length;
      const ups = a.filter((r) => r.rating_action === 'upgrades').length;
      const g0 = guide.find((r) => String(r.ticker) === t);
      const c0 = cons.find((r) => String(r.ticker) === t);
      const e0 = earn.find((r) => String(r.ticker) === t);
      const s0 = scan.find((r) => String(r.ticker) === t);
      const p0 = first(pers as Record<string, unknown>[], t);
      const nw = news.filter((r) => String(r.ticker) === t).slice(0, 3);
      const dv0 = divs.find((r) => String(r.ticker) === t);
      const nextWrite = writeFriday(today);

      const need = lots100 + nPuts;
      const needAfter = lots100 * 2;
      /* ── Price the actual trade ──────────────────────────────────────────
         "Write 20 calls and 20 puts at the money" is a instruction with no
         number attached, and Nik places these by hand. Pull the live chain for
         the expiry actually being written and quote the strike and the mid, so
         the card says what it pays before he opens the broker. */
      const wk = await chain(t, nextWrite, spot, pk);
      const near = (arr: { strike: number; type: string; mid: number; expiry?: string }[], ty: string) => {
        const c = arr.filter((x) => x.type === ty && x.mid > 0);
        if (!c.length) return null;
        return c.reduce((b, x) => Math.abs(x.strike - spot) < Math.abs(b.strike - spot) ? x : b);
      };
      const atmC = near(wk, 'call'), atmP = near(wk, 'put');
      /* The floor is a FOUR-MONTH at-the-money put, per the spec. Nearest
         listed expiry to 120 days out, from whatever the chain offers. */
      const floorExp = ymd(addDays(today, 120));
      const fl = nFloor < needAfter ? await chain(t, floorExp, spot, pk, 30) : [];
      const atmF = near(fl, 'put');

      /* Sentences, not field-speak. The two paragraphs above read like a
         person and then this said "floor short 20 against 20 shares plus 20
         puts sold", which is the same jargon wearing a bullet. */
      const doList: string[] = [];
      if (nCalls < lots100) {
        /* Never negative. TLT carried 38 short puts against 11 lots and this
           asked for "-27 puts" at a credit of -$1,147. */
        const nc = Math.max(0, lots100 - nCalls), np = Math.max(0, lots100 - nPuts);
        if (nc === 0 && np === 0) { /* nothing to add */ } else
        { if (nc) doList.push(atmC
          ? `Sell ${nc} calls, ${atmC.strike} strike, ${day(nextWrite)}, about ${atmC.mid.toFixed(2)} each, ${usd(atmC.mid * 100 * nc)} in`
          : `Sell ${nc} calls at the money, ${day(nextWrite)}`);
        if (np) doList.push(atmP
          ? `Sell ${np} puts, ${atmP.strike} strike, ${day(nextWrite)}, about ${atmP.mid.toFixed(2)} each, ${usd(atmP.mid * 100 * np)} in`
          : `Sell ${np} puts at the money, ${day(nextWrite)}`); }
      }
      for (const c of itmCall) {
        doList.push(`Let the ${c.n} calls at ${c.k} go: ${(c.n * 100).toLocaleString('en-US')} shares `
          + `leave on ${day(c.e)} and ${usd(c.n * 100 * c.k)} comes back.`);
      }
      if (nFloor < need) {
        doList.push(`Buy ${need - nFloor} more floor puts. You hold ${nFloor} against the ${need} your rule asks for.`);
      } else if (nFloor < needAfter) {
        const gap = needAfter - nFloor;
        doList.push(atmF
          ? `Buy ${gap} puts at ${atmF.strike}, ${day(String(atmF.expiry ?? floorExp))}, about ${atmF.mid.toFixed(2)} each, ${usd(atmF.mid * 100 * gap)} out, to close the floor gap`
          : `Buy ${gap} four-month puts at the money to close the floor gap`);
        const inFlow = (atmC ? atmC.mid * 100 * (lots100 - nCalls) : 0) + (atmP ? atmP.mid * 100 * (lots100 - nPuts) : 0);
        const outFlow = atmF ? atmF.mid * 100 * gap : 0;
        /* Only claim a NET when both sides are actually priced. Reporting
           inflow alone under a "net after the floor top-up" label overstates
           the week by the entire cost of the floor. */
        if (inFlow && outFlow) doList.push(`Net after the floor top-up: ${usd(inFlow - outFlow)}`);
        else if (inFlow) doList.push(`Premium in: ${usd(inFlow)}. The floor top-up is not priced here.`);
      }
      if (fk && (spot - fk) / spot > 0.15) {
        doList.push(`Consider rolling the floor up. At ${((spot - fk) / spot * 100).toFixed(0)}% below the price it protects very little.`);
      }
      if (g0 && String(g0.direction) === 'cut' && String(g0.date) >= d120) {
        doList.push(`The company cut guidance on ${day(String(g0.date))}. Think hard before adding to this one.`);
      }

      /* ── The situational read: ANALYSTS, PRICE, COMPANY, HEADLINES ────────
         Grouped by DOMAIN, so it reads as a situation rather than a timeline.

         ⚠ NOT BEARISH / SUPPORTIVE SECTIONS. Two labelled buckets are a QUOTA:
         the card had to fill both every day whether or not anything happened,
         so it reached for what is permanently true, a 120-day aggregate, which
         then counted ONE event many times. NKE's "27 analyst actions" were 14
         firms answering a single earnings report on 1 July. Nik: "reading this
         every day, it feels like I'm repeating the same thing."

         ⚠ NOR IS IT A DATED FEED. That was the next attempt and it failed the
         other way: with the substance moved out, the wire filled the space and
         the card read like a Motley Fool channel. Nik: "everything is news,
         where is the analyst upgrade or consensus, technical indicator."

         Direction returns as a per-bullet TAG rather than a heading, which is
         safe for the reason the headings were not: a tag rides on a bullet
         that already earned its place, so it can never manufacture content. */
      const sRow = (seen as Record<string, unknown>[]).find((r) => String(r.ticker) === t);
      const lastVisit = sRow ? String(sRow.visit_on ?? '').slice(0, 10) : '';
      /* The cutoff moves on the FIRST open of a new day and lands on the
         PREVIOUS visit day, never on today. Collapse the two dates into one
         and opening the app twice before lunch empties the card the second. */
      const sinceOn = sRow
        ? (lastVisit && lastVisit < todayISO ? lastVisit : String(sRow.since_on ?? '').slice(0, 10))
        : '';
      const cut = sinceOn || ymd(addDays(today, -14));

      type Line = { text: string; tags: string[] };
      const L = (text: string, ...tags: Array<string | null>): Line =>
        ({ text, tags: tags.filter((x): x is string => !!x) });
      const isNew = (d: string) => d > cut ? 'NEW' : null;
      const ago = (d: string) => {
        const n = daysBetween(parseISO(d), today);
        return n <= 0 ? 'today' : n === 1 ? 'yesterday' : `${n} days ago`;
      };

      // ── ANALYSTS ──────────────────────────────────────────────────────────
      /* IMPORTANT is derived from RARITY, not from Benzinga's own field, which
         scores 40% of all actions a 5 and 58% a 0 and every NKE action a 5. A
         rating change is 9% of the feed; a "maintains" is 77%. */
      const analysts: Line[] = [];
      const rateChg = a.find((r) => r.rating_action === 'downgrades' || r.rating_action === 'upgrades');
      if (rateChg) {
        const dn = rateChg.rating_action === 'downgrades';
        const pt = N(rateChg.price_target), pp = N(rateChg.previous_price_target);
        const d = String(rateChg.date).slice(0, 10);
        analysts.push(L(`${rateChg.firm} ${dn ? 'cut' : 'raised'} it to ${rateChg.rating} ${ago(d)}`
          + (pt && pp && pt !== pp ? `, ${pp} to ${pt}` : ''),
          isNew(d), dn ? 'BEARISH' : 'BULLISH', 'IMPORTANT'));
      }
      /* The biggest same-day cluster, as ONE line. Counting each firm
         separately is what turned a single earnings reaction into "22 cuts". */
      const byDay = new Map<string, Record<string, unknown>[]>();
      for (const r of a) {
        const dd = String(r.date).slice(0, 10);
        const g = byDay.get(dd); if (g) g.push(r); else byDay.set(dd, [r]);
      }
      const big = [...byDay.entries()].filter(([, g]) => g.length >= 3)
        .sort((x, y) => y[1].length - x[1].length)[0];
      if (big) {
        const [dd, g] = big;
        const cu = g.filter((r) => r.price_target_action === 'lowers').length;
        const ra = g.filter((r) => r.price_target_action === 'raises').length;
        const parts: string[] = [];
        if (cu) parts.push(`${cu} target cut${cu > 1 ? 's' : ''}`);
        if (ra) parts.push(`${ra} target raise${ra > 1 ? 's' : ''}`);
        analysts.push(L(`${g.length} firms re-rated it ${ago(dd)}`
          + (parts.length ? `, ${parts.join(' and ')}` : ''),
          isNew(dd), cu > ra ? 'BEARISH' : ra > cu ? 'BULLISH' : null,
          g.length >= 5 ? 'IMPORTANT' : null));
      }
      if (med) {
        analysts.push(L(`Median target ${med.toFixed(2)}, ${pct((med / spot - 1) * 100)} against spot`,
          med > spot ? 'BULLISH' : 'BEARISH'));
      }
      if (c0) {
        const bu = N(c0.strong_buy) + N(c0.buy), se = N(c0.sell) + N(c0.strong_sell);
        analysts.push(L(`${N(c0.contributors)} analysts: ${bu} buy, ${N(c0.hold)} hold, ${se} sell`,
          bu > se * 3 ? 'BULLISH' : se > bu ? 'BEARISH' : null));
      }

      // ── PRICE ─────────────────────────────────────────────────────────────
      const price: Line[] = [];
      if (m50 && m200) {
        const below = spot < m50 && spot < m200, above = spot > m50 && spot > m200;
        price.push(L(`${below ? 'Below' : above ? 'Above' : 'Between'} the 50-day ${m50.toFixed(2)}`
          + ` and the 200-day ${m200.toFixed(2)}`, below ? 'BEARISH' : above ? 'BULLISH' : null));
      }
      /* No direction tag on this one on purpose. A 48% drawdown is weakness if
         you read momentum and it is the ENTRY CONDITION if you run the sleeve.
         Tagging it would be the engine picking a side it cannot justify. */
      if (hi52 && p0) {
        price.push(L(`${Math.abs((spot / hi52 - 1) * 100).toFixed(1)}% off the high, `
          + `${N(p0.persistence).toFixed(0)}% persistence`));
      }
      if (sd20) {
        price.push(L(`${Math.abs(ext).toFixed(2)}sd ${ext < 0 ? 'below' : 'above'} its 20-day mean`
          + `${Math.abs(ext) < 1 ? ', not at an extreme' : ''}`));
      }
      /* ── Option flow: where the traders are actually moving ────────────────
         ⚠ SAME EXPIRY ONLY. The scanner measures the expiry it would WRITE, so
         the raw series rolls every Friday: NKE read 87,881 open interest on the
         18th and 41,914 on the 20th, which is the roll from 21 Aug to 28 Aug and
         not one contract of genuine unwinding. Compared naively this fires a
         false collapse on every name every week. Silent until the same expiry
         has history, which is the honest state for a table created today. */
      const oh = (ohist as Record<string, unknown>[])
        .filter((r) => String(r.ticker) === t)
        .sort((x, y) => String(y.asof).localeCompare(String(x.asof)));
      if (oh.length >= 2) {
        const now0 = oh[0];
        const same = oh.slice(1).filter((r) => String(r.expiry) === String(now0.expiry));
        if (same.length >= 1) {
          const a0 = N(now0.option_oi), b0 = N(same[0].option_oi);
          if (b0 > 0) {
            const ch = (a0 - b0) / b0 * 100;
            if (Math.abs(ch) >= 15) {
              price.push(L(`Open interest at the ${day(String(now0.expiry))} expiry `
                + `${ch > 0 ? 'up' : 'down'} ${Math.abs(ch).toFixed(0)}% since ${ago(String(same[0].asof))}`, 'NEW'));
            }
          }
        }
        // Volume is a daily flow, so it needs an average, and an average needs
        // observations. Three same-expiry days is the floor for saying anything.
        if (same.length >= 3) {
          const vs = same.map((r) => N(r.option_vol)).filter((x) => x > 0);
          const avg = vs.reduce((s2, x) => s2 + x, 0) / (vs.length || 1);
          const v0 = N(now0.option_vol);
          if (avg > 0 && v0 >= avg * 2) {
            price.push(L(`Option volume ${(v0 / avg).toFixed(1)}x its recent average today`,
              'NEW', v0 >= avg * 3 ? 'IMPORTANT' : null));
          }
        }
      }

      // ── COMPANY ───────────────────────────────────────────────────────────
      const company: Line[] = [];
      if (g0) {
        const gd = String(g0.direction), gdt = String(g0.date).slice(0, 10);
        const gw = gd === 'cut' ? 'cut' : gd === 'raised' ? 'raised'
                 : gd === 'reaffirmed' ? 'reaffirmed' : gd === 'initiated' ? 'introduced' : gd;
        company.push(L(`Guidance ${gw} ${ago(gdt)}${g0.fiscal_period ? ` for ${g0.fiscal_period}` : ''}`,
          isNew(gdt), gd === 'cut' ? 'BEARISH' : gd === 'raised' ? 'BULLISH' : null,
          gd === 'cut' || gd === 'raised' ? 'IMPORTANT' : null));
      }
      if (e0) {
        company.push(L(`Earnings ${day(String(e0.report_date))}, `
          + `${daysBetween(today, parseISO(String(e0.report_date)))} days out. `
          + (parseISO(String(e0.report_date)) <= parseISO(nextWrite)
             ? `This week's write carries through the print.`
             : `The ${day(nextWrite)} expiry is clear of it.`)));
      }

      // ── HEADLINES ─────────────────────────────────────────────────────────
      /* Two, with links, and only ones actually about this company. The wire
         tags a Dick's Sporting Goods piece to NKE, and an unfiltered feed is
         how the card turned into a news channel the first time. */
      const coName = (await tickerName(t, pk)).split(/[\s,.]+/)[0] ?? '';
      const mine2 = nw.filter((r) => {
        const ti = String(r.title ?? '').toLowerCase();
        if (!coName) return true;
        return ti.includes(coName.toLowerCase()) || ti.includes(t.toLowerCase());
      });
      const headlines = (mine2.length ? mine2 : []).slice(0, 2).map((r) => ({
        title: String(r.title ?? ''), publisher: String(r.publisher ?? ''),
        url: String(r.url ?? ''), when: ago(String(r.published).slice(0, 10)),
      }));

      const newCount = [...analysts, ...price, ...company].filter((x) => x.tags.includes('NEW')).length;

      /* ── Compatibility for builds ALREADY ON THE PHONE ───────────────────
         ⚠ NEVER REMOVE A FIELD A SHIPPED BUILD READS. Deploying the new shape
         on its own broke the installed app the moment it went live: that
         build's Position struct declares stance/bearish/supportive/catalyst
         NON-OPTIONAL, so JSONDecoder threw keyNotFound and every live card
         vanished. There is one backend and many builds of the client, some of
         them on a phone in Nik's pocket, so responses are ADDITIVE ONLY.

         These four are derived from the tagged lines, cost nothing to keep,
         and come out when no build that reads them is still in use. */
      const allLines = [...analysts, ...price, ...company];
      const bearish = allLines.filter((l) => l.tags.includes('BEARISH')).map((l) => l.text);
      const supportive = allLines.filter((l) => l.tags.includes('BULLISH')).map((l) => l.text);
      const catalyst = [
        ...company.filter((l) => !l.tags.includes('BEARISH') && !l.tags.includes('BULLISH')).map((l) => l.text),
        ...headlines.map((h) => `${h.publisher}: ${h.title}`),
      ];
      const stance = bearish.length > supportive.length + 1 ? 'Bearish'
                   : supportive.length > bearish.length + 1 ? 'Supportive' : 'Balanced';

      return {
        stance, bearish, supportive, catalyst,
        analysts, price, company, headlines,
        // The counter is the whole freshness story now: it says whether to read
        // closely or skip, and it needs no timeline to do it.
        new_count: newCount,
        since: cut,
        stand: [
          `Spot ${spot.toFixed(2)}`,
          `Long ${shares.toLocaleString('en-US')} shares at ${avg.toFixed(2)}`,
          `${usd(premTaken)} premium collected, effective cost ${effective.toFixed(2)}`,
          `All-in basis ${allIn.toFixed(2)} including the floor`,
        ],
        coverage: [
          nCalls >= lots100
            ? `${nCalls} of ${lots100} calls written`
            : `${nCalls} of ${lots100} calls written, ${(shares - nCalls * 100).toLocaleString('en-US')} shares exposed to upside with no premium offset`,
          ...itmCall.map((c) => `${c.n} calls at ${c.k} are ${(spot - c.k).toFixed(2)} in the money, ${(c.n * 100).toLocaleString('en-US')} shares leave ${day(c.e)}`),
        ],
        floor_lines: nFloor ? [
          `${nFloor} puts long at ${fk}, ${((spot - fk) / spot * 100).toFixed(1)}% below spot`,
          `Once this week's ${lots100} short puts are on, exposure is ${(needAfter * 100).toLocaleString('en-US')} shares equivalent and the floor needs ${needAfter}`,
          nFloor < needAfter ? `Gap: ${needAfter - nFloor} puts` : `Fully covered`,
        ] : [`No floor on this position`],
        ticker: t, spot, shares, avg, effective, allIn, next_write: nextWrite,
        background: {
          analysts: tg.length ? {
            actions: a.length, median_target: med, vs_spot: spot ? (med / spot - 1) * 100 : 0,
            low: tg[0], high: tg[tg.length - 1], raises, cuts, ups, downs,
            recent: a.slice(0, 3).map((r) => ({
              firm: r.firm, action: r.rating_action, from: N(r.previous_price_target), to: N(r.price_target),
              days: daysBetween(parseISO(String(r.date)), today),
            })),
          } : null,
          consensus: c0 ? { rating: c0.rating, strong_buy: c0.strong_buy, buy: c0.buy, hold: c0.hold, sell: c0.sell } : null,
          guidance: g0 ? { direction: g0.direction, date: g0.date, period: g0.fiscal_period, days: daysBetween(parseISO(String(g0.date)), today) } : null,
          technical: { ext, m20, m50, m200, from_high: hi52 ? (spot / hi52 - 1) * 100 : 0,
                       persistence: p0 ? N(p0.persistence) : null },
          earnings: e0 ? { date: e0.report_date, when: e0.report_time, days: daysBetween(today, parseISO(String(e0.report_date))), estimated: e0.date_estimated } : null,
          news: nw.map((r) => ({ published: r.published, title: r.title, publisher: r.publisher })),
        },
        covered: { calls: nCalls, of: lots100, puts: nPuts, unwritten: shares - nCalls * 100, next_expiry: nextExp ?? null,
                   itm_calls: itmCall.map((c) => ({ k: c.k, n: c.n, expiry: c.e, in_the_money: spot - c.k })) },
        floor: { contracts: nFloor, strike: fk, expiry: floor.map((l) => l.e).sort()[0] ?? null,
                 below_spot: fk && spot ? (spot - fk) / spot * 100 : null,
                 cost: floorCost, pct_of_premium: premTaken ? floorCost / premTaken * 100 : null,
                 needed_now: need, needed_after_writing: needAfter },
        context: { edge: s0 ? N(s0.edge) : null, straddle_pct: s0 ? N(s0.atm_straddle_pct) : null,
                   pos_52w: s0 ? N(s0.pos_52w) : null, score: s0 ? N(s0.score) : null,
                   premium_taken: premTaken },
        do: doList,
      };
    }));

    /* ── Consume the freshness window, but only after the cards are built ────
       The cutoff advances on the FIRST open of a new day and lands on the
       previous visit day, never on today, so the card reads the same all day
       instead of emptying itself the second time it is opened.

       `peek` exists so a probe can read a card without burning the window.
       Without it, testing this endpoint marks everything as seen and the next
       real open shows nothing. */
    if (!body.peek) {
      const rows = names.map((t) => {
        const r = (seen as Record<string, unknown>[]).find((x) => String(x.ticker) === t);
        const lv = r ? String(r.visit_on ?? '').slice(0, 10) : '';
        return {
          ticker: t,
          visit_on: todayISO,
          since_on: !r ? null : (lv && lv < todayISO ? lv : (r.since_on ?? null)),
          updated_at: new Date().toISOString(),
        };
      });
      await D.upsert('income_card_seen', rows, 'ticker');
    }
    return json(200, { ok: true, build: BUILD, asof: todayISO, positions: out });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
