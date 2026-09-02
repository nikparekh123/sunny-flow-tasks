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

    /* ⚠ THE UNIVERSE IS SHARES **OR** AN OPEN OPTION LEG, and it used to be
       shares alone. The day the share block was sold and replaced by long
       calls, five names — NKE, NFLX, BABA, FIS, PEP — vanished from every
       screen at once: no ticker in the universe means no page, no analyst
       actions, no closes and no news filter subject.

       Legs are NETTED on their contract key before a name counts. A raw
       `expiry >= today` scan counts a position that was opened and bought
       back in the same week, which is how a flat account reports positions. */
    const [lotRows, legRows] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker'),
      D.get(`option_trades?voided_at=is.null&expiry=gte.${today}`
        + '&select=ticker,option_type,direction,strike,expiry,action,contracts'),
    ]);
    const legNet = new Map<string, number>();
    for (const t of legRows) {
      const k = `${t.ticker}|${t.option_type}|${t.direction}|${N(t.strike)}`
        + `|${String(t.expiry).slice(0, 10)}`;
      legNet.set(k, (legNet.get(k) ?? 0)
        + (String(t.action) === 'open' ? 1 : -1) * N(t.contracts));
    }
    const universe = [...new Set([
      ...lotRows.map((r: Record<string, unknown>) => String(r.ticker)),
      ...[...legNet.entries()].filter(([, v]) => v > 0.0001).map(([k]) => k.split('|')[0]),
    ])].sort();
    const inList = universe.join(',');

    const [lots, quotes, news, acts, insights, earn, guide, closes, legs, book] = await Promise.all([
      Promise.resolve(lotRows),
      D.get('ticker_quotes_latest?select=ticker,spot,day_change_pct'),
      D.get(`name_news?published=gte.${ago(8)}&select=ticker,id,published,title,publisher,url`
        + '&order=published.desc'),
      page(D, `analyst_actions?select=*&order=date.desc&ticker=in.(${inList})`),
      D.get('analyst_insights?select=*&order=date.desc'),
      D.get(`earnings_events?report_date=gte.${today}`
        + '&select=ticker,report_date,report_time,date_estimated,source&order=report_date.asc'),
      D.get('guidance_events?select=*&order=date.desc'),
      page(D, 'daily_closes?select=ticker,date,close_price&order=date.asc'
        + `&date=gte.${ago(320)}&ticker=in.(${inList})`),
      D.get(`option_trades?voided_at=is.null&expiry=gte.${today}`
        + '&select=ticker,option_type,direction,action,contracts,strike,expiry'),
      D.get('ticker_names?select=ticker,name'),
    ]);

    const held = universe;
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
    /* Advertisements for legal services, and auto-generated price recaps.
       Measured against a real week: 9 and 4 of 46, with no false positives. */
    const SOLICIT =
      /class action|lead plaintiff|deadline alert|investor alert|securities fraud|encourages .{0,60}investors|urged to contact|shareholders who lost|investigation on behalf|rights firm|trial attorneys|law offices|\bLLP\b|\bLLC\b/i;
    const RECAP =
      /(dipped|falls?|fell|rises?|suffers|gains?) .{0,40}(than|amid) .{0,30}(market|broader)|what investors need to know|key insights|market size & share/i;

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
      /* ⚠ NAMING THE COMPANY IS NOT ENOUGH, and that was the whole hole. A law
         firm trawling for plaintiffs names it harder than any reporter does,
         so `ROSEN, A TRUSTED INVESTOR RIGHTS FIRM, Encourages Alibaba Group
         Holding Limited Investors to Secure Counsel` sailed through the names
         test and LED THE PAGE for days. Nine of forty-six items in a week were
         this, every one on BABA, every one through GlobeNewswire. They are
         advertisements for legal services that happen to carry a ticker.

         The recap rule catches the other template: Zacks publishes a price
         recap the day a name moves, which restates the chart and nothing else.
         `Why Lennar (LEN) Dipped More Than Broader Market Today` is the shape.

         Both are DROPPED WITH A REASON rather than hidden, so the filtered
         count still owns them and you can open the list and disagree. */
      if (SOLICIT.test(title)) { reason = 'a law firm soliciting plaintiffs'; }
      else if (RECAP.test(title)) { reason = 'an automated price recap'; }
      else if (names) keep = true;
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
      /* ⚠ THE NOTE MAY COME FROM THE NAME'S OTHER ACTION OF THE WEEK. One
         card per name means the week's single insight usually lands on the
         action that did not win the card: RBC's Nike note sat on a
         restatement while Truist's downgrade took the card, and the note
         vanished from the page. It is the only writing in the whole feed
         better than a headline, so it stays with the NAME. What makes that
         honest rather than a misattribution is the byline the card already
         prints under it, `RBC Capital's note`, naming a firm that is not the
         one in the header. The borrowed action also keeps its own list row,
         so the count still adds up. */
      const own = insightBy.get(String(a.benzinga_id));
      const alt = own ? undefined : week.find((x: Record<string, unknown>) =>
        String(x.ticker) === String(a.ticker) && insightBy.has(String(x.benzinga_id)));
      const ins = own ?? (alt ? insightBy.get(String(alt.benzinga_id)) : undefined);
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
      /* ⚠ THE SPREAD AND THE BELOW-SPOT COUNT, because a median alone hides
         both the disagreement and the dissent. NKE's median of 47 is one
         number over a 23-to-75 range: nobody agrees. AIG's 88 sits in an
         80-to-98 range: everybody does. And LEN has SEVEN of ten analysts
         below the price, which no median can show and which is the opposite
         story to BABA's four of four above it.

         This replaces the drift card, which counted how often analysts cut.
         That number turned out to be the price chart told twice — over the
         same two quarters the target walk tracked the price walk inside five
         points on every one of the eight names — so it read as a wall of bad
         news carrying no information. Where the targets SIT is two-sided by
         construction and is the thing you look at before picking a strike. */
      return {
        ticker: t, target: Math.round(med * 100) / 100, n: tg.length,
        spot: Math.round(spot * 100) / 100,
        upside: spot > 0 ? Math.round((med / spot - 1) * 1000) / 10 : null,
        lo: Math.round(tg[0] * 100) / 100,
        hi: Math.round(tg[tg.length - 1] * 100) / 100,
        below: spot > 0 ? tg.filter((v: number) => v < spot).length : 0,
      };
    }).filter(Boolean).sort((a, b) => (b!.upside ?? 0) - (a!.upside ?? 0));

    /* Hoisted above the room, which labels its snapshots with it. */
    const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    /* ── the room ─────────────────────────────────────────────────────────
       ⚠ ONE DOT PER FIRM, NOT PER PUBLICATION. The card is a roster of
       analysts whose stance changes over time, so the dot has to BE an
       analyst. Counting publications in a trailing 90 days counts neither:
       a name goes quiet after earnings and half the room vanishes — BABA ran
       2, 11, 4, 4 across the four snapshots — and pressing play is then a
       reshuffle rather than a defection.

       A firm is in the room if it set a target inside the year before the
       snapshot, and it brings its most recent one. The roster then holds
       nearly still (BABA 11, 11, 11, 11; NKE 25, 25, 26, 26), so a dot
       changing colour means that firm changed its mind or the price crossed
       its target, which is the thing the card claims to show.

       ⚠ EACH SNAPSHOT USES ITS OWN CLOSE. `4 bearish, under 86` has to mean
       under the price THAT DAY; carrying today's spot backwards would restate
       history against a number that did not exist yet. */
    const ROOM_BACK = [180, 90, 30, 0], ROOM_LOOK = 365;
    const before = (iso: string, d: number) =>
      new Date(Date.parse(iso + 'T00:00:00Z') - d * 86_400_000).toISOString().slice(0, 10);
    const dated = new Map<string, { d: string; p: number }[]>();
    for (const c of closes) {
      const t = String(c.ticker);
      if (!dated.has(t)) dated.set(t, []);
      dated.get(t)!.push({ d: String(c.date).slice(0, 10), p: N(c.close_price) });
    }
    /* Ascending, so the last row at or before the date is that date's close.
       A snapshot landing on a weekend takes the Friday, which is correct. */
    const closeOn = (t: string, on: string) => {
      let px = 0;
      for (const r of dated.get(t) ?? []) { if (r.d <= on) px = r.p; else break; }
      return px;
    };
    const snapLabel = (iso: string) => {
      const p = iso.split('-');
      return `${Number(p[2])} ${MON[Number(p[1]) - 1]}`;
    };
    const room = held.map((t) => {
      /* `acts` is date-descending, so the first row seen for a firm is its
         latest, which is what makes the one-pass map correct. */
      const mine = acts.filter((x: Record<string, unknown>) =>
        String(x.ticker) === t && N(x.price_target) > 0 && x.firm);
      const snaps = ROOM_BACK.map((back) => {
        const on = back === 0 ? today : ago(back);
        const from = before(on, ROOM_LOOK);
        const latest = new Map<string, number>();
        for (const a of mine) {
          const d = String(a.date).slice(0, 10);
          if (d > on || d <= from) continue;
          const f = String(a.firm);
          if (!latest.has(f)) latest.set(f, N(a.price_target));
        }
        const spot = back === 0
          ? (spotBy.get(t) ?? closeOn(t, on)) : closeOn(t, on);
        if (!latest.size || !(spot > 0)) return null;
        const v = [...latest.values()];
        return {
          label: back === 0 ? 'Today' : snapLabel(on), date: on,
          spot: Math.round(spot * 100) / 100,
          bear: v.filter((x) => x < spot).length,
          neu: v.filter((x) => x >= spot && x < spot * 1.2).length,
          bull: v.filter((x) => x >= spot * 1.2).length,
        };
      });
      /* All four snapshots or no row. A row that starts halfway through the
         scrubber would make the chips lie about what they select. */
      if (snaps.some((x) => !x)) return null;
      return { ticker: t, snaps };
    }).filter(Boolean)
      /* The loudest rooms first: most bearish, then the bigger roster, so a
         dissenting voice among twenty-six outranks the same voice among four. */
      .sort((a, b) => {
        const x = a!.snaps[3]!, y = b!.snaps[3]!;
        return y.bear - x.bear
          || (y.bear + y.neu + y.bull) - (x.bear + x.neu + x.bull)
          || a!.ticker.localeCompare(b!.ticker);
      });

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

    /* ── the drift: the turn, not the level ──────────────────────────────
       ⚠ THREE TWELVE-MONTH BLOCKS AND THE TURN BETWEEN THE ENDS. A single
       blended cut share was the price chart told twice: over any one window
       the target walk tracks the price walk inside five points on every name,
       so the number carried no information and read as a wall of bad news.

       The TURN survives that test, because it separates two things a price
       cannot. NFLX cut 5% of the time a year ago and 82% since: a regime
       break inside one year. NKE fell just as hard this past year and its
       share moved five points, because it was already at 85% two years ago.
       Newly out of favour and chronically out of favour look identical on a
       chart and are opposite situations to sell calls into.

       Rolling twelve-month blocks, not calendar years — the feed starts in
       Aug 2023, so a calendar 2023 column would be four months wearing a
       year's label. No split adjustment is needed anywhere here: `adjusts` is
       neither a `lowers` nor a `raises`, so NFLX's ten-for-one never entered
       a count. */
    /* ⚠ THE THRESHOLD LIVES ON THE CLIENT, so raw counts ship. The card draws
       a dotted bridge and a dashed hollow ring where a thin block would have
       been, which it can only do if it knows the block exists and is thin.
       A null pct with a real n is that fact; a silently dropped point is not. */
    const DRIFT_SPAN = 365, DRIFT_MIN = 12;
    const driftAll = held.map((t) => {
      const mine = acts.filter((x: Record<string, unknown>) =>
        String(x.ticker) === t
        && ['lowers', 'raises'].includes(String(x.price_target_action)));
      /* Oldest first, so the row reads left to right as time. */
      const years = [2, 1, 0].map((i) => {
        const from = ago(DRIFT_SPAN * (i + 1)), to = ago(DRIFT_SPAN * i);
        const v = mine.filter((x: Record<string, unknown>) =>
          String(x.date) >= from && (i === 0 || String(x.date) < to));
        const cuts = v.filter((x: Record<string, unknown>) =>
          String(x.price_target_action) === 'lowers').length;
        return {
          pct: v.length >= DRIFT_MIN ? Math.round(cuts / v.length * 100) : null,
          n: v.length,
        };
      });
      const drawn = years.filter((y) => y.pct !== null);
      if (drawn.length < 2) return null;
      return {
        ticker: t,
        v: years.map((y) => y.pct),
        n: years.map((y) => y.n),
        /* Last drawn minus first drawn. A turn across a gap is still a turn;
           what a gap forbids is a POINT, not an arithmetic. */
        turn: drawn[drawn.length - 1]!.pct! - drawn[0]!.pct!,
      };
    }).filter(Boolean);
    /* ⚠ HUE IS ASSIGNED BY RANK, NOT BY TICKER. The sheet's four plum steps are
       `turned toward cuts, by rank`, so the deepest belongs to the biggest turn
       whoever holds it that week. Sorting here is what makes the client's index
       into the ramp correct without the client re-deriving the ranking. */
    const blocks = [...driftAll]
      .sort((a, b) => b!.turn - a!.turn);

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
      room: { snaps: ROOM_BACK.length, covered: room.length, of: held.length, rows: room },
      earnings: { count: earnRows.length + gRows.length, rows: [...earnRows, ...gRows] },
      drift: { span: DRIFT_SPAN, minActions: DRIFT_MIN,
               covered: driftAll.length, of: held.length, rows: blocks },
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
