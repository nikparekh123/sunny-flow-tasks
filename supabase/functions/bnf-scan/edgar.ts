/**
 * SEC EDGAR helpers for the BNF scanner risk flags.
 *
 * Three jobs:
 *   - cik(ticker)               → 10-digit CIK string (via cached company_tickers.json)
 *   - fetchRecentFilings(cik)   → recent filings list from submissions endpoint
 *   - extract8Ks(filings, days) → list of recent 8-Ks with parsed item numbers
 *   - fetchInsiderActivity(cik) → sums Form 4 sales in last 14 cal days
 *
 * Rate-limit etiquette: SEC requires a User-Agent that identifies you AND
 * limits requests to ≤10/sec. All requests go through `secFetch()` which
 * sets the UA. Caller code (bnf-scan / bnf-refresh-flags) is responsible
 * for chunked parallelism to stay under the rate cap.
 */

// SEC requires a contact in the User-Agent. Replace with a real address
// before production; the API will reject blank or generic UAs.
const SEC_UA = 'BNFScanner/1.0 (sunnyfi-strategy@example.com)';

function secFetch(url: string): Promise<Response> {
  return fetch(url, {
    headers: { 'User-Agent': SEC_UA, 'Accept': 'application/json' },
  });
}

// ── CIK lookup ───────────────────────────────────────────────────
// SEC publishes a master ticker→CIK map at /files/company_tickers.json
// (~5MB). We fetch once per cold start and memoise in-process. Cold start
// per edge invocation is fine — the map is stable day-to-day.
let _cikMap: Record<string, string> | null = null;
let _cikMapPromise: Promise<Record<string, string>> | null = null;

export async function loadCikMap(): Promise<Record<string, string>> {
  if (_cikMap) return _cikMap;
  if (_cikMapPromise) return _cikMapPromise;
  _cikMapPromise = (async () => {
    const res = await secFetch('https://www.sec.gov/files/company_tickers.json');
    if (!res.ok) return {};
    const j = await res.json() as Record<string, { cik_str: number; ticker: string; title: string }>;
    const m: Record<string, string> = {};
    for (const k of Object.keys(j)) {
      const e = j[k];
      m[e.ticker.toUpperCase()] = String(e.cik_str).padStart(10, '0');
    }
    _cikMap = m;
    return m;
  })();
  return _cikMapPromise;
}

export async function cikFor(ticker: string): Promise<string | null> {
  const map = await loadCikMap();
  return map[ticker.toUpperCase()] ?? null;
}

// ── Recent filings ───────────────────────────────────────────────
export interface SubmissionFiling {
  accessionNumber: string;
  filingDate: string;          // ISO YYYY-MM-DD
  form: string;                // e.g. '8-K', '4', '10-Q'
  primaryDocument: string;
  primaryDocDescription: string;
}

interface RecentBucket {
  accessionNumber: string[];
  filingDate: string[];
  form: string[];
  primaryDocument: string[];
  primaryDocDescription: string[];
}
interface SubmissionsResp {
  filings?: { recent?: RecentBucket };
}

export async function fetchRecentFilings(cik: string): Promise<SubmissionFiling[]> {
  const url = `https://data.sec.gov/submissions/CIK${cik}.json`;
  const res = await secFetch(url);
  if (!res.ok) return [];
  const j: SubmissionsResp = await res.json();
  const r = j?.filings?.recent;
  if (!r) return [];
  const n = r.accessionNumber.length;
  const out: SubmissionFiling[] = [];
  for (let i = 0; i < n; i++) {
    out.push({
      accessionNumber: r.accessionNumber[i],
      filingDate: r.filingDate[i],
      form: r.form[i],
      primaryDocument: r.primaryDocument[i],
      primaryDocDescription: r.primaryDocDescription[i] ?? '',
    });
  }
  return out;
}

// ── 8-K extraction ───────────────────────────────────────────────
export interface Item8K {
  date: string;
  items: string[];   // e.g. ['1.01', '2.02']
  url: string;
}

export function extract8Ks(filings: SubmissionFiling[], windowCalDays: number, cik: string): Item8K[] {
  const cutoffMs = Date.now() - windowCalDays * 86400000;
  const out: Item8K[] = [];
  const cikInt = parseInt(cik, 10);
  for (const f of filings) {
    if (f.form !== '8-K') continue;
    const dMs = new Date(f.filingDate + 'T00:00:00Z').getTime();
    if (dMs < cutoffMs) continue;
    // Item numbers live in the description, e.g. "Item 1.01, Item 2.02".
    // Defensive: dedupe and sort.
    const items = Array.from(new Set(
      (f.primaryDocDescription.match(/\d+\.\d+/g) ?? []).slice(0, 10),
    )).sort();
    const accClean = f.accessionNumber.replace(/-/g, '');
    const url = `https://www.sec.gov/Archives/edgar/data/${cikInt}/${accClean}/${f.primaryDocument}`;
    out.push({ date: f.filingDate, items, url });
  }
  return out;
}

