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
  // Trading window 9:30–16:00 ET, Mon–Fri.
  const isWeekday = !['Sat', 'Sun'].includes(wd);
  const inMarket = isWeekday && h >= 9 && h < 16;

  const findings: { code: string; ok: boolean; detail: string; meta?: Record<string, unknown> }[] = [];

  // 1) mp-refresh: latest option_greeks captured_at.
  //    Skip the check outside market hours — staleness is expected.
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
        detail: `option_greeks_latest query failed: ${gErr.message}`,
      });
    } else {
      const latest = g?.[0]?.captured_at ? new Date(g[0].captured_at as string).getTime() : 0;
      const ageMin = latest > 0 ? (now.getTime() - latest) / 60000 : Infinity;
      if (ageMin > 20) {
        findings.push({
          code: 'cron.mp_refresh_stale',
          ok: false,
          detail: `Greeks last refreshed ${Math.round(ageMin)}m ago; expected ≤ 20m during market hours.`,
          meta: { last_captured_at: g?.[0]?.captured_at ?? null, age_minutes: Math.round(ageMin) },
        });
      } else {
        findings.push({ code: 'cron.mp_refresh_stale', ok: true, detail: '' });
      }
    }
  }

  // 2) daily-theta-snapshot — yesterday's (or today's after close) row exists.
  //    Use the most recent snapshot date <= today and check it's ≤ 1 day old.
  const todayEst = new Date().toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
  const { data: dts, error: dtsErr } = await supabase
    .from('daily_theta_snapshot')
    .select('snapshot_date')
    .order('snapshot_date', { ascending: false })
    .limit(1);
  if (dtsErr) {
    findings.push({
      code: 'cron.daily_theta_snapshot_missing',
      ok: false,
      detail: `daily_theta_snapshot query failed: ${dtsErr.message}`,
    });
  } else {
    const last = dts?.[0]?.snapshot_date as string | undefined;
    // If we're past 20:30 UTC today (after the cron should have run),
    // we expect today's row. Otherwise yesterday's is fine.
    const expectToday = now.getUTCHours() >= 21;
    const expected = expectToday ? todayEst : isoYesterday(todayEst);
    if (!last || last < expected) {
      findings.push({
        code: 'cron.daily_theta_snapshot_missing',
        ok: false,
        detail: `Latest theta snapshot ${last ?? 'none'} — expected ≥ ${expected}.`,
        meta: { last_snapshot: last ?? null, expected_at_least: expected },
      });
    } else {
      findings.push({ code: 'cron.daily_theta_snapshot_missing', ok: true, detail: '' });
    }
  }

  // 3) position-snapshot — same window logic.
  const { data: ph, error: phErr } = await supabase
    .from('position_history')
    .select('snapshot_date')
    .order('snapshot_date', { ascending: false })
    .limit(1);
  if (phErr) {
    findings.push({
      code: 'cron.position_snapshot_missing',
      ok: false,
      detail: `position_history query failed: ${phErr.message}`,
    });
  } else {
    const last = ph?.[0]?.snapshot_date as string | undefined;
    const expectToday = now.getUTCHours() >= 21;
    const expected = expectToday ? todayEst : isoYesterday(todayEst);
    if (!last || last < expected) {
      findings.push({
        code: 'cron.position_snapshot_missing',
        ok: false,
        detail: `Latest position snapshot ${last ?? 'none'} — expected ≥ ${expected}.`,
        meta: { last_snapshot: last ?? null, expected_at_least: expected },
      });
    } else {
      findings.push({ code: 'cron.position_snapshot_missing', ok: true, detail: '' });
    }
  }

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
      const ageMin = latest > 0 ? (now.getTime() - latest) / 60000 : Infinity;
      // Cron is 15-min; allow 2× cadence + slack before alerting.
      if (ageMin > 35) {
        findings.push({
          code: 'cron.ibkr_flex_stale',
          ok: false,
          detail: `IBKR sync last successful ${Math.round(ageMin)}m ago; expected ≤ 35m during market hours.`,
          meta: { last_finished_at: ibkr?.[0]?.finished_at ?? null, age_minutes: Math.round(ageMin) },
        });
      } else {
        findings.push({ code: 'cron.ibkr_flex_stale', ok: true, detail: '' });
      }
    }
  }

  // Apply findings.
  for (const f of findings) {
    if (f.ok) {
      await supabase.rpc('clear_system_alert', { p_code: f.code });
    } else {
      await supabase.rpc('raise_system_alert', {
        p_code: f.code,
        p_severity: 'critical',
        p_title: titleForCode(f.code),
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

function titleForCode(code: string): string {
  switch (code) {
    case 'cron.mp_refresh_stale':              return 'Market data is stale';
    case 'cron.daily_theta_snapshot_missing':  return 'Daily theta snapshot missing';
    case 'cron.position_snapshot_missing':     return 'Position snapshot missing';
    case 'cron.ibkr_flex_stale':               return 'IBKR sync is stale';
    default:                                    return code;
  }
}
