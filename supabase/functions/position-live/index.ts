/**
 * position-live — what a position you ALREADY HOLD is doing, and what it needs.
 *
 * Not a score. Ranking one position against itself says nothing. Five sections:
 *
 *   BACKGROUND      situational: analysts, guidance, technicals, earnings
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
 * ⚠ THE CONSENSUS TARGET IS NOT USED against spot. That feed aggregates every
 * analyst who ever covered the name: NKE reads 91.56 against a spot of 40.91.
 * The usable number is the rolling 120-day median of analyst_actions, and the
 * count of raises against cuts matters more than either.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday, daysBetween } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-22.5';
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
    const D = db(url, key);
    let body: { tickers?: string[] } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* none */ }
    const today = parseISO(nyToday());
    const todayISO = ymd(today);
    const d120 = ymd(addDays(today, -120));

    const lots = await D.get('share_lots?voided_at=is.null&qty_remaining=gt.0'
      + '&select=ticker,qty_remaining,cost_per_share');
    const names = body.tickers ?? [...new Set(lots.map((r) => String(r.ticker)))];
    if (!names.length) return json(200, { ok: true, empty: true, note: 'no shares held' });
    const inList = `(${names.join(',')})`;

    const [trades, quotes, closes, pers, scan, earn, guide, acts, cons, news] = await Promise.all([
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
      D.get(`name_news?ticker=in.${inList}&select=ticker,published,title,publisher&order=published.desc`),
    ]);

    const first = (a: Record<string, unknown>[], t: string) =>
      a.find((x) => String(x.ticker) === t) as Record<string, unknown> | undefined;
    const out = names.map((t) => {
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

      const need = lots100 + nPuts;
      const needAfter = lots100 * 2;
      /* Sentences, not field-speak. The two paragraphs above read like a
         person and then this said "floor short 20 against 20 shares plus 20
         puts sold", which is the same jargon wearing a bullet. */
      const doList: string[] = [];
      if (nCalls < lots100) {
        doList.push(`Write ${lots100 - nCalls} calls and ${lots100 - nPuts} puts at the money.`);
      }
      for (const c of itmCall) {
        doList.push(`Let the ${c.n} calls at ${c.k} go: ${(c.n * 100).toLocaleString('en-US')} shares `
          + `leave on ${day(c.e)} and ${usd(c.n * 100 * c.k)} comes back.`);
      }
      if (nFloor < need) {
        doList.push(`Buy ${need - nFloor} more floor puts. You hold ${nFloor} against the ${need} your rule asks for.`);
      } else if (nFloor < needAfter) {
        doList.push(`Your floor will be ${needAfter - nFloor} contracts short once this week's puts are on.`);
      }
      if (fk && (spot - fk) / spot > 0.15) {
        doList.push(`Consider rolling the floor up. At ${((spot - fk) / spot * 100).toFixed(0)}% below the price it protects very little.`);
      }
      if (g0 && String(g0.direction) === 'cut' && String(g0.date) >= d120) {
        doList.push(`The company cut guidance on ${day(String(g0.date))}. Think hard before adding to this one.`);
      }

      /* ── The card in English, as paragraphs ──────────────────────────────
         Not a list. An earlier version emitted one sentence per bullet and Nik
         called it "still bullet points": a stack of one-line paragraphs reads
         like a form, not like someone telling you where you are.

         Two blocks, and the split matters. SITUATIONAL is the MARKET's view of
         the company: what analysts are doing, what the company has said, where
         the price sits. POSITION is yours. They were tangled before, with
         holdings sitting under a heading called background.

         Deliberately NOT said: whether anything is written this week. Nik cut
         it. Every Monday the book is empty by construction, so "all 2,000
         shares are sitting idle" is the calendar, not news, and the DO block
         already asks for the trade. */
      const money = (v: number) => usd(Math.abs(v));
      const sit: string[] = [];
      if (p0 || hi52) {
        sit.push(`${t} sits ${Math.abs(hi52 ? (spot / hi52 - 1) * 100 : 0).toFixed(0)}% below its high`
          + (p0 ? ` and has spent ${N(p0.persistence).toFixed(0)}% of the last seven months within 10% of its low` : '')
          + `.`);
      }
      if (m50 && m200) {
        const a50 = spot > m50, a200 = spot > m200;
        sit.push(a50 === a200
          ? `It trades ${a50 ? 'above' : 'below'} both its 50-day and 200-day averages.`
          : `It trades ${a50 ? 'above' : 'below'} its 50-day average but ${a200 ? 'above' : 'below'} its 200-day.`);
      }
      if (tg.length) {
        const bulls = c0 ? N(c0.strong_buy) + N(c0.buy) : 0;
        const r0 = a[0];
        let line = cuts > raises
          ? `The street has cut its price target ${cuts} times in four months and raised it ${raises === 0 ? 'none' : `${raises} times`}`
          : `Targets have moved up ${raises} times against ${cuts} cuts in four months`;
        if (r0 && r0.rating_action === 'downgrades') {
          line += `, with ${r0.firm} downgrading ${daysBetween(parseISO(String(r0.date)), today)} days ago to a target of `
            + `${N(r0.price_target)}${N(r0.price_target) < spot ? `, below where it trades` : ``}`;
        }
        line += bulls ? `, though ${bulls} analysts still call it a buy.` : `.`;
        sit.push(line);
      }
      if (g0) {
        const gd = String(g0.direction);
        const ago = daysBetween(parseISO(String(g0.date)), today);
        sit.push(gd === 'cut'
          ? `The company cut its guidance ${ago} days ago, which is the business itself guiding down.`
          : `The company ${gd} its guidance ${ago} days ago.`);
      }
      if (e0) {
        const dd = daysBetween(today, parseISO(String(e0.report_date)));
        sit.push(`It reports on ${day(String(e0.report_date))}, ${dd} days away.`);
      }

      const pos: string[] = [];
      pos.push(`You own ${shares.toLocaleString('en-US')} shares at an average of ${avg.toFixed(2)}.`);
      pos.push(`Premium has taken that to ${effective.toFixed(2)}, and with the floor ${allIn.toFixed(2)}, `
        + `so the stock is ${Math.abs((spot / allIn - 1) * 100).toFixed(0)}% ${spot >= allIn ? 'above' : 'below'} your all-in cost.`);
      if (itmCall.length) {
        const c = itmCall[0];
        pos.push(`Your ${c.n} calls at ${c.k} are in the money, so ${(c.n * 100).toLocaleString('en-US')} shares `
          + `go on ${day(c.e)} for ${usd(c.n * 100 * c.k)}.`);
      }
      if (nFloor) {
        pos.push(`The floor is ${nFloor} puts at ${fk}, ${((spot - fk) / spot * 100).toFixed(1)}% below the price, `
          + (nFloor >= need
            ? `covering what you hold today but ${Math.round(nFloor / needAfter * 100)}% of what you will be exposed to once this week's puts are on.`
            : `which is ${need - nFloor} short of the ${need} your rule asks for.`));
      } else pos.push(`There is no floor under this position.`);

      return {
        situational: sit.join(' '),
        position: pos.join(' '),
        ticker: t, spot, shares, avg, effective, allIn,
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
    });
    return json(200, { ok: true, build: BUILD, asof: todayISO, positions: out });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
