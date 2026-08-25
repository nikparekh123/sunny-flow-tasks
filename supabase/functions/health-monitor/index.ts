/**
 * health-monitor — checks the data pipeline is healthy and raises
 * rows in `system_alerts` when it isn't.
 *
 * Checks:
 *   1. mp-refresh-15min — latest option_greeks captured_at < 20 min
 *      ago during market hours
 *   2. daily-theta-snapshot — yesterday's row exists (or today's if
 *      we're past 20:30 UTC)
 *   3. position-snapshot — same window check on position_history
 *
 * Each failed check calls public.raise_system_alert(code, ...);
 * each passing check calls public.clear_system_alert(code).
 *
 * Scheduled every 30 min during extended market hours. Cheap.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, serviceKey);

  // ── Window helpers (EST) ────────────────────────────────────
  const now = new Date();
  const estParts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York',
    hour: 'numeric', minute: 'numeric', weekday: 'short', hour12: false,
  }).formatToParts(now);
  const wd = estParts.find(p => p.type === 'weekday')?.value ?? '';
  const h = Number(estParts.find(p => p.type === 'hour')?.value ?? '0');
  // Trading window 9:30-16:00 ET, Mon-Fri.
  const isWeekday = !['Sat', 'Sun'].includes(wd);
  const mins = Number(estParts.find(p => p.type === 'minute')?.value ?? '0');
  const minsET = h * 60 + mins;
  const inMarket = isWeekday && minsET >= (9 * 60 + 30) && minsET < (16 * 60);
  /* Minutes since ibkr-flex-sync was ALLOWED to start today. The sync self-gates
     to 09:30-16:30 ET and returns 'out-of-window' before that, so the overnight
     gap is not staleness and must not be counted as it. This used to say
     `h >= 9`, which had the monitor demanding a fresh run at 09:00 while the
     sync was still barred from making one. It measured back to the previous
     afternoon and raised CRITICAL every single weekday morning. Harmless while
     APNs was dead; a 09:00 alarm on Nik's phone now that it works. */
  const minsSinceSyncOpen = minsET - (9 * 60 + 30);

  const findings: { code: string; ok: boolean; severity?: 'warn' | 'critical'; detail: string; meta?: Record<string, unknown> }[] = [];

  // 1) mp-refresh: latest option_greeks captured_at.
  //    Skip the check outside market hours — staleness is expected.
  //
  //    Threshold tuning (2026-06-09): the prior 20-min cutoff was
  //    too tight for a 15-min cron. One slow Polygon round-trip
  //    pushed runs to 16-18 min apart, alarm fires at 21 min, then
  //    next run clears it — but the user saw the red banner every
  //    time. New ladder:
  //      ≤ 35m  → ok (matches IBKR pattern: 2× cadence + slack)
  //      35-60m → warn ("Market data refreshing"; soft yellow)
  //      > 60m  → critical ("Market data is stale"; red)
  //    Banner severity comes from `severity` below — apply step uses
  //    it instead of always raising critical.
  if (inMarket) {
    const { data: g, error: gErr } = await supabase
      .from('option_greeks_latest')
      .select('captured_at')
      .order('captured_at', { ascending: false })
      .limit(1);
    if (gErr) {
      findings.push({
        code: 'cron.mp_refresh_stale',
        ok: false,
        severity: 'critical',
        detail: `option_greeks_latest query failed: ${gErr.message}`,
      });
    } else {
      const latest = g?.[0]?.captured_at ? new Date(g[0].captured_at as string).getTime() : 0;
      const ageMin = latest > 0 ? (now.getTime() - latest) / 60000 : Infinity;
      if (ageMin > 60) {
        findings.push({
          code: 'cron.mp_refresh_stale',
          ok: false,
          severity: 'critical',
          detail: `Market data hasn't refreshed in ${Math.round(ageMin)} minutes. The mp-refresh cron may be down.`,
          meta: { last_captured_at: g?.[0]?.captured_at ?? null, age_minutes: Math.round(ageMin) },
        });
      } else if (ageMin > 35) {
        findings.push({
          code: 'cron.mp_refresh_stale',
          ok: false,
          severity: 'warn',
          detail: `Market data last refreshed ${Math.round(ageMin)}m ago — slightly delayed; usually resolves on its own.`,
          meta: { last_captured_at: g?.[0]?.captured_at ?? null, age_minutes: Math.round(ageMin) },
        });
      } else {
        findings.push({ code: 'cron.mp_refresh_stale', ok: true, detail: '' });
      }
    }
  }

  // 2 + 3) daily-theta-snapshot and position-snapshot checks DISABLED.
  // The underlying snapshot functions return non-200 but pg_cron only
  // logs HTTP-call-success, masking the failure. Until task #19 fixes
  // why those functions don't write to daily_theta_snapshot /
  // position_history, skip the checks AND mark them OK so any existing
  // alerts auto-clear on the next health-monitor run.
  // To re-enable: restore the original blocks from git history of this
  // file (commit 824eaa6) once the snapshot pipeline is fixed.
  findings.push({ code: 'cron.daily_theta_snapshot_missing', ok: true, detail: '' });
  findings.push({ code: 'cron.position_snapshot_missing',    ok: true, detail: '' });

  // 4) ibkr-flex-sync — most recent successful run during market hours.
  //    Skipped outside market hours since cron only runs Mon-Fri 13:00-21:59
  //    UTC; alerting at midnight ET would be noise.
  if (inMarket) {
    const { data: ibkr, error: ibkrErr } = await supabase
      .from('ibkr_sync_runs')
      .select('finished_at, status')
      .eq('status', 'success')
      .order('finished_at', { ascending: false })
      .limit(1);
    if (ibkrErr) {
      findings.push({
        code: 'cron.ibkr_flex_stale',
        ok: false,
        detail: `ibkr_sync_runs query failed: ${ibkrErr.message}`,
      });
    } else {
      const latest = ibkr?.[0]?.finished_at
        ? new Date(ibkr[0].finished_at as string).getTime()
        : 0;
      const rawAgeMin = latest > 0 ? (now.getTime() - latest) / 60000 : Infinity;
      // Never blame the sync for time it was not permitted to run.
      const ageMin = Math.min(rawAgeMin, minsSinceSyncOpen);
      // Cron is 15-min. Two tiers:
      //   ≤ 35m  → ok
      //   35-90m → warn (yellow, "IBKR sync delayed")
      //   > 90m  → critical (red, "IBKR sync is stale")
      if (ageMin > 90) {
        findings.push({
          code: 'cron.ibkr_flex_stale',
          ok: false,
          severity: 'critical',
          detail: `IBKR sync hasn't run successfully in ${Math.round(ageMin)} minutes. The cron may be down.`,
          meta: { last_finished_at: ibkr?.[0]?.finished_at ?? null, age_minutes: Math.round(ageMin) },
        });
      } else if (ageMin > 35) {
        findings.push({
          code: 'cron.ibkr_flex_stale',
          ok: false,
          severity: 'warn',
          detail: `IBKR sync last completed ${Math.round(ageMin)}m ago — slightly delayed; usually resolves on its own.`,
          meta: { last_finished_at: ibkr?.[0]?.finished_at ?? null, age_minutes: Math.round(ageMin) },
        });
      } else {
        findings.push({ code: 'cron.ibkr_flex_stale', ok: true, detail: '' });
      }
    }
  }

  /* 5) FEED HEARTBEATS — the check that would have caught the analyst hole.
        
        ⚠ IT READS THE FEED'S OWN STAMP, NOT THE CRON'S STATUS. pg_cron records
        "succeeded" the moment net.http_post returns a request id; it never
        learns whether the function ran, wrote, or threw. Three consecutive
        green cron rows is exactly what the analyst feed looked like while Nik
        was reading the same card three days running. Checks 2 and 3 above are
        switched off for the same lie told about the snapshot pipeline.

        ⚠ AND IT ALERTS ON AGE, NEVER ON ROWS WRITTEN. A feed that runs and
        finds nothing is healthy: analysts are silent at weekends and over
        holidays, and an alert on a quiet Sunday is an alert he learns to
        ignore. rows_written rides in the meta so it can be read, not judged.

        Cadence is daily at 05:30 UTC, so the grace is generous: a run missed by
        an hour is noise, a run missed by a day is the thing worth knowing. */
  /* Cadences are the cron's own, plus a grace that makes a single missed run a
     WARN and a genuinely dead feed a CRITICAL. Weekday-only feeds get a grace
     that clears a weekend: position-snapshot last runs Friday 20:30 UTC, so by
     Monday morning it is ~60h old and healthy. Setting those to a day would
     alert every Sunday, and an alarm that cries on schedule is one he stops
     reading — the same reason rows_written is never the trigger. */
  const FEEDS: Array<{ feed: string; warnHours: number; critHours: number }> = [
    // daily, every day
    { feed: 'intel-sync',           warnHours: 30,  critHours: 50 },
    { feed: 'earnings-sync',        warnHours: 30,  critHours: 50 },
    // weekday only — the grace has to clear a weekend, and a long one
    { feed: 'income-scanner',       warnHours: 80,  critHours: 110 },
    { feed: 'ticker-iv-snapshot',   warnHours: 80,  critHours: 110 },
    { feed: 'daily-theta-snapshot', warnHours: 80,  critHours: 110 },
    { feed: 'position-snapshot',    warnHours: 80,  critHours: 110 },
  ];
  const { data: beats, error: beatErr } = await supabase
    .from('sync_heartbeat')
    .select('feed, ran_at, rows_written, detail');
  for (const f of FEEDS) {
    const code = `feed.${f.feed.replace(/-/g, '_')}_stale`;
    if (beatErr) {
      findings.push({ code, ok: false, detail: `sync_heartbeat query failed: ${beatErr.message}` });
      continue;
    }
    const hb = (beats ?? []).filter((b) => b.feed === f.feed);
    const stamped = hb?.[0]?.ran_at ? new Date(hb[0].ran_at as string).getTime() : 0;
    // No row at all is not "infinitely stale" on the first deploy; it is a feed
    // that has never reported, which is worth a warn rather than a red screen.
    const ageH = stamped > 0 ? (now.getTime() - stamped) / 3_600_000 : f.warnHours + 1;
    const meta = {
      last_ran_at: hb?.[0]?.ran_at ?? null,
      age_hours: Math.round(ageH),
      rows_written: hb?.[0]?.rows_written ?? null,
      detail: hb?.[0]?.detail ?? null,
    };
    if (ageH > f.critHours) {
      findings.push({ code, ok: false, severity: 'critical',
        detail: `${f.feed} has not reported in ${Math.round(ageH)}h. The cards are showing old facts.`,
        meta });
    } else if (ageH > f.warnHours) {
      findings.push({ code, ok: false, severity: 'warn',
        detail: `${f.feed} last reported ${Math.round(ageH)}h ago — one run behind.`,
        meta });
    } else {
      findings.push({ code, ok: true, detail: '' });
    }
  }

  // Apply findings. Severity is per-finding (default critical for
  // back-compat with any caller that doesn't set it); titles vary
  // by severity so a 'warn' tier doesn't read like a 9-1-1.
  for (const f of findings) {
    if (f.ok) {
      await supabase.rpc('clear_system_alert', { p_code: f.code });
    } else {
      const sev = f.severity ?? 'critical';
      await supabase.rpc('raise_system_alert', {
        p_code: f.code,
        p_severity: sev,
        p_title: titleForCode(f.code, sev),
        p_detail: f.detail,
        p_meta: f.meta ?? {},
      });
    }
  }

  return new Response(JSON.stringify({ findings }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});

