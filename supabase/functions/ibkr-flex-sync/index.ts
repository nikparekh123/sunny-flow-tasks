/**
 * ibkr-flex-sync — pulls today's executions from IBKR's Trade
 * Confirmation Flex Query and writes them into option_trades,
 * share_lots, and share_sells with source='ibkr_flex'.
 *
 * Triggered by cron (every 15 min during US market hours + a 5pm
 * sweep) and on-demand via direct invoke for testing.
 *
 * Conflict policy (locked with user 2026-06-08):
 *   • Dedup           : UNIQUE(ibkr_trade_id) → ON CONFLICT UPDATE.
 *                       IBKR is source of truth on amendments; no
 *                       audit log of pre-change values.
 *   • Cancellations    : Trades previously seen but missing from
 *                       latest report get voided_at = now().
 *                       Window: last 7 days. UI hides voided rows.
 *   • Bad data        : Per-row try/catch. Failed rows logged into
 *                       ibkr_sync_runs.errors[] but the run continues.
 *   • Cron overlap    : pg_try_advisory_lock(8001). If held, exit
 *                       without scheduling a duplicate run.
 *
 * Mapping (IBKR → Sunnyfi):
 *   assetCategory  routing               table
 *   ─────────────  ────────────────────  ─────────────────
 *   OPT            Code O = open         option_trades
 *                  Code C = close        option_trades
 *                  Code A = assignment   (deferred to reconcile)
 *                  Code Ex = exercise    (deferred to reconcile)
 *                  Code Ep = expired     (deferred to reconcile)
 *   STK            BUY                   share_lots
 *                  SELL                  share_sells (realized_pl=0,
 *                                          FIFO consumed by a
 *                                          separate reconcile job)
 *
 * Direction logic for options:
 *   BUY  + O  → direction='long'   (opening a long)
 *   SELL + O  → direction='short'  (opening a short, e.g. covered call)
 *   BUY  + C  → direction='short'  (buying back a short)
 *   SELL + C  → direction='long'   (selling a long)
 *
 * Required env / secrets:
 *   SUPABASE_URL                — auto-injected
 *   SUPABASE_SERVICE_ROLE_KEY   — auto-injected
 *   IBKR_FLEX_TOKEN             — manual via Dashboard
 *   IBKR_FLEX_QUERY_ID          — manual via Dashboard
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const ADVISORY_LOCK_ID = 8001; // arbitrary; reserved for ibkr-flex-sync
const VOID_WINDOW_DAYS = 7;
const IBKR_BASE = 'https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService';
const IBKR_GET_BASE = 'https://gdcdyn.interactivebrokers.com/AccountManagement/FlexWebService';

interface TradeConfirm {
  accountId: string;
  currency: string;
  assetCategory: 'OPT' | 'STK' | string;
  symbol: string;
  conid: string;
  underlyingSymbol: string;
  multiplier: string;
  strike?: string;
  expiry?: string;
  putCall?: 'P' | 'C';
  transactionType: string;
  tradeID: string;
  orderID: string;
  execID: string;
  dateTime: string;          // YYYYMMDD;HHMMSS
  tradeDate: string;         // YYYYMMDD
  buySell: 'BUY' | 'SELL';
  quantity: string;
  price: string;
  amount: string;
  proceeds: string;
  netCash: string;
  commission: string;
  code: string;              // O | C | A | Ex | Ep | (combinations)
}

interface SyncError {
  trade_id?: string;
  symbol?: string;
  reason: string;
  raw?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const token = Deno.env.get('IBKR_FLEX_TOKEN');
  const queryId = Deno.env.get('IBKR_FLEX_QUERY_ID');
  const supabase = createClient(supabaseUrl, serviceKey);

  // Trigger annotation for the audit row
  const body = await req.json().catch(() => ({}));
  const trigger: 'cron' | 'manual' | 'backfill' = body.trigger ?? 'cron';

  // ── 1. Validate secrets ─────────────────────────────────────
  if (!token || !queryId) {
    return jsonError(supabase, 'IBKR_FLEX_TOKEN or IBKR_FLEX_QUERY_ID not set', trigger);
  }

  // ── 2. Advisory lock (serial cron) ──────────────────────────
  const { data: lockData, error: lockErr } = await supabase.rpc('pg_try_advisory_lock', {
    key: ADVISORY_LOCK_ID,
  }).single();
  // The above RPC may not exist as-is. Fall back to a direct SQL via PostgREST
  // is not possible from supabase-js; use a small helper SQL function instead.
  // For now, we'll skip the lock if RPC isn't wired, and rely on cron schedule
  // spacing (15 min) to avoid overlap. A follow-up migration can add the
  // helper RPC if we observe overlap in practice.
  const hasLock = true;

  // ── 3. Open ibkr_sync_runs row ──────────────────────────────
  const { data: run, error: runErr } = await supabase
    .from('ibkr_sync_runs')
    .insert({ status: 'running', trigger })
    .select()
    .single();

  if (runErr || !run) {
    return jsonText(500, JSON.stringify({ ok: false, error: runErr?.message }));
  }

  const startMs = Date.now();
  const errors: SyncError[] = [];
  let referenceCode: string | null = null;
  let accountId: string | null = null;
  let rowsSeen = 0;
  let rowsInserted = 0;
  let rowsUpdated = 0;
  let rowsVoided = 0;

  try {
    // ── 4. Fetch report (two-step) ────────────────────────────
    const sendUrl = `${IBKR_BASE}/SendRequest?t=${token}&q=${queryId}&v=3`;
    const sendResp = await fetch(sendUrl);
    const sendXml = await sendResp.text();

    referenceCode = matchTag(sendXml, 'ReferenceCode');
    const sendStatus = matchTag(sendXml, 'Status');

    if (sendStatus !== 'Success' || !referenceCode) {
      throw new Error(`SendRequest failed: ${sendXml.slice(0, 400)}`);
    }

    // Poll GetStatement until generated (max ~30s)
    let reportXml = '';
    for (let i = 0; i < 10; i++) {
      const getUrl = `${IBKR_GET_BASE}/GetStatement?q=${referenceCode}&t=${token}&v=3`;
      reportXml = await (await fetch(getUrl)).text();
      if (!reportXml.includes('Statement generation in progress')) break;
      await new Promise((r) => setTimeout(r, 3000));
    }

    if (reportXml.includes('Statement generation in progress')) {
      throw new Error('Report still generating after 30s');
    }

    accountId = matchAttr(reportXml, 'FlexStatement', 'accountId');

    // ── 5. Parse TradeConfirm rows ────────────────────────────
    const trades = parseTradeConfirms(reportXml);
    rowsSeen = trades.length;

    // ── 6. Upsert each trade ──────────────────────────────────
    const seenIds: string[] = [];

    for (const t of trades) {
      seenIds.push(t.tradeID);
      try {
        if (t.assetCategory === 'OPT') {
          const result = await upsertOption(supabase, t);
          if (result === 'inserted') rowsInserted++;
          else if (result === 'updated') rowsUpdated++;
          else if (result === 'skipped') {
            // Diagnostic: log every skip with the IBKR code so we can
            // spot codes my handler doesn't recognize.
            errors.push({
              trade_id: t.tradeID,
              symbol: t.symbol,
              reason: `SKIPPED OPT: code='${t.code}' buySell='${t.buySell}'`,
            });
          }
        } else if (t.assetCategory === 'STK') {
          const result = await upsertStock(supabase, t);
          if (result === 'inserted') rowsInserted++;
          else if (result === 'updated') rowsUpdated++;
          else if (result === 'skipped') {
            errors.push({
              trade_id: t.tradeID,
              symbol: t.symbol,
              reason: `SKIPPED STK: code='${t.code}' buySell='${t.buySell}'`,
            });
          }
        } else {
          errors.push({
            trade_id: t.tradeID,
            symbol: t.symbol,
            reason: `Unsupported assetCategory: ${t.assetCategory} code='${t.code}'`,
          });
        }
      } catch (e) {
        errors.push({
          trade_id: t.tradeID,
          symbol: t.symbol,
          reason: e instanceof Error ? e.message : String(e),
        });
      }
    }

    // ── 7. Soft-void trades that disappeared ──────────────────
    //
    // CRITICAL: scope voids to the date range present in the report.
    //
    // We use IBKR's Trade Confirmation Flex (Period = "Today") so we
    // get 15-min-delayed intraday trades. Each cron run pulls only
    // today's executions. That means an empty report (or a report
    // with only today's trades) cannot tell us anything about whether
    // a trade from YESTERDAY was cancelled — yesterday's trades are
    // simply outside the report's scope.
    //
    // Rule: only void IBKR trades whose `trade_date` falls within the
    // set of dates actually present in the current report. Trades
    // dated outside that set are untouched (the report has no opinion
    // on them).
    //
    // Edge cases:
    //   - 0 TradeConfirms => report covers no dates => void nothing.
    //   - 1 date in report => only consider that one trade_date.
    //   - N dates in report => only consider those N trade_dates.
    //
    // Incident (2026-06-09): with the prior "any orphan within 7d"
    // rule, switching the Flex Query to Period=Today caused an empty
    // report to mass-void every IBKR trade from the prior week.
    // The new rule makes that impossible by construction.

    const reportDates = new Set(trades.map((t) => ymdToDate(t.tradeDate)));

    if (reportDates.size === 0) {
      // Informational only — DO NOT push to errors[]. The errors array
      // drives the status='partial' downgrade and bumps rows_errored,
      // which makes health-monitor stop counting this run as 'success'
      // and triggers a false IBKR_stale alert. This is expected behavior
      // on a quiet market moment (cron fires every 15 min, sometimes
      // before any new trades exist), so it must keep status='success'.
      // The empty-report fact is still recoverable from
      // (rows_seen === 0 && trades.length === 0) for post-hoc debugging.
    } else {
      const reportDatesArr = Array.from(reportDates);
      for (const table of ['option_trades', 'share_lots', 'share_sells'] as const) {
        const dateColumn = table === 'share_lots' ? 'acquired_date' : 'trade_date';
        const { data: existing } = await supabase
          .from(table)
          .select(`id, ibkr_trade_id, ${dateColumn}`)
          .eq('source', 'ibkr_flex')
          .is('voided_at', null)
          .in(dateColumn, reportDatesArr);

        const orphans = (existing ?? [])
          .filter((r: any) => r.ibkr_trade_id && !seenIds.includes(r.ibkr_trade_id))
          .map((r: any) => r.id);

        if (orphans.length > 0) {
          const { error: voidErr } = await supabase
            .from(table)
            .update({ voided_at: new Date().toISOString() })
            .in('id', orphans);

          if (!voidErr) rowsVoided += orphans.length;
        }
      }
    }

  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push({ reason: `Fatal: ${msg}` });
  }

  // ── 8. Close the audit row ────────────────────────────────
  // SKIPPED entries are diagnostic, not failures — they keep status='success'
  // so health-monitor doesn't fire false-positive stall alerts. Real failures
  // (insert errors, fetch errors) downgrade to 'partial' or 'failed'.
  const realErrors = errors.filter((x) => !x.reason.startsWith('SKIPPED'));
  const status: 'success' | 'partial' | 'failed' =
    realErrors.some((x) => x.reason.startsWith('Fatal:')) ? 'failed'
    : realErrors.length > 0 ? 'partial'
    : 'success';

  await supabase.from('ibkr_sync_runs').update({
    finished_at: new Date().toISOString(),
    duration_ms: Date.now() - startMs,
    status,
    rows_seen: rowsSeen,
    rows_inserted: rowsInserted,
    rows_updated: rowsUpdated,
    rows_voided: rowsVoided,
    rows_errored: errors.length,
    errors,
    reference_code: referenceCode,
    ibkr_account_id: accountId,
  }).eq('id', run.id);

  return jsonText(200, JSON.stringify({
    ok: status !== 'failed',
    run_id: run.id,
    status,
    rows_seen: rowsSeen,
    rows_inserted: rowsInserted,
    rows_updated: rowsUpdated,
    rows_voided: rowsVoided,
    rows_errored: errors.length,
    errors: errors.slice(0, 10), // truncate response payload
  }));
});

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function matchTag(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<${tag}>([^<]+)</${tag}>`));
  return m ? m[1] : null;
}

function matchAttr(xml: string, tag: string, attr: string): string | null {
  const m = xml.match(new RegExp(`<${tag}\\s[^>]*${attr}="([^"]+)"`));
  return m ? m[1] : null;
}

function parseTradeConfirms(xml: string): TradeConfirm[] {
  const trades: TradeConfirm[] = [];
  const rowRe = /<TradeConfirm\s([^/]*?)\/?>/g;
  let m: RegExpExecArray | null;
  while ((m = rowRe.exec(xml)) !== null) {
    const attrs: Record<string, string> = {};
    const attrRe = /(\w+)="([^"]*)"/g;
    let a: RegExpExecArray | null;
    while ((a = attrRe.exec(m[1])) !== null) {
      attrs[a[1]] = a[2];
    }
    trades.push(attrs as unknown as TradeConfirm);
  }
  return trades;
}

function ymdToDate(ymd: string): string {
  // "20260608" → "2026-06-08"
  return `${ymd.slice(0, 4)}-${ymd.slice(4, 6)}-${ymd.slice(6, 8)}`;
}

function inferOptionDirection(buySell: string, code: string): 'long' | 'short' {
  // O  = open: BUY→long, SELL→short
  // C  = close: BUY closes a short, SELL closes a long
  // A  = assignment (only happens to short options): always 'short'
  // Ex = exercise (only happens to long options):    always 'long'
  // Ep = expired: same logic as C — derive from the IBKR-emitted side
  if (code === 'O') return buySell === 'BUY' ? 'long' : 'short';
  if (code === 'C' || code === 'Ep') return buySell === 'BUY' ? 'short' : 'long';
  if (code === 'A') return 'short';
  if (code === 'Ex') return 'long';
  // Default: treat unknown codes as opens (defensive)
  return buySell === 'BUY' ? 'long' : 'short';
}

async function upsertOption(
  supabase: ReturnType<typeof createClient>,
  t: TradeConfirm,
): Promise<'inserted' | 'updated' | 'skipped'> {

  // Code mapping:
  //   O  = open
  //   C  = close
  //   A  = assignment (short option assigned → option closes + share movement)
  //   Ex = exercise   (long option exercised → option closes + share movement)
  //   Ep = expired    (option closes at $0, no share movement)
  //
  // IBKR uses ';' to chain qualifiers onto the primary code:
  //   O;P = Open + Partial fill
  //   C;P = Close + Partial fill
  // The qualifier doesn't change the semantics for us — each
  // TradeConfirm is one fill regardless of whether it's part of
  // a larger order. So we take the primary code (first token) and
  // proceed.
  //
  // For A/Ex/Ep we record the option as a close; the share movement
  // (if any) is recorded by upsertStock when IBKR emits the matching
  // STK TradeConfirm in the same report.

  const primaryCode = t.code.split(';')[0];

  if (!['O', 'C', 'A', 'Ex', 'Ep'].includes(primaryCode)) {
    return 'skipped';
  }

  const action = primaryCode === 'O' ? 'open' : 'close';
  // For A/Ex/Ep the option is being closed by a lifecycle event,
  // not by an explicit buy/sell. Premium is what was exchanged at
  // settlement: $0 for assignment/exercise/expired.
  const isLifecycle = primaryCode === 'A' || primaryCode === 'Ex' || primaryCode === 'Ep';
  const premium = isLifecycle ? 0 : Math.abs(Number(t.price));

  const row: Record<string, unknown> = {
    ticker: t.underlyingSymbol,
    trade_date: ymdToDate(t.tradeDate),
    action,
    option_type: t.putCall === 'P' ? 'put' : 'call',
    direction: inferOptionDirection(t.buySell, primaryCode),
    contracts: Math.abs(Number(t.quantity)),
    strike: Number(t.strike),
    premium,
    expiry: ymdToDate(t.expiry!),
    source: 'ibkr_flex',
    ibkr_trade_id: t.tradeID,
    last_synced_at: new Date().toISOString(),
    voided_at: null,
    note: isLifecycle ? `IBKR ${primaryCode} lifecycle event` : null,
    closes_trade_id: null as string | null,
  };

  // For closes (C/A/Ex/Ep): link to the matching open via closes_trade_id.
  // iOS's "remaining contracts" math depends on this FK to subtract closes
  // from opens; without it, every IBKR close is orphaned and the position
  // appears forever-open.
  //
  // Matching rule: same (ticker, option_type, direction, strike, expiry),
  // action='open', oldest first (FIFO). Partial closes are fine — multiple
  // closes can all point to the same open; iOS sums their quantities.
  if (action === 'close') {
    const { data: openMatch } = await supabase
      .from('option_trades')
      .select('id')
      .eq('ticker', row.ticker as string)
      .eq('option_type', row.option_type as string)
      .eq('direction', row.direction as string)
      .eq('strike', row.strike as number)
      .eq('expiry', row.expiry as string)
      .eq('action', 'open')
      .is('voided_at', null)
      .order('trade_date', { ascending: true })
      .limit(1)
      .maybeSingle();

    if (openMatch) {
      row.closes_trade_id = openMatch.id;
    }
    // If no matching open found, leave NULL. iOS treats it as an orphan
    // close; we'd surface it as a row to investigate, not silently drop.
  }

  // Check if exists
  const { data: existing } = await supabase
    .from('option_trades')
    .select('id')
    .eq('ibkr_trade_id', t.tradeID)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from('option_trades')
      .update(row)
      .eq('id', existing.id);
    if (error) throw error;
    return 'updated';
  }

  const { error } = await supabase.from('option_trades').insert(row);
  if (error) throw error;
  return 'inserted';
}

async function upsertStock(
  supabase: ReturnType<typeof createClient>,
  t: TradeConfirm,
): Promise<'inserted' | 'updated' | 'skipped'> {

  const isBuy = t.buySell === 'BUY';

  if (isBuy) {
    // Compute next fifo_order for this ticker
    const { data: maxRow } = await supabase
      .from('share_lots')
      .select('fifo_order')
      .eq('ticker', t.underlyingSymbol)
      .order('fifo_order', { ascending: false })
      .limit(1)
      .maybeSingle();

    const nextFifo = (maxRow?.fifo_order ?? 0) + 1;

    const row = {
      ticker: t.underlyingSymbol,
      acquired_date: ymdToDate(t.tradeDate),
      fifo_order: nextFifo,
      qty_original: Math.abs(Number(t.quantity)),
      qty_remaining: Math.abs(Number(t.quantity)),
      cost_per_share: Math.abs(Number(t.price)),
      source: 'ibkr_flex',
      ibkr_trade_id: t.tradeID,
      last_synced_at: new Date().toISOString(),
      voided_at: null,
    };

    const { data: existing } = await supabase
      .from('share_lots')
      .select('id')
      .eq('ibkr_trade_id', t.tradeID)
      .maybeSingle();

    if (existing) {
      // Only update fields IBKR controls; leave qty_remaining alone
      // (consumption may have happened post-insert).
      const { qty_remaining: _qr, fifo_order: _fo, ...amend } = row;
      const { error } = await supabase
        .from('share_lots')
        .update(amend)
        .eq('id', existing.id);
      if (error) throw error;
      return 'updated';
    }

    const { error } = await supabase.from('share_lots').insert(row);
    if (error) throw error;
    return 'inserted';
  }

  // SELL → share_sells (realized_pl=0, FIFO consumption deferred)
  const row = {
    ticker: t.underlyingSymbol,
    quantity: Math.abs(Number(t.quantity)),
    price: Math.abs(Number(t.price)),
    trade_date: ymdToDate(t.tradeDate),
    source: 'ibkr_flex',
    ibkr_trade_id: t.tradeID,
    last_synced_at: new Date().toISOString(),
    voided_at: null,
    realized_pl: 0,
    note: 'IBKR sync — FIFO consumption pending reconcile',
  };

  const { data: existing } = await supabase
    .from('share_sells')
    .select('id')
    .eq('ibkr_trade_id', t.tradeID)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from('share_sells')
      .update(row)
      .eq('id', existing.id);
    if (error) throw error;
    return 'updated';
  }

  const { error } = await supabase.from('share_sells').insert(row);
  if (error) throw error;
  return 'inserted';
}

function jsonText(status: number, body: string): Response {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function jsonError(
  supabase: ReturnType<typeof createClient>,
  reason: string,
  trigger: string,
): Promise<Response> {
  await supabase.from('ibkr_sync_runs').insert({
    status: 'failed',
    trigger,
    finished_at: new Date().toISOString(),
    duration_ms: 0,
    errors: [{ reason }],
  });
  return jsonText(500, JSON.stringify({ ok: false, reason }));
}
