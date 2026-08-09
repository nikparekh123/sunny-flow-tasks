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
  const report: Record<string, { prints: number; measured: number }> = {};

  for (const ticker of tickers) {
    const dates = await filingDates(ticker, key, limit);
    report[ticker] = { prints: dates.length, measured: 0 };

    for (const d of dates) {
      const day = new Date(d + 'T00:00:00Z');
      // A window wide enough to hold the session before and 30 sessions after,
      // with slack for weekends and holidays.
      const from = ymd(new Date(day.getTime() - 10 * 86400000));
      const to = ymd(new Date(day.getTime() + 60 * 86400000));
      const bars = await dailyBars(ticker, from, to, key);
      if (bars.length < 35) continue;

      // The reaction is the first session ON or AFTER the filing date; the one
      // before it is the reference close.
      const i = bars.findIndex((b) => ymd(new Date(b.t)) >= d);
      if (i < 1 || i + 30 >= bars.length) continue;

      const before = bars[i - 1].c, after = bars[i].c;
      if (!(before > 0) || !(after > 0)) continue;
      const move = ((after - before) / before) * 100;
      const at = (n: number) => ((bars[i + n].c - after) / after) * 100;

      rows.push({
        ticker,
        report_date: d,
        reaction_date: ymd(new Date(bars[i].t)),
        close_before: +before.toFixed(4),
        close_after: +after.toFixed(4),
        move_pct: +move.toFixed(2),
        d5_pct: +at(5).toFixed(2),
        d10_pct: +at(10).toFixed(2),
        d30_pct: +at(30).toFixed(2),
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
