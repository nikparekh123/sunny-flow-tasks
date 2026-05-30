/**
 * Pure compute: join the five DB sources into the `Company[]` shape the
 * Portfolio views (Table / Cards / Cockpit / Focus) already consume.
 *
 * Inputs (raw rows; this function does no IO):
 *   positions       — public.positions
 *   trades          — public.option_trades
 *   greeks          — public.option_greeks (PD-1)
 *   quotes          — public.ticker_quotes (PD-1)
 *   shareSells      — public.share_sells (for realized stock P&L)
 *   strategyByT     — Map<ticker, "income" | "invest" | "yield">
 *
 * The transform mirrors the sample-data shape in `./data.ts` (legLabel,
 * computeFlags, aggregate rollup) so the rendered views don't need to
 * change at all when PD-2 lands.
 *
 * Missing Greeks / quotes are NOT fatal — they fall back to nulls or
 * derived values so the page renders the moment the user uploads
 * positions, even before `mp-refresh` has been invoked.
 */
import type {
  Company, Leg, Aggregate, Flag, CompanyEvent,
} from "./data";

// ─── Raw row shapes from Supabase ───────────────────────────────
export interface PositionRow {
  ticker: string;
  name: string | null;
  sector: string | null;
  quantity: number;
  avg_cost: number;
  current_price: number | null;
  prev_close: number | null;
  status: "open" | "closed";
  earnings_date: string | null;
  realized_stock_pl: number | null;
}
export interface OptionTradeRow {
  id: string;
  ticker: string;
  trade_date: string;
  action: "open" | "close";
  option_type: "call" | "put";
  direction: "long" | "short";
  contracts: number;
  strike: number;
  premium: number;
  expiry: string;
  closes_trade_id: string | null;
}
export interface OptionGreeksRow {
  option_trade_id: string;
  delta: number | null;
  gamma: number | null;
  theta: number | null;
  vega: number | null;
  iv: number | null;
  open_interest: number | null;
  volume: number | null;
  last_mark: number | null;
}
export interface TickerQuoteRow {
  ticker: string;
  spot: number | null;
  day_change_pct: number | null;
  beta: number | null;
}
export interface ShareSellRow {
  ticker: string;
  realized_pl: number;
  trade_date: string;
}

// ─── Helpers ────────────────────────────────────────────────────
const STRAT_LABEL: Record<"income" | "invest" | "yield", Company["strat"]> = {
  income: "Income",
  invest: "Investment",
  yield: "Yield",
};

function daysUntil(iso: string, today: Date): number {
  const t = new Date(iso + "T00:00:00Z").getTime();
  const n = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate())).getTime();
  return Math.round((t - n) / 86_400_000);
}

