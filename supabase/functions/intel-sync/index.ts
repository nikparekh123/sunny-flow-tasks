/**
 * intel-sync — Benzinga guidance, analyst actions, consensus and news.
 *
 * Guidance and ratings run over the WHOLE universe, because guidance becomes a
 * gate and the 120-day median target is derived from ratings. Consensus and
 * news are one call per ticker, so they run only for names actually held.
 *
 * ⚠ CONSENSUS IS A PATH PARAMETER, not a query filter.
 *   /benzinga/v1/consensus-ratings/NKE      works
 *   /benzinga/v1/consensus-ratings?ticker=  empty 404, reads as "not entitled"
 * That 404 cost an hour and a wrong conclusion about what the plan carried.
 *
 * ⚠ NEWS is Polygon's own /v2/reference/news, not a Benzinga path. Every
 * /benzinga/v1/news form returns 404; the reference feed carries Benzinga
 * among its publishers.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-25.1';
const POLY = 'https://api.polygon.io';
const CHUNK = 40;
/* 180 days, not 400. The 120-day median target and the 120-day guidance
   lookback are all that read this, and at 400 days a 40-ticker chunk returned
   exactly 1,000 rows fifteen times over: the limit, silently truncating. */
const BACK = 180;

const num = (v: unknown) => (v === null || v === undefined || v === '' ? null : Number(v));

/* Direction, derived from whichever line actually carries numbers.
   NKE reaffirmed on 23 Jun without restating EPS, so the payload reads
   0.00-0.00 against a prior of 0.00-0.00. Compared naively that is a cut. */