// ── Form 4 (insider) parsing ─────────────────────────────────────
export interface InsiderDetail {
  name: string;
  role: string;
  date: string;
  usd: number;
}
export interface InsiderActivity {
  sellers_count: number;
  total_sold_usd: number;
  details: InsiderDetail[];
}

/** Quick regex-XPath. Form 4 XML is well-structured; full DOM parse would
 *  be cleaner but Deno doesn't bundle one. Each nonDerivativeTransaction
 *  block is self-contained, so we scan blocks and pull S-coded sales. */
function parseForm4Xml(xml: string, dateIso: string): InsiderDetail | null {
  const nameMatch = xml.match(/<rptOwnerName>([^<]+)<\/rptOwnerName>/);
  const officerTitleMatch = xml.match(/<officerTitle>([^<]+)<\/officerTitle>/);
  const isDirector = /<isDirector>1<\/isDirector>/.test(xml);
  const isOfficer = /<isOfficer>1<\/isOfficer>/.test(xml);
  const is10pct = /<isTenPercentOwner>1<\/isTenPercentOwner>/.test(xml);
  const name = nameMatch?.[1]?.trim() ?? 'Unknown';
  const role = officerTitleMatch?.[1]?.trim()
    ?? (isOfficer ? 'Officer'
    :   isDirector ? 'Director'
    :   is10pct    ? '10% owner'
    :   'Insider');

  let usd = 0;
  const blockRegex = /<nonDerivativeTransaction>([\s\S]*?)<\/nonDerivativeTransaction>/g;
  let m: RegExpExecArray | null;
  while ((m = blockRegex.exec(xml)) !== null) {
    const block = m[1];
    // S = open-market sale. Skip other codes (P=buy, A=grant, M=option exercise, etc.).
    if (!/<transactionCode>S<\/transactionCode>/.test(block)) continue;
    const sharesMatch = block.match(/<transactionShares>[\s\S]*?<value>([\d.]+)<\/value>/);
    const priceMatch  = block.match(/<transactionPricePerShare>[\s\S]*?<value>([\d.]+)<\/value>/);
    if (sharesMatch && priceMatch) {
      usd += parseFloat(sharesMatch[1]) * parseFloat(priceMatch[1]);
    }
  }
  if (usd <= 0) return null;
  return { name, role, date: dateIso, usd };
}

export async function fetchInsiderActivity(
  cik: string,
  filings: SubmissionFiling[],
  windowCalDays: number,
): Promise<InsiderActivity> {
  const cutoffMs = Date.now() - windowCalDays * 86400000;
  const recent4s = filings.filter((f) =>
    f.form === '4' && new Date(f.filingDate + 'T00:00:00Z').getTime() >= cutoffMs,
  );
  if (recent4s.length === 0) {
    return { sellers_count: 0, total_sold_usd: 0, details: [] };
  }

  const cikInt = parseInt(cik, 10);
  const details: InsiderDetail[] = [];
  const sellers = new Set<string>();
  let total = 0;

  // Sequential per filing to stay polite to SEC's rate cap. Caller is
  // already running multiple tickers in parallel; per-ticker fetches are
  // small (usually 1–3 Form 4s).
  for (const f of recent4s) {
    try {
      const accClean = f.accessionNumber.replace(/-/g, '');
      const xmlUrl = `https://www.sec.gov/Archives/edgar/data/${cikInt}/${accClean}/${f.primaryDocument}`;
      const res = await secFetch(xmlUrl);
      if (!res.ok) continue;
      const xml = await res.text();
      const parsed = parseForm4Xml(xml, f.filingDate);
      if (parsed) {
        sellers.add(parsed.name);
        total += parsed.usd;
        details.push(parsed);
      }
    } catch { /* skip this filing */ }
  }

  return {
    sellers_count: sellers.size,
    total_sold_usd: Math.round(total),   // cents-precision unnecessary
    details: details.sort((a, b) => b.usd - a.usd),
  };
}

// ── Days-since-earnings ──────────────────────────────────────────
/** Compute trading days since the most recent earnings date. Negative
 *  means "earnings was X days AGO". Returns null when nothing within 30 days. */
export function daysSinceFromTradingDays(daysToEarnings: number | null): number | null {
  // The Yahoo lookup we already do returns daysToEarnings as a SIGNED
  // trading-day count: negative = past (already reported), positive =
  // future. "Days since" only cares about the past case, ≤30d back.
  if (daysToEarnings == null) return null;
  if (daysToEarnings >= 0) return null;            // upcoming, not "since"
  const since = -daysToEarnings;
  if (since > 30) return null;                     // too far back to flag
  return since;
}