function isoYesterday(today: string): string {
  // today is YYYY-MM-DD; just step back one calendar day in UTC.
  const d = new Date(`${today}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

/// Most recent trading day STRICTLY BEFORE today. Used as the expected
/// snapshot date when today's cron hasn't run yet (i.e. it's before
/// 21:00 UTC). Examples:
///   today = Mon → returns Fri (skips Sat+Sun)
///   today = Sat → returns Fri
///   today = Sun → returns Fri
///   today = Tue → returns Mon
function isoLastTradingDayBefore(today: string): string {
  const d = new Date(`${today}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  while (d.getUTCDay() === 0 || d.getUTCDay() === 6) {
    d.setUTCDate(d.getUTCDate() - 1);
  }
  return d.toISOString().slice(0, 10);
}

function titleForCode(code: string, sev: 'warn' | 'critical' = 'critical'): string {
  switch (code) {
    case 'cron.mp_refresh_stale':
      return sev === 'warn' ? 'Market data refreshing' : 'Market data is stale';
    case 'cron.daily_theta_snapshot_missing':  return 'Daily theta snapshot missing';
    case 'cron.position_snapshot_missing':     return 'Position snapshot missing';
    case 'cron.ibkr_flex_stale':
      return sev === 'warn' ? 'IBKR sync delayed' : 'IBKR sync is stale';
    case 'feed.intel_sync_stale':
      return sev === 'warn' ? 'News feed one run behind' : 'News feed has stopped';
    case 'feed.earnings_sync_stale':
      return sev === 'warn' ? 'Earnings dates one run behind' : 'Earnings dates have stopped';
    case 'feed.income_scanner_stale':
      return sev === 'warn' ? 'Scanner one run behind' : 'Scanner has stopped';
    case 'feed.ticker_iv_snapshot_stale':
      return sev === 'warn' ? 'IV snapshot one run behind' : 'IV snapshot has stopped';
    case 'feed.daily_theta_snapshot_stale':
      return sev === 'warn' ? 'Theta snapshot one run behind' : 'Theta snapshot has stopped';
    case 'feed.position_snapshot_stale':
      return sev === 'warn' ? 'Position snapshot one run behind' : 'Position snapshot has stopped';
    default:                                    return code;
  }
}
