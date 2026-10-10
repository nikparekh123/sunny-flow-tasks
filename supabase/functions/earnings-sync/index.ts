/**
 * earnings-sync — the book's next report dates, from Nasdaq's free calendar.
 *
 * ⚠ NOT BENZINGA ANY MORE (9 Oct 2026). Nik cancelled the Polygon news and
 * analyst add-ons, and the Benzinga earnings endpoint went with them: it answers
 * 403 "not entitled" and the 9 Oct run found nothing. Nasdaq publishes each
 * name's next date (Zacks-sourced) on a public endpoint, one name per call, so
 * the universe is now just the book: every name with an option leg not yet
 * expired, plus `positions`. The retired scanner's 596 names are gone with it.
 *
 * What the app reads from here: the roll sheet's earnings rule (20% at the
 * money before a report), its `earnings 17 Dec` line, and the New tab's
 * countdown chips. One row per ticker per date in earnings_events:
 *
 *   report_date     the date Nasdaq states, never inferred by us
 *   report_time     bmo / amc when Nasdaq says so, otherwise left as stored
 *   date_estimated  false only when Nasdaq states it without a qualifier
 *
 * ⚠ NASDAQ SPEAKS IN THREE STRENGTHS, and only two of them may move a date:
 *   "is estimated to report ... derived from an algorithm"   a GUESS, no time
 *   "is expected* to report ... before market open"          analysts' date
 *   "is scheduled / will report ..." (no asterisk)            confirmed
 * A guess fills a name with nothing stored for that quarter and never replaces
 * anything. An expected or confirmed date replaces the other FEED rows (benzinga
 * or nasdaq) for that name within 45 days, or the app would read the stale one.
 * Rows Nik entered by hand (`source = manual`) are never touched; a
 * disagreement with one is reported in `conflicts` instead.
 *
 * ⚠ NO DATE IS NOT A DELETE. Nasdaq often has nothing until a company
 * announces (NKE on 9 Oct): the stored date stays until a real one arrives.
 *
 * ⚠ SANITY GATE: anything outside [today - 30d, today + 400d] is dropped.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-10-09.1';
const AHEAD = 400;
const BEHIND = 30;
const SAME_QUARTER = 45;
/* Nasdaq refuses requests without a browser's headers. This goes to Nasdaq
   only, never to Supabase (a browser UA on a secret key is refused there). */