function fmtMonthDay(iso: string): string {
  // "2026-06-19" → "Jun 19"
  const d = new Date(iso + "T00:00:00Z");
  const M = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${M[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

/** Walk opens + closes (closes_trade_id) → remaining contracts per open id.
 *  Mirrors atoms.ts remainingByOpenId + the same logic in mp-refresh. */
function remainingByOpenId(trades: OptionTradeRow[]): Map<string, number> {
  const opens = new Map<string, OptionTradeRow>();
  const closedQty = new Map<string, number>();
  for (const t of trades) {
    if (t.action === "open") opens.set(t.id, t);
    else if (t.action === "close" && t.closes_trade_id) {
      closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
    }
  }
  const out = new Map<string, number>();
  for (const [id, o] of opens) out.set(id, Math.max(0, o.contracts - (closedQty.get(id) ?? 0)));
  return out;
}

/** Flag computation — same rules as data.ts computeFlags but operates on
 *  the joined Company-in-progress (legs already mapped). */
function computeFlags(
  c: Omit<Company, "agg" | "flags" | "sev" | "optLegs">,
): Flag[] {
  const flags: Flag[] = [];
  c.legs.forEach((l) => {
    if (l.side === "short" && l.kind === "call" && l.dte != null && l.dte <= 21 && l.strike != null) {
      const moneyness = (c.spot - l.strike) / l.strike;
      const callDelta = Math.abs(l.delta / (Math.abs(l.qty) * 100));
      if (moneyness > -0.02) flags.push({ k: "assign", label: "assignment risk", tone: "neg" });
      if (callDelta >= 0.75) flags.push({ k: "delta", label: "Δ " + callDelta.toFixed(2) + " · roll", tone: "neg" });
    }
  });
  const hasShortOpt = c.legs.some((l) => l.side === "short" && (l.kind === "call" || l.kind === "put"));
  if (c.event.kind === "earnings" && c.event.days <= 7 && hasShortOpt) {
    flags.push({ k: "crush", label: "IV crush " + c.event.days + "d", tone: "warn" });
  }
  if (c.event.kind === "earnings" && c.event.days <= 14) {
    flags.push({ k: "earn", label: "earnings " + c.event.days + "d", tone: "warn" });
  }
  if (c.flags200) flags.push({ k: "below", label: "below 200d", tone: "neg" });
  if (Math.abs(c.day) >= 2.5) flags.push({ k: "move", label: "big move", tone: c.day > 0 ? "pos" : "neg" });
  const seen: Record<string, true> = {};
  return flags.filter((f) => (seen[f.k] ? false : (seen[f.k] = true)));
}

// ─── Main build ─────────────────────────────────────────────────
export interface BuildSources {
  positions: PositionRow[];
  trades: OptionTradeRow[];
  greeks: OptionGreeksRow[];
  quotes: TickerQuoteRow[];
  shareSells: ShareSellRow[];
  strategyByT: Map<string, "income" | "invest" | "yield">;
}

export function buildCompanies(src: BuildSources): Company[] {
  const today = new Date();
  const greekById = new Map(src.greeks.map((g) => [g.option_trade_id, g]));
  const quoteByT = new Map(src.quotes.map((q) => [q.ticker.toUpperCase(), q]));
  const remaining = remainingByOpenId(src.trades);

  // Realized share P&L per ticker (lifetime sum).
  const realizedSharesByT = new Map<string, number>();
  for (const s of src.shareSells) {
    realizedSharesByT.set(s.ticker, (realizedSharesByT.get(s.ticker) ?? 0) + s.realized_pl);
  }
  // Realized option P&L per ticker — pair closes with their opens.
  const tradeById = new Map(src.trades.map((t) => [t.id, t]));
  const realizedOptByT = new Map<string, number>();
  for (const c of src.trades) {
    if (c.action !== "close" || !c.closes_trade_id) continue;
    const o = tradeById.get(c.closes_trade_id);
    if (!o) continue;
    const perShare = o.direction === "short" ? o.premium - c.premium : c.premium - o.premium;
    const $ = perShare * c.contracts * 100;
    realizedOptByT.set(c.ticker, (realizedOptByT.get(c.ticker) ?? 0) + $);
  }

  // One Company per OPEN position (closed positions are filtered into
  // the page's `CLOSED` array elsewhere — TODO: expose a `closed`
  // companion list when the Show Closed filter needs DB data instead of
  // the sample CLOSED array).
  const companies: Company[] = [];
  const openPositions = src.positions.filter((p) => p.status === "open");

  // Group open option legs (remaining > 0) by ticker for fast lookup.
  const legsByT = new Map<string, OptionTradeRow[]>();
  for (const t of src.trades) {
    if (t.action !== "open") continue;
    if ((remaining.get(t.id) ?? 0) <= 0) continue;
    const list = legsByT.get(t.ticker.toUpperCase()) ?? [];
    list.push(t);
    legsByT.set(t.ticker.toUpperCase(), list);
  }
  // Also include tickers that have legs but no underlying position
  // (you might hold options on something you don't own outright).
  const allTickers = new Set([
    ...openPositions.map((p) => p.ticker.toUpperCase()),
    ...Array.from(legsByT.keys()),
  ]);

  for (const ticker of allTickers) {
    const pos = openPositions.find((p) => p.ticker.toUpperCase() === ticker);
    const quote = quoteByT.get(ticker);
    const spot = quote?.spot ?? pos?.current_price ?? pos?.avg_cost ?? 0;
    const day = quote?.day_change_pct ?? 0;
    const beta = quote?.beta ?? 1.0;

    // Event from earnings_date (if present).
    let event: CompanyEvent = { kind: "none", label: "—", date: "—", days: 999 };
    if (pos?.earnings_date) {
      const d = daysUntil(pos.earnings_date, today);
      if (d >= 0) event = { kind: "earnings", label: "Earnings", date: fmtMonthDay(pos.earnings_date), days: d };
    }

    const strat = STRAT_LABEL[src.strategyByT.get(ticker) ?? "income"] ?? "Income";

    // Build legs: stock (if held) + each open option.
    const legs: Leg[] = [];
    if (pos && pos.quantity > 0) {
      const last = quote?.spot ?? pos.current_price ?? pos.avg_cost;
      legs.push({
        kind: "stock",
        qty: pos.quantity,
        avg: pos.avg_cost,
        last,
        day,
        unreal: pos.quantity * (last - pos.avg_cost),
        real: pos.realized_stock_pl ?? 0,
        delta: pos.quantity, // 1 share = 1 delta
        gamma: 0, theta: 0, vega: 0,
      });
    }

    const tickerLegs = legsByT.get(ticker) ?? [];
    for (const t of tickerLegs) {
      const left = remaining.get(t.id) ?? 0;
      if (left <= 0) continue;
      const g = greekById.get(t.id);
      const sideSign = t.direction === "short" ? -1 : 1;
      // Per-position Greeks: per-share × contracts × 100 × side sign.
      const k = left * 100;
      const last = g?.last_mark ?? t.premium;
      // Unrealized for an open leg = entry premium kept (short) or
      // current value vs paid (long) — matches the sample data convention.
      const perShareDelta = t.direction === "short" ? t.premium - last : last - t.premium;
      const unreal = perShareDelta * left * 100;
      legs.push({
        kind: t.option_type,
        side: t.direction,
        qty: left * sideSign,        // negative for shorts (per the sample shape)
        avg: t.premium,
        last,
        unreal,
        real: 0,
        delta: (g?.delta ?? 0) * k * sideSign,
        gamma: (g?.gamma ?? 0) * k * sideSign,
        theta: (g?.theta ?? 0) * k * sideSign,
        vega:  (g?.vega  ?? 0) * k * sideSign,
        strike: t.strike,
        expiry: t.expiry,
        dte: Math.max(0, daysUntil(t.expiry, today)),
        iv: g?.iv != null ? g.iv * 100 : undefined,  // decimal → percent
        oi: g?.open_interest ?? undefined,
        vol: g?.volume ?? undefined,
      });
    }

    const skel: Omit<Company, "agg" | "flags" | "sev" | "optLegs"> = {
      t: ticker,
      name: pos?.name ?? ticker,
      sector: pos?.sector ?? "—",
      strat,
      spot,
      day,
      beta,
      event,
      legs,
    };
    const flags = computeFlags(skel);
    const sev = flags.reduce((s, f) => s + (f.tone === "neg" ? 3 : f.tone === "warn" ? 2 : 1), 0);

    const agg: Aggregate = legs.reduce<Aggregate>(
      (a, l) => ({
        delta: a.delta + l.delta,
        gamma: a.gamma + l.gamma,
        theta: a.theta + l.theta,
        vega:  a.vega  + l.vega,
        unreal: a.unreal + l.unreal,
        // Per-ticker realized = realized share PL + realized option PL
        // (added once below — keep accumulator clean here).
        real: 0,
        mv: a.mv + (l.kind === "stock" ? l.qty * l.last : 0),
        net: 0,
      }),
      { delta: 0, gamma: 0, theta: 0, vega: 0, unreal: 0, real: 0, mv: 0, net: 0 },
    );
    agg.real = (realizedSharesByT.get(ticker) ?? 0) + (realizedOptByT.get(ticker) ?? 0);
    agg.net = agg.unreal + agg.real;

    companies.push({
      ...skel,
      agg,
      flags,
      sev,
      optLegs: legs.filter((l) => l.kind !== "stock").length,
    });
  }

  return companies;
}

/** Portfolio rollup — sum the per-ticker aggregates. */
export interface PortfolioRollup {
  delta: number; gamma: number; theta: number; vega: number;
  unreal: number; real: number; net: number; mv: number;
  legs: number; opts: number; companies: number;
  maxAbsDelta: number;
  betaWeightedDelta: number;
}
export function buildPortfolio(companies: Company[]): PortfolioRollup {
  const p = companies.reduce(
    (a, c) => ({
      delta: a.delta + c.agg.delta,
      gamma: a.gamma + c.agg.gamma,
      theta: a.theta + c.agg.theta,
      vega:  a.vega  + c.agg.vega,
      unreal: a.unreal + c.agg.unreal,
      real:   a.real   + c.agg.real,
      mv:     a.mv     + c.agg.mv,
      legs:   a.legs + c.legs.length,
      opts:   a.opts + c.optLegs,
    }),
    { delta: 0, gamma: 0, theta: 0, vega: 0, unreal: 0, real: 0, mv: 0, legs: 0, opts: 0 },
  );
  const betaWeightedDelta = Math.round(
    companies.reduce((s, c) => s + c.agg.delta * (c.beta || 0), 0),
  );
  return {
    ...p,
    net: p.unreal + p.real,
    companies: companies.length,
    maxAbsDelta: companies.length ? Math.max(...companies.map((c) => Math.abs(c.agg.delta))) : 0,
    betaWeightedDelta,
  };
}
