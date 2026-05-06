/**
 * sync-snowball-fundamentals — pull reference data + TTM financials from
 * Polygon for every ticker in `public.snowball` and overlay them onto the
 * stored row. Recomputes intrinsic value (and TBPs) from the analyst's
 * existing assumptions × API-fetched fundamentals.
 *
 * Slow (4 endpoints × 524 tickers) but only needed weekly since
 * fundamentals don't change daily. Schedule via Supabase Cron at e.g.
 * "0 13 * * 0" (Sundays 9 AM ET).
 *
 * Required Supabase secrets:
 *   POLYGON_API_KEY
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface FinResp {
  results?: {
    financials?: {
      cash_flow_statement?: {
        net_cash_flow_from_operating_activities?: { value?: number };
        net_cash_flow_from_investing_activities?: { value?: number };
        // For EBITDA: D&A is typically buried here (not always present).
        depreciation_and_amortization?: { value?: number };
      };
      income_statement?: {
        diluted_average_shares?: { value?: number };
        basic_average_shares?: { value?: number };
        revenues?: { value?: number };
        net_income_loss?: { value?: number };
        net_income_loss_attributable_to_parent?: { value?: number };
        diluted_earnings_per_share?: { value?: number };
        basic_earnings_per_share?: { value?: number };
        operating_income_loss?: { value?: number };
        // Some filings expose D&A here too.
        depreciation_and_amortization?: { value?: number };
      };
      balance_sheet?: {
        long_term_debt?: { value?: number };
        // Cash + equivalents not always broken out — use current assets'
        // first slot or fall back.
        cash_and_cash_equivalents_at_carrying_value?: { value?: number };
      };
    };
  }[];
}

interface TickerRefResp {
  results?: {
    name?: string;
    sic_description?: string;
    weighted_shares_outstanding?: number;
  };
}

interface ExistingRow {
  ticker: string;
  stage1_growth_pct: number | null;
  discount_rate_pct: number | null;
  terminal_growth_pct: number | null;
  sector: string | null;
}

/**
 * For financial-sector tickers (banks, insurers), Polygon's "investing
 * activities" line includes loans + securities portfolios, which makes
 * Owner Earnings come out hugely negative when computed as CFO + investing.
 * For these, use Net Income as the owner-earnings proxy instead — that's
 * Buffett's recommended approach for financials.
 */
function isFinancialSector(sector: string | null | undefined): boolean {
  if (!sector) return false;
  const s = sector.toLowerCase();
  return s.includes("financ") || s.includes("bank") || s.includes("insur");
}

// Two-stage DCF (mirrors the client-side `dcfIntrinsic`).
function dcfIntrinsic(
  oe: number,
  shares: number,
  g: number,
  d: number,
  tg: number,
): number | null {
  if (!shares || shares <= 0) return null;
  if (d <= tg) return null;
  let pv = 0;
  let fcf = oe;
  for (let y = 1; y <= 10; y++) {
    fcf = fcf * (1 + g);
    pv += fcf / Math.pow(1 + d, y);
  }
  const tv = (fcf * (1 + tg)) / (d - tg);
  pv += tv / Math.pow(1 + d, 10);
  return pv / shares;
}

async function fetchFinancials(ticker: string, apiKey: string) {
  const url = new URL("https://api.polygon.io/vX/reference/financials");
  url.searchParams.set("ticker", ticker);
  url.searchParams.set("timeframe", "ttm");
  url.searchParams.set("limit", "1");
  url.searchParams.set("apiKey", apiKey);
  const r = await fetch(url.toString());
  if (!r.ok) return null;
  return (await r.json()) as FinResp;
}

