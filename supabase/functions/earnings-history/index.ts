/**
 * earnings-history — what the tape actually did after each print.
 *
 * We had no historical earnings dates: earnings_events holds a single seeded row.
 * Polygon's financials endpoint carries a filing_date per quarter, which lands on
 * or within a day of the report, and that is close enough to locate the reaction in
 * the daily bars. The reaction itself is then measured from prices, not inferred.
 *
 * For each print: the session that repriced it, the close-to-close move, and where
 * price sat 5, 10 and 30 sessions later. The last part is the whole point — it is
 * what answers "how long does it stay down", which the planner currently guesses at.
 *
 * Peers are stored under their own ticker rather than pooled on write, so NVDA's own
 * record stays separable from the wider semis sample.
 *
 * POST {} — all tickers. POST {"tickers":["NVDA"],"limit":40} to narrow.
 * Env: POLYGON_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 */
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const DEFAULT_TICKERS = ['NVDA', 'AVGO', 'AMD', 'TSM', 'MU'];
const BAND = 8;                      // ±8% decides bad / flat / good

interface Bar { t: number; c: number }

const ymd = (d: Date) => d.toISOString().slice(0, 10);

/** Filing dates stand in for report dates — same day or the next, close enough to
 *  find the reaction in the bars. */
async function filingDates(ticker: string, key: string, limit: number): Promise<string[]> {
  const out: string[] = [];
  try {
    const r = await fetch(`${POLY}/vX/reference/financials?ticker=${ticker}&timeframe=quarterly`
      + `&order=desc&sort=filing_date&limit=${limit}&apiKey=${key}`);
    if (!r.ok) return out;
    const j = await r.json();
    for (const row of (j?.results ?? []) as { filing_date?: string }[]) {
      if (row.filing_date && !out.includes(row.filing_date)) out.push(row.filing_date);
    }
  } catch { /* a ticker with no filings simply contributes nothing */ }
  return out;
}

