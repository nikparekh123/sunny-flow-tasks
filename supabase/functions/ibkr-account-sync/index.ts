/**
 * ibkr-account-sync — the account itself, once a morning, from IBKR's
 * Activity Flex query "Sunny account" (ID 1670350, created by Nik 12 Oct 2026):
 * NAV in Base, Change in NAV, Cash Report, Interest Accruals and Open
 * Positions for the last 30 calendar days, broken out by day.
 *
 * Writes one row per account per trading day into `account_daily` and every
 * position at that day's close into `account_positions_daily`. Upserts, so a
 * run repeats safely and each run re-covers 30 days (a missed morning heals).
 *
 * ⚠ TWO ACCOUNTS, ONE BOOK. Every trade is in the main account (...1475); the
 * second (...9479) holds only a cash balance of about -$672K, an IBKR split
 * they cannot fix. Neither account is the account on its own:
 * `account_value_daily` adds them ($96,615 at the 9 Oct close). Interest too
 * is only ever the NET: on 9 Oct ...1475 earned $79.93 on its +$586K cash and
 * ...9479 was charged $92.53, so the book paid $12.60 that day. Never quote
 * one account's interest (Nik corrected exactly that, 12 Oct 2026).
 *
 * ⚠ T+1. Daily Flex covers closed days only. The live figure through the day
 * is this close plus today's moves, worked out by the Home payload.
 *
 * Body: { dry_run?: true } parses and returns the summary without writing.
 */
const IBKR_BASE = 'https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService';
const IBKR_GET_BASE = 'https://gdcdyn.interactivebrokers.com/AccountManagement/FlexWebService';
const QUERY_ID = '1670350';
const BUILD = '2026-10-12.1';

