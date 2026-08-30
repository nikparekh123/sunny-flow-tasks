/**
 * new-page — everything the New page renders. handoff/NEW-PAGE.md.
 *
 * ⚠ SECTIONS ARE SPEEDS, NEVER TICKERS, AND THE PAGE RUNS ON TWO CLOCKS.
 * News is daily (~22 items a week), analyst actions are weekly (~10), earnings
 * and guidance are quarterly. Sorting by name gave every section eight of
 * everything and turned a quiet week into forty cells.
 *
 * ⚠ EVERY EMPTY SECTION STATES ITS LAST DATE. An empty section with no
 * last-seen date is indistinguishable from a broken feed, so every count is
 * returned including 0, and every section carries `last`.
 *
 * ⚠ THE DRIFT IS THE FLOOR. It is the one block that is never empty, which is
 * why a dead week still has a page. Nothing else may be padded to fill space.
 */
import { corsHeaders, json, db, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-29.1';
const N = (v: unknown) => (v === null || v === undefined || v === '' ? 0 : Number(v));
/* PostgREST caps every response at 1000 rows and `limit` cannot lift it. The
   first build asked for every analyst action and got the newest 1000 across the
   whole universe, which made BABA's drift read 4 target actions against a true
   109 and dropped seven names out of the median target card. A truncated list
   looks exactly like a short list. */
async function page(D: { get: (p: string) => Promise<Record<string, unknown>[]> }, path: string) {
  const out: Record<string, unknown>[] = [];
  for (let off = 0; off < 20_000; off += 1000) {
    const r = await D.get(`${path}&limit=1000&offset=${off}`);
    out.push(...r);
    if (r.length < 1000) break;
  }
  return out;
}

const day = (a: string, b: string) =>
  Math.round((Date.parse(a + 'T00:00:00Z') - Date.parse(b + 'T00:00:00Z')) / 86_400_000);

/* ── the news filter ──────────────────────────────────────────────────────
   ⚠ EVERY HELD-BACK ROW NAMES ITS REASON, and every reason is literally true
   of the string. A gate that does not count itself looks broken; one that does
   not say why is a second silent gate.

   Measured over the last month: 45% of items name the company in their own
   title. The rest are aggregator listicles that merely mention it. */
const LISTICLE = /^(\d+|one|two|three|four|five|prediction:|here'?s)\b/i;
const WRAP = /(stock market|midday|market close|markets? (muted|open|slip|rally))/i;

/** The company's own name, from the full name Polygon gives us. */
function firstWord(name: string, ticker: string): string[] {
  const stop = /\b(inc|corp|corporation|co|ltd|limited|group|holding|holdings|plc|the|company|services|international|nv|sa|ag)\b\.?/gi;
  const core = name.replace(stop, ' ').replace(/[,.]/g, ' ').trim();
  const words = core.split(/\s+/).filter((w) => w.length > 2);
  return [ticker, ...(words.length ? [words[0]] : [])];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const today = nyToday();
    const ago = (d: number) => new Date(Date.parse(today + 'T00:00:00Z') - d * 86_400_000)
      .toISOString().slice(0, 10);

    const [lots, quotes, news, acts, insights, earn, guide, closes, legs, book] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker'),
      D.get('ticker_quotes_latest?select=ticker,spot,day_change_pct'),
      D.get(`name_news?published=gte.${ago(8)}&select=ticker,id,published,title,publisher,url`
        + '&order=published.desc'),
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker')
        .then((l) => page(D, 'analyst_actions?select=*&order=date.desc&ticker=in.('
          + [...new Set(l.map((r) => String(r.ticker)))].join(',') + ')')),
      D.get('analyst_insights?select=*&order=date.desc'),
      D.get(`earnings_events?report_date=gte.${today}`
        + '&select=ticker,report_date,report_time,date_estimated,source&order=report_date.asc'),
      D.get('guidance_events?select=*&order=date.desc'),
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker')
        .then((l) => page(D, 'daily_closes?select=ticker,date,close_price&order=date.asc'
          + `&date=gte.${ago(320)}&ticker=in.(`
          + [...new Set(l.map((r) => String(r.ticker)))].join(',') + ')')),
      D.get(`option_trades?voided_at=is.null&expiry=gte.${today}`
        + '&select=ticker,option_type,direction,action,contracts,strike,expiry'),
      D.get('ticker_names?select=ticker,name'),
    ]);

    const held = [...new Set(lots.map((r: Record<string, unknown>) => String(r.ticker)))].sort();
    const heldSet = new Set(held);
    const spotBy = new Map<string, number>();
    for (const q of quotes) if (N(q.spot) > 0) spotBy.set(String(q.ticker), N(q.spot));
    const nameBy = new Map<string, string>();
    /* ⚠ `analyst_actions` HAS NO company_name and the scanner universe does not
       cover the held book, so the news filter had nothing to match on and every
       Netflix story fell through to "does not name the company".
       earnings_events carries a name per ticker. */
    for (const u of book) nameBy.set(String(u.ticker), String(u.name));
    /* ⚠ FILL THE CACHE FOR ANYTHING MISSING, ONCE. Nothing else in the schema
       carries a company name for the held book — positions.name echoes the
       ticker, earnings_events.company_name is null for all nine — and without
       one the news filter cannot answer its own keep question. */
    /* ⚠ POLYGON'S OWN CASING IS WRONG ON ONE NAME and Nik has already had it
       corrected once on the page heading: it returns "NetFlix Inc". sunny-rail
       carries the same fix. Two sources for one string is how they drift, so
       the correction is applied on the way IN to the cache, not per reader. */
    const NAME_FIX = new Map([['NFLX', 'Netflix, Inc.']]);
    /* Names are resolved for the held book AND for any other ticker the news
       set mentions, because "about LULU" should read "about lululemon". */
    const cast = [...new Set([...held, ...news.map((n: Record<string, unknown>) => String(n.ticker))])];
    const missing = cast.filter((t) => !nameBy.has(t));
    if (missing.length) {
      const pk = Deno.env.get('POLYGON_API_KEY') ?? '';
      const found: { ticker: string; name: string }[] = [];
      for (const t of missing) {
        try {
          const r = await fetch(`https://api.polygon.io/v3/reference/tickers/${t}?apiKey=${pk}`);
          if (!r.ok) continue;
          const nm = NAME_FIX.get(t)
            ?? String((await r.json())?.results?.name ?? '').trim();
          if (nm) { nameBy.set(t, nm); found.push({ ticker: t, name: nm }); }
        } catch { /* a missing name must not fail the page */ }
      }
      if (found.length) await D.upsert('ticker_names', found, 'ticker');
    }

    /* ── the name's own state, computed live ──────────────────────────────
       ⚠ NOT FROM `ticker_signals`. That table was last written 8 Jul 2026 and
       holds the SCANNER universe, not the book: of nine held names it carries
       two, both stale (NKE 42.89 against a live 38.48). The three facts the
       lead's state row needs are cheap to derive, so they are derived. */
    const closeBy = new Map<string, number[]>();
    for (const c of closes) {
      const t = String(c.ticker);
      if (!closeBy.has(t)) closeBy.set(t, []);
      closeBy.get(t)!.push(N(c.close_price));
    }
    function state(t: string) {
      const spot = spotBy.get(t) ?? 0;
      const px = closeBy.get(t) ?? [];
      if (!(spot > 0)) return null;
      const ma200 = px.length >= 200
        ? px.slice(-200).reduce((s, x) => s + x, 0) / 200 : null;
      /* Wilder's RSI over 14, on the closes we hold. */
      let rsi: number | null = null;
      if (px.length >= 15) {
        const w = px.slice(-15);
        let up = 0, dn = 0;
        for (let i = 1; i < w.length; i++) {
          const d = w[i] - w[i - 1];
          if (d > 0) up += d; else dn -= d;
        }
        rsi = dn === 0 ? 100 : Math.round(100 - 100 / (1 + (up / 14) / (dn / 14)));
      }
      return {
        spot: Math.round(spot * 100) / 100,
        rsi,
        vs200: ma200 ? Math.round((spot / ma200 - 1) * 1000) / 10 : null,
      };
    }

    /* ── the date row: earnings only, nearest first ───────────────────────
       ⚠ ONE ROW PER NAME. earnings_events holds duplicates — NKE carries both
       24 Sep (confirmed, manual) and 29 Sep (Benzinga's estimate). A CONFIRMED
       date beats an estimated one; then earliest wins. */
    const nextEarn = new Map<string, { date: string; estimated: boolean }>();
    for (const e of earn) {
      const t = String(e.ticker);
      if (!heldSet.has(t)) continue;
      const d = String(e.report_date).slice(0, 10);
      const est = e.date_estimated !== false;
      const cur = nextEarn.get(t);
      if (!cur || (cur.estimated && !est) || (cur.estimated === est && d < cur.date)) {
        nextEarn.set(t, { date: d, estimated: est });
      }
    }
    const dates = [...nextEarn.entries()]
      .map(([ticker, e]) => ({
        ticker, date: e.date, estimated: e.estimated,
        days: day(e.date, today), label: `${ticker} reports`,
      }))
      .sort((a, b) => a.days - b.days);

    /* ── news ─────────────────────────────────────────────────────────────
       ⚠ DEDUPE ON URL. One article files under several tickers at the same
       timestamp, and a book-wide section shows it twice without this. The
       second filing is also what makes the "about another company" test exact
       rather than a guess. */
    const byUrl = new Map<string, string[]>();
    for (const n of news) {
      const u = String(n.url ?? n.id);
      if (!byUrl.has(u)) byUrl.set(u, []);
      byUrl.get(u)!.push(String(n.ticker));
    }
    type NewsRow = {
      ticker: string; title: string; url: string; publisher: string; published: string;
      keep: boolean; reason: string | null; kind: 'press release' | 'article';
    };
    const seen = new Set<string>();
    const rows: NewsRow[] = [];
    for (const n of news) {
      const t = String(n.ticker);
      if (!heldSet.has(t)) continue;
      const url = String(n.url ?? n.id);
      const title = String(n.title ?? '');
      const pub = String(n.publisher ?? '');
      /* Keep the filing whose own name is in the title, so the deduped row is
         the one the article is actually about. */
      const mine = firstWord(nameBy.get(t) ?? t, t);
      const lower = title.toLowerCase();
      const names = mine.some((w) => lower.includes(w.toLowerCase()));
      const key = url + (names ? '' : '|' + t);
      if (seen.has(url)) continue;
      if (names) seen.add(url);
      else if (seen.has(key)) continue; else seen.add(key);

      let keep = false, reason: string | null = null;
      if (names) keep = true;
      else {
        /* ⚠ THE SUBJECT IS FOUND BY NAME, NOT GUESSED. Every company we hold
           an earnings date for gives us its own name, so a title naming one of
           them and not this holding is about that one — and the reason printed
           is that company's actual name. The same-url case (one article filed
           under NKE and LULU at one timestamp) is the exact version of this and
           is checked first. */
        const others = (byUrl.get(url) ?? []).filter((x) => x !== t);
        const co = (o: string) => firstWord(nameBy.get(o) ?? o, o)[1] ?? o;
        const filed = others.find((o) =>
          firstWord(nameBy.get(o) ?? o, o).some((x) => lower.includes(x.toLowerCase())));
        const named = filed ?? [...nameBy.keys()].find((o) => {
          if (o === t) return false;
          const w = co(o);
          return w.length >= 4 && new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i').test(title);
        });
        if (named) reason = `about ${co(named)}`;
        else if (LISTICLE.test(title)) reason = 'opens with a number';
        else if (WRAP.test(title)) reason = 'a market wrap';
        else reason = 'does not name the company';
      }
      rows.push({
        ticker: t, title, url, publisher: pub, published: String(n.published),
        keep, reason,
        kind: /globenewswire|business ?wire|pr ?newswire|accesswire/i.test(pub)
          ? 'press release' : 'article',
      });
    }
    const kept = rows.filter((r) => r.keep);
    const hours = (iso: string) =>
      Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 3_600_000));

    /* ⚠ ON-TOPIC FIRST, THEN NEWEST. FULL STOP.
       An earlier pass ranked a same-day press release above an article, on the
       sheet's rule that a press release outranks one — 19% of the feed and
       close to 100% on topic. Nik saw the result and cut it: the lead became a
       securities-fraud class-action notice, which is material but is not what
       the day was about. The KIND is still printed, so a press release still
       announces itself; it just does not jump the queue.
       The filter remains the section's whole point, so an off-topic listicle
       can never lead however fresh it is. */
    const leadRank = (r: NewsRow) => hours(r.published);
    const ordered = [...kept].sort((a, b) => leadRank(a) - leadRank(b));
    const lead = ordered[0] ?? null;
    const links = ordered.slice(1, 3);
    const dropped = rows.filter((r) => !r.keep);

    /* ── analysts, this week ──────────────────────────────────────────────
       ⚠ THREE CARDS, NEWEST FIRST, THE REST IN A LIST. Not the importance
       flag: it is a 0–5 scale and last week ran four 5s and three 4s, which
       selects seven of seven. A restatement is still an action and is printed,
       not suppressed — five of last week's ten were restatements, and hiding
       them makes the section look quieter than the feed is. */
    const week = acts.filter((a: Record<string, unknown>) =>
      heldSet.has(String(a.ticker)) && String(a.date) >= ago(7));
    const insightBy = new Map<string, Record<string, unknown>>();
    for (const i of insights) {
      const k = String(i.benzinga_rating_id ?? '');
      if (k && !insightBy.has(k)) insightBy.set(k, i);
    }
    /* ⚠ THE TEXT OPENS WITH A RESTATEMENT of the rating — "RBC Capital
       reiterated their Sector Perform rating on Nike's stock with a price
       target of $45.00" — which is the row directly above it on the card. So
       the first BULLET is taken, minus its bold header, and never the first
       sentence. Selection, not truncation. */
    function pickInsight(raw: string): string | null {
      for (const line of raw.split('\n')) {
        const m = line.match(/\*\*(.+?)\*\*\s*:?\s*(.+)/);
        if (m && m[2].trim().length > 40) {
          let s = m[2].trim();
          if (s.length > 240) {
            const cut = s.lastIndexOf('. ', 240);
            s = cut > 80 ? s.slice(0, cut + 1) : s.slice(0, 240).replace(/\s+\S*$/, '') + '…';
          }
          return s;
        }
      }
      return null;
    }
    const actionRow = (a: Record<string, unknown>) => {
      const prev = N(a.previous_price_target), now = N(a.price_target);
      const act = String(a.rating_action ?? '');
      return {
        ticker: String(a.ticker),
        date: String(a.date),
        /* ⚠ THE STATE IS A WORD AND IT TAKES NO DIRECTION INK. Red is loss in
           this deck; a downgrade is an opinion. */
        state: act === 'downgrades' ? 'downgraded'
          : act === 'upgrades' ? 'upgraded'
          : now > prev ? 'target raised' : now < prev ? 'target cut' : 'held',
        prev: prev || null,
        now: now || null,
        rating: String(a.rating ?? ''),
        previousRating: String(a.previous_rating ?? ''),
        action: act,
        firm: String(a.firm ?? ''),
        analyst: a.analyst ? String(a.analyst) : null,
        /* The vendor's own flag, 0–5. It is the one thing here worth a colour. */
        importance: N(a.importance),
      };
    };
    /* ⚠ ONE CARD PER NAME, MAX THREE. The section answers "who moved", so a
       name twice is a name too many. Under the old newest-three rule the week
       FIS ran three actions including a Wells Fargo downgrade put NKE on two
       cards and FIS on none: the busiest name got the quietest treatment.
       Now each name fields ONE action and the three newest of those are the
       cards. A name's second action is a list row like any other, which is
       also where an insight goes if it did not land on the chosen action. */
    const heft = (a: Record<string, unknown>) => {
      const act = String(a.rating_action ?? '');
      if (act === 'downgrades' || act === 'upgrades') return 2;
      return N(a.price_target) !== N(a.previous_price_target) ? 1 : 0;
    };
    /* Newest wins the name; a tie inside one day goes to the heavier action,
       so a rating change beats a target nudge beats a restatement. */
    const perName = new Map<string, Record<string, unknown>>();
    for (const a of week) {
      const cur = perName.get(String(a.ticker));
      if (!cur || String(a.date) > String(cur.date)
        || (String(a.date) === String(cur.date) && heft(a) > heft(cur))) {
        perName.set(String(a.ticker), a);
      }
    }
    const carded = [...perName.values()]
      .sort((x, y) => String(y.date).localeCompare(String(x.date)) || heft(y) - heft(x))
      .slice(0, 3);
    const cardIds = new Set(carded.map((a) => String(a.benzinga_id)));
    const cards = carded.map((a: Record<string, unknown>) => {
      const ins = insightBy.get(String(a.benzinga_id));
      const text = ins ? pickInsight(String(ins.insight ?? '')) : null;
      return {
        ...actionRow(a),
        insight: text ? { text, firm: String(ins!.firm ?? '') } : null,
      };
    });
    const rest = week.filter((a: Record<string, unknown>) =>
      !cardIds.has(String(a.benzinga_id))).map(actionRow);
    const lastAction = acts.find((a: Record<string, unknown>) => heldSet.has(String(a.ticker)));

    /* ── median target, 90 days ───────────────────────────────────────────
       ⚠ A MEDIAN OF ACTIONS ACTUALLY SET, never a consensus endpoint. The
       window is short enough that it cannot straddle a split — the consensus
       feed pools across NFLX's Nov 2025 10:1 and reports a $1.22 low against an
       $80 spot. And no row for an unrated instrument: TLT is a fund. */
    const targets = held.map((t) => {
      const tg = acts
        .filter((a: Record<string, unknown>) =>
          String(a.ticker) === t && String(a.date) >= ago(90) && N(a.price_target) > 0)
        .map((a: Record<string, unknown>) => N(a.price_target))
        .sort((x: number, y: number) => x - y);
      if (!tg.length) return null;
      const med = tg[Math.floor(tg.length / 2)];
      const spot = spotBy.get(t) ?? 0;
      return {
        ticker: t, target: Math.round(med * 100) / 100, n: tg.length,
        spot: Math.round(spot * 100) / 100,
        upside: spot > 0 ? Math.round((med / spot - 1) * 1000) / 10 : null,
      };
    }).filter(Boolean).sort((a, b) => (b!.upside ?? 0) - (a!.upside ?? 0));

    /* ── earnings & guidance: conditions, not answers ─────────────────────
       ⚠ THE COLLISION TEST IS DIRECTION-AWARE. Earnings inside a SHORT put's
       life is exposure; inside a BOUGHT put's life the cover is doing its job.
       The same date is red on one and grey on the other. */
    const netLeg = new Map<string, { short: boolean; type: string; expiry: string; n: number }>();
    for (const t of legs) {
      const k = `${t.ticker}|${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}`
        + `|${t.direction}`;
      const e = netLeg.get(k) ?? {
        short: String(t.direction) === 'short', type: String(t.option_type),
        expiry: String(t.expiry).slice(0, 10), n: 0,
      };
      e.n += (t.action === 'open' ? 1 : -1) * N(t.contracts);
      netLeg.set(k, e);
    }
    const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    /* A support line is prose, so its date is written the way a person writes
       one. The ISO form belongs in the payload's own fields, never in a
       sentence. */
    const said = (iso: string) => {
      const p = iso.split('-');
      return p.length === 3 ? `${Number(p[2])} ${MON[Number(p[1]) - 1]}` : iso;
    };
    /* ⚠ A HORIZON, NOT A COUNT. The first build showed four dates because I
       capped it at four, so the seam always read `4` however the calendar
       moved and the four beyond the cut were invisible rather than distant.
       Sixty days is the cut now: inside it a report is something to hold a
       position against, past it there is nothing to do yet. Today the two
       rules agree at four names; in November they will not. */
    const earnRows = dates.filter((d) => d.days <= 60).map((d) => {
      const open = [...netLeg.entries()]
        .filter(([k, v]) => k.startsWith(d.ticker + '|') && v.n > 0.0001 && v.expiry >= d.date);
      const shortAfter = open.find(([, v]) => v.short);
      const longAfter = open.find(([, v]) => !v.short);
      const support = shortAfter
        ? { text: `Inside the ${shortAfter[1].type} you sold, ${said(shortAfter[1].expiry)}`, red: true }
        : longAfter
        ? { text: `Inside the ${longAfter[1].type} you bought, ${said(longAfter[1].expiry)} — covered`,
            red: false }
        : null;
      return {
        kind: 'earnings' as const, ticker: d.ticker,
        line: `Reports ${d.date}`, days: d.days, estimated: d.estimated, support,
      };
    });
    const gRows = held.map((t) => {
      const g = guide.find((x: Record<string, unknown>) => String(x.ticker) === t);
      if (!g) return null;
      const lo = N(g.min_revenue_guidance), hi = N(g.max_revenue_guidance);
      if (!(lo > 0 || hi > 0)) return null;
      return {
        kind: 'guidance' as const, ticker: t,
        period: `${g.fiscal_period ?? ''} FY${g.fiscal_year ?? ''}`.trim(),
        lo, hi, method: String(g.revenue_method ?? 'gaap').toUpperCase(),
        date: String(g.date).slice(0, 10),
        notes: g.notes ? String(g.notes) : null,
        eps: N(g.min_eps_guidance) > 0 || N(g.max_eps_guidance) > 0,
      };
    }).filter(Boolean).sort((a, b) => (b!.date < a!.date ? -1 : 1)).slice(0, 2);

    /* ── the drift: the never-empty floor ─────────────────────────────────
       ⚠ EVERY NAME, RANKED BY CUT SHARE, and the sentence goes to the widest
       spread. The first build showed the two names with the most ACTIONS,
       which is not a ranking at all: NFLX and NKE are the best-covered names
       in the book, so they won every day and the other six were never seen.
       Cut share is the thing the section is actually about, so it sorts, and
       nothing is cut off. The bar is a SHARE OF ACTIONS, never a price, and it
       is --ink: 185 lowers is a fact about analysts, not a loss in the book. */
    const driftAll = held.map((t) => {
      const a = acts.filter((x: Record<string, unknown>) =>
        String(x.ticker) === t && ['lowers', 'raises'].includes(String(x.price_target_action)));
      const cuts = a.filter((x: Record<string, unknown>) =>
        String(x.price_target_action) === 'lowers').length;
      if (!a.length) return null;
      const years = new Map<string, number[]>();
      for (const x of acts) {
        if (String(x.ticker) !== t || !(N(x.price_target) > 0)) continue;
        const y = String(x.date).slice(0, 4);
        if (!years.has(y)) years.set(y, []);
        years.get(y)!.push(N(x.price_target));
      }
      const medians = [...years.entries()].sort()
        .map(([y, v]) => ({ year: y, median: v.sort((p, q) => p - q)[Math.floor(v.length / 2)] }));
      return {
        ticker: t, actions: a.length, cuts, raises: a.length - cuts,
        pct: Math.round(cuts / a.length * 100),
        since: String(acts.filter((x: Record<string, unknown>) =>
          String(x.ticker) === t).slice(-1)[0]?.date ?? '').slice(0, 7),
        medians,
      };
    }).filter(Boolean);
    const blocks = [...driftAll].sort((a, b) => b!.pct - a!.pct);
    const sentenceOn = blocks.length
      ? [...blocks].sort((a, b) => Math.abs(b!.pct - 50) - Math.abs(a!.pct - 50))[0]!.ticker
      : null;

    return json(200, {
      ok: true, build: BUILD, date: today,
      dates,
      news: {
        lead: lead && {
          ...lead, hours: hours(lead.published), state: state(lead.ticker),
        },
        links: links.map((l) => ({ ...l, hours: hours(l.published) })),
        filtered: {
          count: dropped.length,
          rows: dropped.map((d) => ({
            ticker: d.ticker, title: d.title, publisher: d.publisher,
            url: d.url, reason: d.reason,
          })),
        },
        kept: kept.length,
        last: news.length ? String(news[0].published).slice(0, 10) : null,
      },
      analysts: {
        count: week.length, cards, rest,
        last: lastAction ? String(lastAction.date) : null,
        lastFirm: lastAction ? String(lastAction.firm) : null,
        lastTicker: lastAction ? String(lastAction.ticker) : null,
      },
      targets: { window: 90, covered: targets.length, of: held.length, rows: targets },
      earnings: { count: earnRows.length + gRows.length, rows: [...earnRows, ...gRows] },
      drift: { blocks, sentenceOn, names: driftAll.length },
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
