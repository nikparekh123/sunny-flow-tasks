/**
 * bnf-refresh-flags — re-pull the three risk flags for the user's existing
 * candidate rows without re-running the full universe scan.
 *
 * Reads current bnf_candidates rows for the calling user, fetches SEC
 * EDGAR (8-K + Form 4) and Yahoo (earnings date) for each ticker, and
 * updates the three flag columns + days_since_earnings + days_to_earnings.
 * Leaves SMA / dev / options data untouched.
 *
 * Useful when the user has a stale scan from this morning and wants to
 * refresh the risk panel without burning the full Polygon budget.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  cikFor, fetchRecentFilings, extract8Ks, fetchInsiderActivity,
  daysSinceFromTradingDays,
  type Item8K, type InsiderActivity,
} from '../bnf-scan/edgar.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Yahoo lookup duplicated lean here so we don't drag the whole bnf-scan
// file in. Only need the earnings date (name is already on the row).
async function fetchEarningsDays(ticker: string): Promise<number | null> {
  try {
    const url = `https://query1.finance.yahoo.com/v10/finance/quoteSummary/${ticker}?modules=calendarEvents`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; BNFScanner/1.0)' },
    });
    if (!res.ok) return null;
    const j = await res.json() as {
      quoteSummary?: { result?: Array<{ calendarEvents?: { earnings?: { earningsDate?: Array<{ raw?: number }> } } }> };
    };
    const raw = j?.quoteSummary?.result?.[0]?.calendarEvents?.earnings?.earningsDate?.[0]?.raw;
    if (typeof raw !== 'number') return null;
    return Math.round(((raw * 1000 - Date.now()) / 86400000) * 5 / 7);
  } catch {
    return null;
  }
}

async function fetchEdgarFlags(ticker: string): Promise<{ insider: InsiderActivity; eightKs: Item8K[] }> {
  const cik = await cikFor(ticker);
  if (!cik) return { insider: { sellers_count: 0, total_sold_usd: 0, details: [] }, eightKs: [] };
  const filings = await fetchRecentFilings(cik);
  const eightKs = extract8Ks(filings, 14, cik);
  const insider = await fetchInsiderActivity(cik, filings, 14);
  return { insider, eightKs };
}

async function inChunks<T, U>(items: T[], size: number, fn: (item: T) => Promise<U>): Promise<U[]> {
  const out: U[] = [];
  for (let i = 0; i < items.length; i += size) {
    const slice = items.slice(i, i + size);
    out.push(...await Promise.all(slice.map(fn)));
  }
  return out;
}

function jsonErr(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return jsonErr('Supabase env not configured', 500);

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonErr('Missing Authorization header', 401);

    const userClient = createClient(supabaseUrl, serviceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return jsonErr('Unauthorized', 401);
    const userId = userData.user.id;

    const admin = createClient(supabaseUrl, serviceKey);

    const { data: rows, error: readErr } = await admin
      .from('bnf_candidates')
      .select('id, ticker')
      .eq('user_id', userId);
    if (readErr) return jsonErr(`Read failed: ${readErr.message}`, 500);
    if (!rows || rows.length === 0) return new Response(
      JSON.stringify({ refreshed: 0, message: 'No candidates to refresh' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

    type Row = { id: string; ticker: string };
    const updates = await inChunks(rows as Row[], 5, async (r) => {
      const [edgar, daysToEarnings] = await Promise.all([
        fetchEdgarFlags(r.ticker).catch(() => ({
          insider: { sellers_count: 0, total_sold_usd: 0, details: [] } as InsiderActivity,
          eightKs: [] as Item8K[],
        })),
        fetchEarningsDays(r.ticker).catch(() => null),
      ]);
      return { id: r.id, edgar, daysToEarnings };
    });

    // One update per row. Could batch with upsert but list is small (≤100).
    let updated = 0;
    for (const u of updates) {
      const { error } = await admin
        .from('bnf_candidates')
        .update({
          insider_sales: u.edgar.insider.sellers_count > 0 ? u.edgar.insider : null,
          recent_8ks: u.edgar.eightKs.length > 0 ? u.edgar.eightKs : null,
          days_to_earnings: u.daysToEarnings,
          days_since_earnings: daysSinceFromTradingDays(u.daysToEarnings),
        })
        .eq('id', u.id);
      if (!error) updated++;
    }

    return new Response(
      JSON.stringify({ refreshed: updated, total: rows.length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return jsonErr((e as Error).message, 500);
  }
});