const UA = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    + '(KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'application/json, text/plain, */*',
  'Accept-Language': 'en-US,en;q=0.9',
};

type Row = { ticker: string; report_date: string; report_time: string | null;
             date_estimated: boolean; source: string; scope_tag: string;
             strength: 'guess' | 'expected' | 'confirmed' };

/** `... expected* to report earnings on  10/20/2026 after market close.` */
function parse(t: string, text: string): Row | null {
  const m = text.match(/on\s+(\d{1,2})\/(\d{1,2})\/(\d{4})\s*(before market open|after market close)?/i);
  if (!m) return null;
  const d = `${m[3]}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`;
  const strength = /derived from an algorithm|is estimated to report/i.test(text) ? 'guess'
    : /\*/.test(text.slice(0, text.search(/report earnings/i) + 1)) ? 'expected' : 'confirmed';
  return {
    ticker: t, report_date: d,
    report_time: m[4] ? (/before/i.test(m[4]) ? 'bmo' : 'amc') : null,
    date_estimated: strength !== 'confirmed',
    source: 'nasdaq', scope_tag: 'position', strength,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    let body: { dry_run?: boolean; tickers?: string[] } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is fine */ }
    const D = db(url, key);
    const today = parseISO(nyToday());
    const from = ymd(addDays(today, -BEHIND));
    const to = ymd(addDays(today, AHEAD));

    const [legs, pos] = await Promise.all([
      D.get(`option_trades?voided_at=is.null&expiry=gte.${ymd(today)}&select=ticker`),
      D.get('positions?select=ticker'),
    ]);
    const names = body.tickers ?? [...new Set([...legs, ...pos]
      .map((r) => String(r.ticker ?? '').toUpperCase()).filter(Boolean))].sort();

    const found: Row[] = [];
    const none: string[] = [];
    const errors: string[] = [];
    for (const t of names) {
      try {
        const r = await fetch(`https://api.nasdaq.com/api/analyst/${encodeURIComponent(t)}/earnings-date`,
          { headers: UA, signal: AbortSignal.timeout(10_000) });
        if (!r.ok) { errors.push(`${t} ${r.status}`); continue; }
        const j = await r.json();
        const row = parse(t, String(j?.data?.reportText ?? ''));
        if (!row || row.report_date < from || row.report_date > to) { none.push(t); continue; }
        found.push(row);
      } catch (e) { errors.push(`${t} ${String(e).slice(0, 60)}`); }
    }

    let wrote = 0, replaced = 0, kept = 0;
    const conflicts: string[] = [];
    let writeErr: string | null = null;
    const plan: string[] = [];
    {
      const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
      for (const row of found) {
        const lo = ymd(addDays(parseISO(row.report_date), -SAME_QUARTER));
        const hi = ymd(addDays(parseISO(row.report_date), SAME_QUARTER));
        const near = await D.get(`earnings_events?ticker=eq.${row.ticker}&report_date=gte.${lo}`
          + `&report_date=lte.${hi}&select=id,report_date,report_time,source`);
        const same = near.find((n) => String(n.report_date) === row.report_date);
        const others = near.filter((n) => String(n.report_date) !== row.report_date);
        const { strength, ...rec } = row;
        /* A guess never moves a stored quarter; it only fills an empty one. */
        if (strength === 'guess' && (same || others.length)) { kept++; plan.push(`${row.ticker} keep stored`); continue; }
        /* Never blank a stored time with an unknown one. */
        if (rec.report_time === null && same?.report_time) rec.report_time = String(same.report_time);
        plan.push(`${row.ticker} ${same ? 'update' : 'add'} ${row.report_date} ${rec.report_time ?? '?'} (${strength})`);
        if (body.dry_run) {
          for (const n of others) plan.push(`${row.ticker} ${String(n.source) === 'manual' ? 'conflict manual' : 'drop'} ${n.report_date}`);
          continue;
        }
        const r = await fetch(`${url}/rest/v1/earnings_events?on_conflict=ticker,report_date`, {
          method: 'POST',
          headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify([rec]),
        });
        if (!r.ok) { if (!writeErr) writeErr = `${r.status} ${(await r.text()).slice(0, 200)}`; continue; }
        wrote++;
        /* Only now, with the new date stored, drop the stale ones. */
        for (const n of others) {
          if (String(n.source) === 'manual') {
            conflicts.push(`${row.ticker} nasdaq ${row.report_date} vs manual ${n.report_date}`);
            continue;
          }
          plan.push(`${row.ticker} drop ${n.report_date} (${n.source})`);
          {
            const d = await fetch(`${url}/rest/v1/earnings_events?id=eq.${n.id}`, { method: 'DELETE', headers: h });
            if (d.ok) replaced++;
          }
        }
      }
    }

    /* Stamped last, on the success path only, so health-monitor's age check
       means the feed ran and wrote, not that a cron fired. */
    if (!body.dry_run && !writeErr) {
      await D.upsert('sync_heartbeat', [{
        feed: 'earnings-sync', ran_at: new Date().toISOString(),
        rows_written: wrote,
        detail: `nasdaq · ${names.length} names · dated ${found.length} · none ${none.length}`
          + ` · replaced ${replaced} · kept ${kept} · errors ${errors.length}`,
      }], 'feed');
    }

    return json(200, {
      ok: true, build: BUILD, asof: ymd(today), names: names.length,
      plan,
      no_date_yet: none, errors, written: body.dry_run ? 'dry_run' : wrote,
      replaced, conflicts, write_error: writeErr,
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