async function dailyBars(ticker: string, from: string, to: string, key: string): Promise<Bar[]> {
  try {
    const r = await fetch(`${POLY}/v2/aggs/ticker/${ticker}/range/1/day/${from}/${to}`
      + `?adjusted=true&sort=asc&limit=200&apiKey=${key}`);
    if (!r.ok) return [];
    const j = await r.json();
    return ((j?.results ?? []) as Bar[]).filter((b) => Number.isFinite(b.c));
  } catch { return []; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const key = Deno.env.get('POLYGON_API_KEY');
  const supaUrl = Deno.env.get('SUPABASE_URL');
  const supaKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!key || !supaUrl || !supaKey) return json(500, { ok: false, error: 'missing env' });

  const body = await req.json().catch(() => ({})) as { tickers?: string[]; limit?: number; stats?: boolean };

  // ── stats mode ───────────────────────────────────────────────────────────────
  // What the planner actually consumes: per band, the median path after the print.
  // Median rather than mean, because one -30% quarter should not define the rule.
  // NVDA's own record is kept apart from the pooled peers so a keep-percentage
  // driven by a handful of prints never reads like one driven by sixty.
  if (body.stats) {
    const r = await fetch(`${supaUrl}/rest/v1/earnings_reactions`
      + `?select=ticker,band,move_pct,d5_pct,d10_pct,d30_pct&limit=2000`,
      { headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}` } });
    if (!r.ok) return json(200, { ok: false, error: `HTTP${r.status}` });
    const all = (await r.json()) as Record<string, number | string>[];
    const med = (xs: number[]) => {
      if (!xs.length) return null;
      const s2 = xs.slice().sort((a, b) => a - b);
      return +s2[Math.floor(s2.length / 2)].toFixed(2);
    };
    const summarise = (rows: typeof all) => {
      const out: Record<string, unknown> = {};
      for (const band of ['bad', 'flat', 'good']) {
        const g = rows.filter((x) => x.band === band);
        out[band] = {
          n: g.length,
          move: med(g.map((x) => Number(x.move_pct))),
          d5: med(g.map((x) => Number(x.d5_pct))),
          d10: med(g.map((x) => Number(x.d10_pct))),
          d30: med(g.map((x) => Number(x.d30_pct))),
        };
      }
      return out;
    };
    return json(200, {
      ok: true, band: BAND, total: all.length,
      nvda: summarise(all.filter((x) => x.ticker === 'NVDA')),
      peers: summarise(all.filter((x) => x.ticker !== 'NVDA')),
    });
  }
  const tickers = body.tickers?.length ? body.tickers : DEFAULT_TICKERS;
  const limit = Math.min(Math.max(Number(body.limit ?? 40), 1), 100);

  const rows: Record<string, unknown>[] = [];
  const report: Record<string, { prints: number; measured: number; seeded: number }> = {};

  /** Confirmed report dates we already hold. Polygon's financials endpoint only knows a
   *  print once the 10-Q is filed AND indexed, which lags the report by a week or more —
   *  so the newest quarter, the one the planner's peer factor actually cares about, was
   *  invisible. earnings_events has the real dates because they were seeded by hand. */
  async function seededDates(ticker: string): Promise<string[]> {
    try {
      const since = ymd(new Date(Date.now() - 400 * 86400000));
      const r = await fetch(`${supaUrl}/rest/v1/earnings_events?select=report_date&ticker=eq.${ticker}`
        + `&report_date=gte.${since}&report_date=lte.${ymd(new Date())}&order=report_date.desc&limit=12`,
        { headers: { apikey: supaKey!, Authorization: `Bearer ${supaKey}` } });
      if (!r.ok) return [];
      return ((await r.json()) as { report_date: string }[]).map((x) => String(x.report_date).slice(0, 10));
    } catch { return []; }
  }

  for (const ticker of tickers) {
    const [filed, seeded] = await Promise.all([filingDates(ticker, key, limit), seededDates(ticker)]);
    const dates = [...new Set([...seeded, ...filed])];
    report[ticker] = { prints: dates.length, measured: 0, seeded: seeded.length };

    for (const d of dates) {
      const day = new Date(d + 'T00:00:00Z');
      // A window wide enough to hold the session before and 30 sessions after,
      // with slack for weekends and holidays.
      // Reach back before the filing, since the release precedes it, and far enough
      // forward to hold 30 sessions after whatever day turns out to be the reaction.
      const from = ymd(new Date(day.getTime() - 45 * 86400000));
      const to = ymd(new Date(day.getTime() + 70 * 86400000));
      const bars = await dailyBars(ticker, from, to, key);
      // Was 45, which silently skipped the MOST RECENT quarter of every ticker: a
      // print from last week has nowhere near 45 bars behind its filing date. The
      // planner's peer factor cares about exactly those prints, so the floor is now
      // whatever is needed to see the reaction itself.
      if (bars.length < 8) continue;

      // The filing date is NOT the earnings date. A 10-Q lands days or weeks after
      // the release, so anchoring on it measured ordinary sessions: NVDA came back
      // 40 of 40 "flat" with a median move of +0.0%, which is what random days look
      // like on a stock that routinely gaps 8-15% on a print.
      //
      // The reaction is found in the prices instead: within the window, the single
      // largest close-to-close move. On a mega-cap the biggest day of a quarter is
      // almost always the print. Anything under 3% is not a reaction worth calling
      // one, so the quarter is skipped rather than guessed at.
      let i = -1, biggest = 0;
      // Also was `- 30`, for the same reason: it refused to look at any session that
      // did not already have thirty behind it. The reaction is measurable the day after
      // it happens; the PATHS are what need time, and those are now nullable.
      for (let k = 1; k < bars.length; k++) {
        const mv = Math.abs((bars[k].c - bars[k - 1].c) / bars[k - 1].c) * 100;
        if (mv > biggest) { biggest = mv; i = k; }
      }
      if (i < 1 || biggest < 3) continue;

      const before = bars[i - 1].c, after = bars[i].c;
      if (!(before > 0) || !(after > 0)) continue;
      const move = ((after - before) / before) * 100;
      // Null, not zero, when the session has not happened yet. A missing path and a
      // flat path are different facts and the median must not confuse them.
      const at = (n: number) => (bars[i + n] ? +(((bars[i + n].c - after) / after) * 100).toFixed(2) : null);

      rows.push({
        ticker,
        report_date: d,
        reaction_date: ymd(new Date(bars[i].t)),
        close_before: +before.toFixed(4),
        close_after: +after.toFixed(4),
        move_pct: +move.toFixed(2),
        d5_pct: at(5),
        d10_pct: at(10),
        d30_pct: at(30),
        band: move <= -BAND ? 'bad' : move >= BAND ? 'good' : 'flat',
        source: 'polygon',
      });
      report[ticker].measured++;
    }
  }

  let wrote = 0, writeNote = 'nothing to write';
  if (rows.length) {
    const r = await fetch(`${supaUrl}/rest/v1/earnings_reactions?on_conflict=ticker,report_date`, {
      method: 'POST',
      headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}`, 'Content-Type': 'application/json',
                 Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    });
    // Reported, never swallowed: a backfill that half-fails silently is worse than
    // one that fails loudly.
    writeNote = r.ok ? 'written' : `HTTP${r.status}: ${(await r.text()).slice(0, 200)}`;
    if (r.ok) wrote = rows.length;
  }

  return json(200, { ok: true, tickers, band: BAND, perTicker: report, wrote, write: writeNote });
});