function matchTag(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<${tag}>([^<]+)</${tag}>`));
  return m ? m[1] : null;
}
function attrs(s: string): Record<string, string> {
  const o: Record<string, string> = {};
  for (const m of s.matchAll(/(\w+)="([^"]*)"/g)) o[m[1]] = m[2];
  return o;
}
function rows(block: string, tag: string): Record<string, string>[] {
  return [...block.matchAll(new RegExp(`<${tag}\\s([^>]*?)/?>`, 'g'))].map((m) => attrs(m[1]));
}
const num = (v?: string) => (v === undefined || v === '' ? null : Number(v));
const iso = (d?: string) => (d && /^\d{8}$/.test(d) ? `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}` : null);

async function fetchReport(token: string, q: string): Promise<string> {
  const send = await (await fetch(`${IBKR_BASE}/SendRequest?t=${token}&q=${q}&v=3`)).text();
  const ref = matchTag(send, 'ReferenceCode');
  if (matchTag(send, 'Status') !== 'Success' || !ref) throw new Error(`SendRequest: ${send.slice(0, 300)}`);
  let xml = '';
  for (let i = 0; i < 15; i++) {
    xml = await (await fetch(`${IBKR_GET_BASE}/GetStatement?q=${ref}&t=${token}&v=3`)).text();
    if (!xml.includes('Statement generation in progress')) break;
    await new Promise((r) => setTimeout(r, 3000));
  }
  if (xml.includes('Statement generation in progress')) throw new Error('report still generating after 45s');
  if (!xml.includes('<FlexStatement ')) throw new Error(`GetStatement: ${xml.slice(0, 300)}`);
  return xml;
}

Deno.serve(async (req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  let body: { dry_run?: boolean } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is fine */ }
  try {
    const xml = await fetchReport(Deno.env.get('IBKR_FLEX_TOKEN')!, QUERY_ID);

    const days: Record<string, unknown>[] = [];
    const positions: Record<string, unknown>[] = [];
    for (const m of xml.matchAll(/<FlexStatement\s([^>]*)>([\s\S]*?)<\/FlexStatement>/g)) {
      const st = attrs(m[1]);
      const block = m[2];
      const acct = st.accountId;
      const date = iso(st.toDate);
      if (!acct || !date) continue;
      /* Broken out by day, each statement carries the day before and the day
         itself; the row dated toDate is that day's close. */
      const eq = rows(block, 'EquitySummaryByReportDateInBase').find((r) => r.reportDate === st.toDate);
      if (!eq || eq.total === undefined) continue;
      const nav = rows(block, 'ChangeInNAV')[0] ?? {};
      const cash = rows(block, 'CashReportCurrency').find((r) => r.currency === 'BASE_SUMMARY') ?? {};
      const acc = rows(block, 'InterestAccrualsCurrency').find((r) => r.currency === 'BASE_SUMMARY') ?? {};
      days.push({
        account_id: acct, report_date: date,
        nav: num(eq.total), cash: num(eq.cash), stock: num(eq.stock), options: num(eq.options),
        interest_accruals: num(eq.interestAccruals),
        starting_value: num(nav.startingValue), mtm: num(nav.mtm), realized: num(nav.realized),
        change_in_unrealized: num(nav.changeInUnrealized),
        deposits_withdrawals: num(nav.depositsWithdrawals), dividends: num(nav.dividends),
        interest: num(nav.interest), change_in_interest_accruals: num(nav.changeInInterestAccruals),
        commissions: num(nav.commissions), other_fees: num(nav.otherFees), twr: num(nav.twr),
        interest_accrued: num(acc.interestAccrued),
        commissions_mtd: num(cash.commissionsMTD), broker_interest_mtd: num(cash.brokerInterestMTD),
        other_fees_mtd: num(cash.otherFeesMTD),
        synced_at: new Date().toISOString(),
      });
      for (const p of rows(block, 'OpenPosition')) {
        if (p.levelOfDetail && p.levelOfDetail !== 'SUMMARY') continue;
        if (p.reportDate !== st.toDate || !p.conid) continue;
        positions.push({
          account_id: acct, report_date: date, conid: p.conid,
          symbol: p.symbol ?? null, underlying: p.underlyingSymbol ?? null,
          asset_category: p.assetCategory ?? null, put_call: p.putCall || null,
          strike: num(p.strike), expiry: iso(p.expiry), multiplier: num(p.multiplier),
          position: num(p.position), mark_price: num(p.markPrice), position_value: num(p.positionValue),
          cost_basis_money: num(p.costBasisMoney), fifo_pnl_unrealized: num(p.fifoPnlUnrealized),
          synced_at: new Date().toISOString(),
        });
      }
    }
    if (!days.length) throw new Error('report parsed to no days');

    /* What the app will show: both accounts added, per day. */
    const byDate = new Map<string, { nav: number; n: number }>();
    for (const d of days) {
      const k = String(d.report_date);
      const v = byDate.get(k) ?? { nav: 0, n: 0 };
      v.nav += Number(d.nav); v.n += 1; byDate.set(k, v);
    }
    const dates = [...byDate.keys()].sort();
    const last = dates[dates.length - 1];
    const summary = {
      accounts: [...new Set(days.map((d) => `...${String(d.account_id).slice(-4)}`))],
      days: dates.length, from: dates[0], to: last,
      last_close_value: Math.round(byDate.get(last)!.nav * 100) / 100,
      last_close_accounts: byDate.get(last)!.n,
      positions_at_last_close: positions.filter((p) => p.report_date === last).length,
    };

    if (body.dry_run) return new Response(JSON.stringify({ ok: true, build: BUILD, dry_run: true, summary }),
      { headers: { 'Content-Type': 'application/json' } });

    for (const [table, conflict, data] of [
      ['account_daily', 'account_id,report_date', days],
      ['account_positions_daily', 'account_id,report_date,conid', positions],
    ] as const) {
      for (let i = 0; i < data.length; i += 500) {
        const r = await fetch(`${url}/rest/v1/${table}?on_conflict=${conflict}`, {
          method: 'POST',
          headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify(data.slice(i, i + 500)),
        });
        if (!r.ok) throw new Error(`${table} ${r.status} ${(await r.text()).slice(0, 200)}`);
      }
    }

    /* Stamped last, on the success path only. */
    await fetch(`${url}/rest/v1/sync_heartbeat?on_conflict=feed`, {
      method: 'POST',
      headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify([{
        feed: 'ibkr-account-sync', ran_at: new Date().toISOString(), rows_written: days.length,
        detail: `${summary.accounts.length} accounts · ${summary.days} days to ${last} · close ${summary.last_close_value}`,
      }]),
    });

    return new Response(JSON.stringify({ ok: true, build: BUILD, summary }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