function direction(g: Record<string, unknown>): string {
  const mid = (a: number | null, b: number | null) =>
    (a === null && b === null) ? null : ((a ?? b ?? 0) + (b ?? a ?? 0)) / 2;
  const now = mid(num(g.min_eps_guidance), num(g.max_eps_guidance));
  const was = mid(num(g.previous_min_eps_guidance), num(g.previous_max_eps_guidance));
  const rNow = mid(num(g.min_revenue_guidance), num(g.max_revenue_guidance));
  const rWas = mid(num(g.previous_min_revenue_guidance), num(g.previous_max_revenue_guidance));
  const note = String(g.notes ?? '').toLowerCase();
  if (note.includes('reaffirm') || note.includes('maintains guidance')) return 'reaffirmed';
  const pick = (a: number | null, b: number | null) =>
    (a && b && a !== 0 && b !== 0) ? (a > b ? 'raised' : a < b ? 'cut' : 'reaffirmed') : null;
  return pick(now, was) ?? pick(rNow, rWas)
    ?? ((now || rNow) ? 'initiated' : 'unknown');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const pk = Deno.env.get('POLYGON_API_KEY')!;
    let body: { dry_run?: boolean; tickers?: string[]; back_days?: number; page?: number } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* none */ }
    const D = db(url, key);
    const today = parseISO(nyToday());
    /* back_days lets a one-off deep pull reach past the routine 180. The
       depth exists only while the subscription does, so it is worth taking
       once: a guidance cut can only be tested against outcomes if the cuts
       from before this week are on disk. */
    const back = Math.max(1, Number(body.back_days ?? BACK));
    const from = ymd(addDays(today, -back));

    const [uni, sleeve, pos] = await Promise.all([
      D.get('income_scanner_universe?active=is.true&select=ticker'),
      D.get('income_sleeve_names?active=is.true&select=ticker'),
      // qty_remaining > 0, or 'held' picks up every ticker ever owned:
      // FIG, SPCX, HOOD and fifteen others with zero shares.
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker'),
    ]);
    const all = body.tickers ?? [...new Set(uni.map((r) => String(r.ticker)))];
    // Held: one call each, so only names with an actual position or a sleeve row.
    const held = [...new Set([...sleeve.map((r) => String(r.ticker)),
                              ...pos.map((r) => String(r.ticker))])];

    /* Dedupe on the conflict key BEFORE posting. The backwards date slices
       overlap at their boundaries, so the same benzinga_id arrives twice in one
       batch and Postgres rejects the whole command with 21000: "cannot affect
       row a second time". A partial write looks like a rate limit and is not. */
    const post = async (table: string, rows: unknown[], conflict: string) => {
      const keys = conflict.split(',');
      const seen = new Set<string>();
      rows = rows.filter((r) => {
        const k = keys.map((c) => String((r as Record<string, unknown>)[c])).join('|');
        if (seen.has(k)) return false;
        seen.add(k); return true;
      });
      let n = 0, err: string | null = null;
      for (let i = 0; i < rows.length; i += 400) {
        try {
          const r = await fetch(`${url}/rest/v1/${table}?on_conflict=${conflict}`, {
            method: 'POST',
            headers: { apikey: key, Authorization: `Bearer ${key}`,
                       'Content-Type': 'application/json',
                       Prefer: 'resolution=merge-duplicates,return=minimal' },
            body: JSON.stringify(rows.slice(i, i + 400)),
          });
          if (r.ok) n += Math.min(400, rows.length - i);
          else if (!err) err = `${r.status} ${(await r.text()).slice(0, 160)}`;
        } catch (e) { if (!err) err = String(e).slice(0, 120); }
      }
      return { n, err };
    };
    const get = async (u: string) => {
      try { const r = await fetch(u); return r.ok ? ((await r.json())?.results ?? []) : []; }
      catch { return []; }
    };

    // ── guidance + ratings, whole universe ────────────────────────────────
    const gRows: unknown[] = [], aRows: unknown[] = [];
    for (let i = 0; i < all.length; i += CHUNK) {
      const p = all.slice(i, i + CHUNK).join(',');
      /* Walk backwards a slice at a time. A single call caps at 1,000 and
         silently truncates: at 400 days a 40-ticker chunk returned exactly
         1,000 rows fifteen times, which reads as a complete answer. */
      const guides: Record<string, unknown>[] = [];
      for (let d0 = 0; d0 < back; d0 += 120) {
        const lo = ymd(addDays(today, -Math.min(back, d0 + 120)));
        const hi = ymd(addDays(today, -d0));
        guides.push(...await get(`${POLY}/benzinga/v1/guidance?ticker.any_of=${p}`
          + `&date.gte=${lo}&date.lte=${hi}&limit=1000&order=desc&sort=date&apiKey=${pk}`));
      }
      for (const g of guides) {
        gRows.push({
          benzinga_id: String(g.benzinga_id), ticker: String(g.ticker ?? '').toUpperCase(),
          date: String(g.date).slice(0, 10), fiscal_period: g.fiscal_period,
          fiscal_year: num(g.fiscal_year), release_type: g.release_type, importance: num(g.importance),
          min_eps: num(g.min_eps_guidance), max_eps: num(g.max_eps_guidance),
          prev_min_eps: num(g.previous_min_eps_guidance), prev_max_eps: num(g.previous_max_eps_guidance),
          min_rev: num(g.min_revenue_guidance), max_rev: num(g.max_revenue_guidance),
          prev_min_rev: num(g.previous_min_revenue_guidance), prev_max_rev: num(g.previous_max_revenue_guidance),
          direction: direction(g), notes: g.notes ?? null,
        });
      }
      const acts: Record<string, unknown>[] = [];
      for (let d0 = 0; d0 < back; d0 += 45) {
        const lo = ymd(addDays(today, -Math.min(back, d0 + 45)));
        const hi = ymd(addDays(today, -d0));
        acts.push(...await get(`${POLY}/benzinga/v1/ratings?ticker.any_of=${p}`
          + `&date.gte=${lo}&date.lte=${hi}&limit=1000&order=desc&sort=date&apiKey=${pk}`));
      }
      for (const a of acts) {
        aRows.push({
          benzinga_id: String(a.benzinga_id), ticker: String(a.ticker ?? '').toUpperCase(),
          date: String(a.date).slice(0, 10), firm: a.firm ?? null, analyst: a.analyst ?? null,
          rating: a.rating ?? null, previous_rating: a.previous_rating ?? null,
          rating_action: a.rating_action ?? null,
          price_target: num(a.price_target), previous_price_target: num(a.previous_price_target),
          price_target_action: a.price_target_action ?? null, importance: num(a.importance),
        });
      }
    }

    // ── consensus + news, held names only (one call each) ─────────────────
    const cRows: unknown[] = [], nRows: unknown[] = [];
    for (const t of held) {
      for (const c of await get(`${POLY}/benzinga/v1/consensus-ratings/${t}?apiKey=${pk}`)) {
        cRows.push({
          ticker: t, rating: c.consensus_rating ?? null, rating_value: num(c.consensus_rating_value),
          target: num(c.consensus_price_target), high: num(c.high_price_target), low: num(c.low_price_target),
          contributors: num(c.ratings_contributors),
          strong_buy: num(c.strong_buy_ratings), buy: num(c.buy_ratings), hold: num(c.hold_ratings),
          sell: num(c.sell_ratings), strong_sell: num(c.strong_sell_ratings),
          as_of: new Date().toISOString(),
        });
      }
      for (const n of await get(`${POLY}/v2/reference/news?ticker=${t}&limit=20&order=desc&apiKey=${pk}`)) {
        nRows.push({
          id: String(n.id), ticker: t, published: n.published_utc ?? null,
          title: n.title ?? null, publisher: n.publisher?.name ?? null, url: n.article_url ?? null,
        });
      }
    }

    if (body.dry_run) {
      return json(200, { ok: true, build: BUILD, dry_run: true,
        universe: all.length, held,
        guidance: gRows.length, actions: aRows.length, consensus: cRows.length, news: nRows.length,
        sample_guidance: gRows.slice(0, 4), sample_action: aRows.slice(0, 2),
        by_direction: gRows.reduce((m: Record<string, number>, g) => {
          const d = String((g as Record<string, unknown>).direction); m[d] = (m[d] ?? 0) + 1; return m; }, {}) });
    }
    const g = await post('guidance_events', gRows, 'benzinga_id');
    const a = await post('analyst_actions', aRows, 'benzinga_id');
    const c = await post('analyst_consensus', cRows, 'ticker,as_of_date');
    const n = await post('name_news', nRows, 'ticker,id');
    /* ⚠ STAMP THE HEARTBEAT LAST, AFTER THE WRITES, AND ONLY ON THE WAY OUT.
       pg_cron logs "succeeded" the moment net.http_post hands back a request
       id — it never learns whether this function ran, wrote, or threw. Three
       days of green cron rows is what a feed with a hole in it looks like, and
       it is why the analyst hole went unnoticed until Nik spotted the card
       repeating itself.

       So the evidence is a row this function writes about itself. Its AGE is
       the health signal. `rows_written` rides along but must not be an alert on
       its own: analysts are silent at weekends and over holidays, and a feed
       that runs correctly and finds nothing is healthy. */
    const written = (g.n ?? 0) + (a.n ?? 0) + (c.n ?? 0) + (n.n ?? 0);
    await D.upsert('sync_heartbeat', [{
      feed: 'intel-sync',
      ran_at: new Date().toISOString(),
      rows_written: written,
      detail: `guidance ${g.n ?? 0} · actions ${a.n ?? 0} · consensus ${c.n ?? 0} · news ${n.n ?? 0}`,
    }], 'feed');

    return json(200, { ok: true, build: BUILD, universe: all.length, held,
      guidance: g, actions: a, consensus: c, news: n });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
