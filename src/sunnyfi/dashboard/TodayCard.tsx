/**
 * Dashboard TODAY card.
 *
 * Up to five fat color-coded rows surfacing what needs attention in
 * the next ~8 hours. Each row is a single sentence + a sub-line.
 * Empty when nothing demands action — the card shrinks gracefully.
 *
 * Data:
 *   • option_trades — to detect live options expiring today + this week
 *   • bnf_candidates — for next-earnings dates on held tickers
 *
 * We do NOT receive open option marks here; "premium decay today" is
 * the sum of premium collected on short legs that expire today (i.e.
 * what becomes pure realized P&L if those legs end OTM).
 */
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useMemo } from "react";

interface OptionTradeRow {
  id: string;
  ticker: string;
  trade_date: string;
  action: "open" | "close";
  option_type: "call" | "put";
  direction: "short" | "long";
  contracts: number;
  strike: number;
  premium: number;
  expiry: string;
  closes_trade_id: string | null;
}

interface PositionRow {
  ticker: string;
}

interface BnfCandidateRow {
  ticker: string;
  days_to_earnings: number | null;
}

type RowTone = "alert" | "income" | "warn" | "info";

interface AttentionRow {
  tone: RowTone;
  headline: string;
  sub: string;
}

const todayIsoUtc = () => new Date().toISOString().slice(0, 10);

function useTradesForUser() {
  return useQuery({
    queryKey: ["dash_today_trades"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("*")
        .returns<OptionTradeRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

function usePositions() {
  return useQuery({
    queryKey: ["dash_today_positions"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker")
        .returns<PositionRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

function useBnfCandidates() {
  return useQuery({
    queryKey: ["dash_today_bnf"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bnf_candidates" as never)
        .select("ticker, days_to_earnings")
        .returns<BnfCandidateRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 10 * 60 * 1000,
  });
}

/** Compute remaining-open contracts per trade id. An OPEN is still
 *  live when its associated CLOSEs (by closes_trade_id) sum to less
 *  than the open's contracts. */
function buildLiveOpens(trades: OptionTradeRow[]): Array<OptionTradeRow & { remaining: number }> {
  const closedQty = new Map<string, number>();
  for (const t of trades) {
    if (t.action === "close" && t.closes_trade_id) {
      closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
    }
  }
  return trades
    .filter((t) => t.action === "open")
    .map((t) => ({ ...t, remaining: t.contracts - (closedQty.get(t.id) ?? 0) }))
    .filter((t) => t.remaining > 0);
}

export function TodayCard() {
  const { data: trades = [] } = useTradesForUser();
  const { data: positions = [] } = usePositions();
  const { data: bnf = [] } = useBnfCandidates();

  const rows = useMemo<AttentionRow[]>(() => {
    const today = todayIsoUtc();
    const lives = buildLiveOpens(trades);

    // ── 1. Expiries today ───────────────────────────────────────
    const expiringToday = lives.filter((t) => t.expiry === today);
    const todayShortPremium = expiringToday
      .filter((t) => t.direction === "short")
      .reduce((s, t) => s + t.remaining * 100 * t.premium, 0);

    // ── 2. Expiries this week ───────────────────────────────────
    const weekEnd = new Date();
    weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);
    const weekEndIso = weekEnd.toISOString().slice(0, 10);
    const expiringThisWeek = lives.filter(
      (t) => t.expiry > today && t.expiry <= weekEndIso,
    );

    // ── 3. Earnings inside held positions (next 7 days) ─────────
    const heldTickers = new Set(positions.map((p) => p.ticker));
    const earningsSoon = bnf.filter(
      (b) =>
        heldTickers.has(b.ticker) &&
        b.days_to_earnings != null &&
        b.days_to_earnings >= 0 &&
        b.days_to_earnings <= 5,
    );

    const out: AttentionRow[] = [];

    if (expiringToday.length > 0) {
      const tickers = expiringToday
        .slice(0, 3)
        .map((t) => `${t.ticker} ${t.option_type === "call" ? "C" : "P"}${t.strike}`)
        .join(" · ");
      const more = expiringToday.length > 3 ? ` +${expiringToday.length - 3} more` : "";
      out.push({
        tone: "alert",
        headline: `${expiringToday.length} option${expiringToday.length === 1 ? "" : "s"} expire today`,
        sub: tickers + more,
      });
    }

    if (todayShortPremium > 0) {
      out.push({
        tone: "income",
        headline: `$${Math.round(todayShortPremium).toLocaleString()} premium settles today`,
        sub: "if held to expiry · short legs expiring",
      });
    }

    if (earningsSoon.length > 0) {
      const top = earningsSoon[0];
      const others = earningsSoon.length - 1;
      out.push({
        tone: "warn",
        headline: `${earningsSoon.length} earnings in held positions`,
        sub: `next: ${top.ticker} in ${top.days_to_earnings}d${others > 0 ? ` · +${others} more` : ""}`,
      });
    }

    if (expiringThisWeek.length > 0) {
      out.push({
        tone: "info",
        headline: `${expiringThisWeek.length} more expir${expiringThisWeek.length === 1 ? "y" : "ies"} this week`,
        sub: `next: ${expiringThisWeek[0].ticker} ${expiringThisWeek[0].option_type === "call" ? "C" : "P"}${expiringThisWeek[0].strike} · ${expiringThisWeek[0].expiry}`,
      });
    }

    return out.slice(0, 5);
  }, [trades, positions, bnf]);

  return (
    <section className="dash2-card dash2-span-4">
      <div className="dash2-card-head">
        <span className="dash2-card-title">Today</span>
      </div>
      <div className="dash2-card-body">
        {rows.length === 0 ? (
          <div className="dash2-today-clear">
            <div className="dash2-today-clear-num">0</div>
            <div className="dash2-today-clear-lbl">items today</div>
            <div className="dash2-today-clear-sub">quiet — nothing demanding action</div>
          </div>
        ) : (
          <ul className="dash2-today-list">
            {rows.map((r, i) => (
              <li key={i} className={`dash2-today-row tone-${r.tone}`}>
                <div className="dash2-today-row-headline">{r.headline}</div>
                <div className="dash2-today-row-sub">{r.sub}</div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
