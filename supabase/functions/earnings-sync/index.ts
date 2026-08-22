/**
 * earnings-sync — Benzinga earnings dates, via Polygon.
 *
 * WHY THIS EXISTS
 * earnings_events was maintained by hand. At 144 names, 37 failed for want of a
 * date. At 596 it was 455, by far the largest single cause of rejection, larger
 * than edge, range and vol combined. A guard that cannot fire looks exactly like
 * a guard with nothing to catch, so the scanner SKIPS a name with no date, and
 * the universe was capped at whatever Nik could type.
 *
 * The feed fills three columns that were all hand-entered:
 *
 *   date         -> report_date
 *   date_status  -> date_estimated   ('confirmed' is the only confirmed value)
 *   time         -> report_time      (bmo before 09:30 ET, otherwise amc)
 *
 * That last one matters most. It is why BABA was blocked at +9.8 on the morning
 * of 20 Aug by a print it had already delivered before the open: the table held
 * a date and no time, so "reported at 07:00" and "reports after the close" were
 * indistinguishable. Nik entered seven of these by hand. Now none.
 *
 * ⚠ SANITY GATE, because the feed has bad rows. A sample Nik pulled carried
 * date 2029-09-24 against fiscal_year 2024, last updated in 2025. A four-year
 * blackout from one bad row would silently remove a name and look like a gate
 * working. Anything outside [today - 30d, today + 400d] is dropped and counted.
 *
 * ⚠ NEVER INFER A DATE. Polygon's `financials` endpoint works on this plan and
 * gives filing dates for periods already reported. Inferring the next print from
 * that cadence was tested and came out 31, 29 and 120 days wrong. This function
 * writes only dates the feed actually states.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-22.1';
const POLY = 'https://api.polygon.io';
const CHUNK = 40;          // tickers per request; ticker.any_of takes a list
const AHEAD = 400;         // days forward to accept
const BEHIND = 30;         // days back, so a just-passed print still blackouts

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const polyKey = Deno.env.get('POLYGON_API_KEY')!;
    if (!polyKey) return json(500, { ok: false, error: 'POLYGON_API_KEY is not set' });

    let body: { dry_run?: boolean; tickers?: string[] } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is fine */ }
    const D = db(url, key);
    const today = parseISO(nyToday());
    const from = ymd(addDays(today, -BEHIND));
    const to = ymd(addDays(today, AHEAD));

    /* Everything the app cares about: the scanner's universe, the sleeve's
       names, and anything with a position. A held name losing its date would
       silently stop being guarded. */
    const [uni, sleeve, pos] = await Promise.all([
      D.get('income_scanner_universe?active=is.true&select=ticker'),
      D.get('income_sleeve_names?active=is.true&select=ticker'),
      D.get('positions?select=ticker'),
    ]);
    const names = body.tickers ?? [...new Set([
      ...uni.map((r) => String(r.ticker)),
      ...sleeve.map((r) => String(r.ticker)),
      ...pos.map((r) => String(r.ticker)),
    ])].filter(Boolean);

    const rows: Record<string, unknown>[] = [];
    let dropped = 0, calls = 0, apiErr: string | null = null;

    for (let i = 0; i < names.length; i += CHUNK) {
      const part = names.slice(i, i + CHUNK);
      const u = `${POLY}/benzinga/v1/earnings?ticker.any_of=${part.join(',')}`
        + `&date.gte=${from}&date.lte=${to}&limit=1000&order=asc&sort=date&apiKey=${polyKey}`;
      try {
        const r = await fetch(u);
        calls++;
        if (!r.ok) { if (!apiErr) apiErr = `${r.status} ${(await r.text()).slice(0, 160)}`; continue; }
        const j = await r.json();
        for (const x of (j?.results ?? [])) {
          const t = String(x.ticker ?? '').toUpperCase();
          const d = String(x.date ?? '').slice(0, 10);
          if (!t || !/^\d{4}-\d{2}-\d{2}$/.test(d)) { dropped++; continue; }
          if (d < from || d > to) { dropped++; continue; }   // the 2029 problem
          /* Before the 09:30 open is pre, anything else is post. A midday time
             is unusual and treated as post, which only ever blocks longer. */
          const tm = String(x.time ?? '');
          const session = /^\d\d:\d\d/.test(tm) && tm < '09:30' ? 'bmo' : 'amc';
          rows.push({
            ticker: t,
            report_date: d,
            date_estimated: String(x.date_status ?? '') !== 'confirmed',
            report_time: session,
            source: 'benzinga',
            scope_tag: 'top50',
          });
        }
      } catch (e) { if (!apiErr) apiErr = String(e).slice(0, 160); }
    }

    // One row per ticker per date; the feed can repeat a print across revisions.
    const seen = new Set<string>();
    const uniq = rows.filter((r) => {
      const k = `${r.ticker}|${r.report_date}`;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });

    let wrote = 0;
    let writeErr: string | null = null;
    if (!body.dry_run) {
      for (let i = 0; i < uniq.length; i += 500) {
        try {
          /* scope_tag is NOT overwritten: it answers "why is this ticker here",
             and a name Nik marked 'position' must not be demoted to 'top50' by
             a feed refresh. */
          const r = await fetch(`${url}/rest/v1/earnings_events?on_conflict=ticker,report_date`, {
            method: 'POST',
            headers: {
              apikey: key, Authorization: `Bearer ${key}`,
              'Content-Type': 'application/json',
              Prefer: 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(uniq.slice(i, i + 500)),
          });
          if (r.ok) wrote += Math.min(500, uniq.length - i);
          else if (!writeErr) writeErr = `${r.status} ${(await r.text()).slice(0, 200)}`;
        } catch (e) { if (!writeErr) writeErr = String(e).slice(0, 160); }
      }
    }

    return json(200, {
      ok: true, build: BUILD, asof: ymd(today), window: `${from} .. ${to}`,
      tickers: names.length, api_calls: calls,
      found: rows.length, unique: uniq.length, dropped_insane: dropped,
      written: body.dry_run ? 'dry_run' : wrote,
      confirmed: uniq.filter((r) => r.date_estimated === false).length,
      pre_market: uniq.filter((r) => r.report_time === 'bmo').length,
      api_error: apiErr, write_error: writeErr,
      sample: uniq.slice(0, 5),
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