async function fetchReference(ticker: string, apiKey: string) {
  const url = new URL(
    `https://api.polygon.io/v3/reference/tickers/${encodeURIComponent(ticker)}`,
  );
  url.searchParams.set("apiKey", apiKey);
  const r = await fetch(url.toString());
  if (!r.ok) return null;
  return (await r.json()) as TickerRefResp;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const polygonKey = Deno.env.get("POLYGON_API_KEY");
    if (!polygonKey) throw new Error("POLYGON_API_KEY not set");

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) Read all tickers and their existing assumptions + sector.
    const { data: rows, error: readErr } = await admin
      .from("snowball")
      .select(
        "ticker, stage1_growth_pct, discount_rate_pct, terminal_growth_pct, sector",
      );
    if (readErr) throw readErr;
    const tickers = (rows ?? []) as ExistingRow[];

    // 2) For each, fetch reference + financials in parallel (8 concurrent).
    const queue = [...tickers];
    let updated = 0;
    const missing: string[] = [];

    async function worker() {
      while (queue.length > 0) {
        const row = queue.shift()!;
        const t = row.ticker.toUpperCase();
        try {
          const [refResp, finResp] = await Promise.all([
            fetchReference(t, polygonKey!),
            fetchFinancials(t, polygonKey!),
          ]);

          const ref = refResp?.results;
          const fin = finResp?.results?.[0]?.financials;
          const cfo =
            fin?.cash_flow_statement?.net_cash_flow_from_operating_activities
              ?.value ?? null;
          const inv =
            fin?.cash_flow_statement?.net_cash_flow_from_investing_activities
              ?.value ?? null;
          const netIncome =
            fin?.income_statement?.net_income_loss_attributable_to_parent
              ?.value ??
            fin?.income_statement?.net_income_loss?.value ??
            null;

          // Reference's weighted_shares_outstanding is the current actual
          // share count. Polygon's TTM `diluted_average_shares` is unreliable
          // (sums quarters instead of averaging for some tickers, e.g. AAPL
          // returns ~3× the real number). Always prefer reference.
          const apiShares =
            ref?.weighted_shares_outstanding ??
            fin?.income_statement?.diluted_average_shares?.value ??
            fin?.income_statement?.basic_average_shares?.value ??
            null;

          // Owner earnings — branch by sector. Banks/insurers report huge
          // "investing activities" (loans, securities portfolios) that
          // aren't real CapEx, so CFO + investing comes out wildly negative
          // for them. For financials, use Net Income directly — Buffett's
          // recommended approach.
          let oe: number | null;
          if (isFinancialSector(row.sector)) {
            oe = netIncome != null ? netIncome / 1_000_000 : null;
          } else {
            oe =
              cfo != null && inv != null ? (cfo + inv) / 1_000_000 : null;
          }

          // ── Additional inputs for P/E and EV/EBITDA lenses ────────────
          const eps =
            fin?.income_statement?.diluted_earnings_per_share?.value ??
            fin?.income_statement?.basic_earnings_per_share?.value ??
            null;

          // EBITDA ≈ Operating income + D&A. Polygon doesn't always report
          // D&A; if missing, fall back to operating income (a downward bias
          // — undercounts EBITDA, conservative).
          const opIncome =
            fin?.income_statement?.operating_income_loss?.value ?? null;
          const da =
            fin?.income_statement?.depreciation_and_amortization?.value ??
            fin?.cash_flow_statement?.depreciation_and_amortization?.value ??
            0;
          const ebitda =
            opIncome != null ? (opIncome + (da ?? 0)) / 1_000_000 : null;

          // Net debt = total debt − cash; both for the EV → equity bridge.
          const debtRaw = fin?.balance_sheet?.long_term_debt?.value ?? null;
          const cashRaw =
            fin?.balance_sheet?.cash_and_cash_equivalents_at_carrying_value
              ?.value ?? null;
          const debt = debtRaw != null ? debtRaw / 1_000_000 : null;
          const cash = cashRaw != null ? cashRaw / 1_000_000 : null;
          // Shares are reported in raw count; CSV uses millions.
          const sharesMm =
            apiShares != null ? apiShares / 1_000_000 : null;

          const patch: Record<string, unknown> = {};
          if (ref?.name) patch.name = ref.name;
          if (ref?.sic_description) patch.industry = ref.sic_description;
          if (oe != null) patch.total_owner_earnings = oe;
          if (sharesMm != null) patch.shares_outstanding = sharesMm;
          if (eps != null) patch.eps_ttm = eps;
          if (ebitda != null) patch.ebitda_ttm = ebitda;
          if (debt != null) patch.total_debt = debt;
          if (cash != null) patch.cash_and_equivalents = cash;

          // If we have all the inputs, recompute intrinsic + TBPs from the
          // analyst's existing assumptions.
          const g = row.stage1_growth_pct;
          const d = row.discount_rate_pct;
          const tg = row.terminal_growth_pct;
          if (
            oe != null &&
            sharesMm != null &&
            g != null &&
            d != null &&
            tg != null
          ) {
            const intrinsic = dcfIntrinsic(
              oe,
              sharesMm,
              g / 100,
              d / 100,
              tg / 100,
            );
            if (intrinsic != null) {
              patch.intrinsic_value = intrinsic;
              patch.tbp_aggressive_15 = intrinsic * 0.85;
              patch.tbp_conservative_30 = intrinsic * 0.7;
              patch.tbp_deep_value_50 = intrinsic * 0.5;
            }
          }

          if (Object.keys(patch).length === 0) {
            missing.push(t);
            continue;
          }

          const { error: upErr } = await admin
            .from("snowball")
            .update(patch)
            .eq("ticker", t);
          if (upErr) {
            missing.push(`${t} (${upErr.message})`);
          } else {
            updated++;
          }
        } catch (e) {
          missing.push(`${t} (${(e as Error).message})`);
        }
      }
    }

    const concurrency = 8;
    await Promise.all(Array.from({ length: concurrency }, worker));

    return new Response(
      JSON.stringify({
        updated,
        total: tickers.length,
        missing: missing.slice(0, 20),
        missing_count: missing.length,
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message || "Server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
