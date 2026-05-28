/**
 * Dashboard content blocks — ported from the Claude design handoff.
 *
 * Each block is a self-contained section that renders its own header,
 * content, and footer. All visual data is HARDCODED in this commit;
 * subsequent CD-4 through CD-9 commits replace each block's sample data
 * with real queries.
 *
 * Original spec lives in /handoff 4/dashboard-blocks.jsx. Every styling
 * class is defined in dashboard.css under the .dash scope so blocks can
 * be rendered standalone (no extra setup beyond the .dash wrapper).
 *
 * Conventions:
 *   • Every block returns a plain <div> root (never React.Fragment) so
 *     it can carry data-* attributes the dev tooling might add.
 *   • Numbers use MoneyCount / PctCount for the count-up animation.
 *   • Section headers use <Section n="01">...</Section>.
 */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Spark, AnimatedBar, HairRow, Section } from "./atoms";
import { MoneyCount, PctCount, useEntered } from "./animation";
import { macroEventsOn } from "./macroCalendar";
import {
  buildRiskScenarios, loadLastReviewed, saveLastReviewed,
  type RiskPositionInput, type RiskOptionInput,
} from "./riskMath";
import { useState } from "react";

// ─────────────────── Brand bar ───────────────────────────────────

export function BrandBar({
  dateLabel, onPositions, onStrategy, onMath,
}: {
  dateLabel?: string;
  onPositions?: () => void;
  onStrategy?: () => void;
  onMath?: () => void;
}) {
  return (
    <div className="brandbar">
      <div className="mark">
        <span className="logo">◆ SUNNYFI</span>
        <span className="slash">/</span>
        <span className="route">Morning brief<span className="cursor" /></span>
      </div>
      <nav className="brandbar-nav">
        <a className="brandbar-nav-link" onClick={onPositions}>→ Positions</a>
        <a className="brandbar-nav-link" onClick={onStrategy}>→ Strategy</a>
        <a className="brandbar-nav-link" onClick={onMath}>→ Math</a>
      </nav>
      <div className="actions">
        {dateLabel && <span className="label">{dateLabel}</span>}
      </div>
    </div>
  );
}

// ─────────────────── Greeting ────────────────────────────────────

/** "Good morning, Niket." vs "MORNING, NIKET". Greeting word respects
 *  time of day (Morning / Afternoon / Evening / Late night). */
function greetingWord(hour: number): string {
  if (hour < 5)  return "late";
  if (hour < 12) return "morning";
  if (hour < 17) return "afternoon";
  if (hour < 21) return "evening";
  return "late";
}

export function Greeting({
  size = 128, bone = false, formal = false, name = "Niket", hour,
}: {
  size?: number; bone?: boolean; formal?: boolean; name?: string; hour?: number;
}) {
  const word = greetingWord(hour ?? new Date().getHours());
  if (formal) {
    // Formal greeting has its own floor so it stays legible when the
    // hero is dialled small (e.g. cockpit layout).
    const formalSize = Math.max(56, size * 0.72);
    // First-letter cap for the formal variant.
    const wordCap = word.charAt(0).toUpperCase() + word.slice(1);
    const prefix = word === "late" ? "Up late," : `Good ${wordCap.toLowerCase()},`;
    return (
      <div
        className={"greeting display " + (bone ? "bone" : "")}
        style={{ fontSize: formalSize, lineHeight: 0.95, fontWeight: 300, letterSpacing: "-.025em" }}
      >
        {prefix.replace(",", "")}<span className="accent">,</span> {name}<span className="accent">.</span>
      </div>
    );
  }
  const shout = word === "late" ? "LATE NIGHT" : word.toUpperCase();
  return (
    <div className={"greeting display " + (bone ? "bone" : "")} style={{ fontSize: size }}>
      {shout}<span className="accent">,</span><br />{name.toUpperCase()}<span className="accent">.</span>
    </div>
  );
}

// ─────────────────── Markets clock ───────────────────────────────

/** "Markets open in 2h 48m" / "closes in 4h 12m" / "closed". When
 *  `phrase` is supplied we split on the time-string at the end and
 *  render it in the neon mono `<span class="time">`. */
export function MarketsClock({
  size = 28, phrase = "Markets open in 2h 48m", live = false,
}: {
  size?: number; phrase?: string; live?: boolean;
}) {
  // Pull the trailing "Xh Ym" / "Ym" out so we can style the time strong.
  const m = phrase.match(/^(.*?)(\d+h(?:\s\d+m)?|\d+m)$/);
  const [pre, t] = m ? [m[1], m[2]] : [phrase, ""];
  return (
    <div className="markets-clock" style={{ fontSize: size }}>
      {live && <span className="live-dot" style={{ marginRight: 10 }} />}
      {pre}
      {t && <span className="time">{t}</span>}
    </div>
  );
}

// ─────────────────── Ticker strip ────────────────────────────────

/** TickerStrip pulls SPY / QQQ / IWM from bnf_universe_latest (the same
 *  view the BNF page uses). 10Y / VIX / DXY are not in our cache yet —
 *  rendered as muted placeholders until a later pass extends the macro
 *  backfill. The live-dot decorates SPY only — it's our headline. */

interface TickerLatestRow {
  ticker: string;
  latest_close: number;
  today_intraday_pct: number | null;
}

function useTickerData() {
  return useQuery({
    queryKey: ["dash_ticker_strip"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bnf_universe_latest" as never)
        .select("ticker, latest_close, today_intraday_pct")
        .in("ticker", ["SPY", "QQQ", "IWM"])
        .returns<TickerLatestRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 60_000,
  });
}

type MacroLabel = "10Y" | "VIX" | "DXY";
interface MacroQuote { price: number | null; changePct: number | null; source: string | null }

/** Live quotes via the quote-macro edge function: 10Y / VIX / DXY (Polygon
 *  indices → Yahoo) plus SPY / QQQ / IWM (live Yahoo) so the index % change
 *  reflects today, not the nightly cache close. Failures degrade to the
 *  muted "—" placeholder / cache fallback. */
function useMacroData() {
  return useQuery({
    queryKey: ["dash_macro_strip"],
    queryFn: async () => {
      const { data, error } = await supabase.functions.invoke("quote-macro", {
        body: { tickers: ["SPY", "QQQ", "IWM"] },
      });
      if (error) throw error;
      return (data as { items?: Record<string, MacroQuote> } | null)?.items ?? null;
    },
    staleTime: 5 * 60_000,
    refetchInterval: 5 * 60_000,
  });
}

/** Format a macro index value for the strip. 10Y reads as a yield (4.32%),
 *  VIX / DXY as plain two-decimal levels. */
function fmtMacroPrice(label: MacroLabel, v: number | null): string {
  if (v == null || !Number.isFinite(v)) return "—";
  return label === "10Y" ? `${v.toFixed(2)}%` : v.toFixed(2);
}

function fmtChangePct(v: number | null): { txt: string; tone: "pos" | "neg" } {
  if (v == null || !Number.isFinite(v)) return { txt: "—", tone: "pos" };
  const sign = v >= 0 ? "+" : "−";
  return { txt: `${sign}${Math.abs(v).toFixed(2)}%`, tone: v >= 0 ? "pos" : "neg" };
}

export function TickerStrip({ compact = false }: { compact?: boolean }) {
  const { data: live = [] } = useTickerData();
  const { data: macro = null } = useMacroData();
  const byTicker = new Map(live.map((r) => [r.ticker, r]));

  // Live rows first. 10Y / VIX / DXY remain placeholders until the cache
  // gets those instruments in a future pass — render as muted "—".
  const rows: Array<{
    ticker: string;
    price: string;
    change: string;
    tone: "pos" | "neg";
    live: boolean;
    muted?: boolean;
  }> = [];
  for (const sym of ["SPY", "QQQ", "IWM"] as const) {
    const q = macro?.[sym];
    const r = byTicker.get(sym);
    if (q && q.price != null) {
      // Live Yahoo quote — accurate today % + price.
      const ch = fmtChangePct(q.changePct);
      rows.push({ ticker: sym, price: q.price.toFixed(2), change: ch.txt, tone: ch.tone, live: sym === "SPY" });
    } else if (r) {
      // Cache fallback (nightly close) when the live quote is unavailable.
      const ch = fmtChangePct(r.today_intraday_pct);
      rows.push({ ticker: sym, price: r.latest_close.toFixed(2), change: ch.txt, tone: ch.tone, live: sym === "SPY" });
    } else {
      rows.push({ ticker: sym, price: "—", change: "—", tone: "pos", live: false, muted: true });
    }
  }
  for (const sym of ["10Y", "VIX", "DXY"] as const) {
    const q = macro?.[sym];
    if (q && q.price != null) {
      const ch = fmtChangePct(q.changePct);
      rows.push({ ticker: sym, price: fmtMacroPrice(sym, q.price), change: ch.txt, tone: ch.tone, live: false });
    } else {
      rows.push({ ticker: sym, price: "—", change: "—", tone: "pos", live: false, muted: true });
    }
  }

  return (
    <div className={"ticker" + (compact ? " compact" : "")}>
      {rows.map((r) => (
        <div key={r.ticker} className={"tick" + (compact ? " compact" : "")} style={r.muted ? { opacity: 0.55 } : undefined}>
          <div className="head">
            {r.live && <span className="live-dot" />}
            <span className="label">{r.ticker}</span>
          </div>
          <div className="price">{r.price}</div>
          <div className={"change " + r.tone}>{r.change}</div>
        </div>
      ))}
    </div>
  );
}

// ─────────────────── § 01 Attention (live) ───────────────────────

interface AttentionTrade {
  id: string;
  ticker: string;
  action: "open" | "close";
  option_type: "call" | "put";
  direction: "short" | "long";
  contracts: number;
  strike: number;
  premium: number;
  expiry: string;
  closes_trade_id: string | null;
}

interface AttentionPosition {
  ticker: string;
  quantity: number;
  current_price: number | null;
  earnings_date: string | null;
}

const todayIso = () => new Date().toISOString().slice(0, 10);

function useAttentionTrades() {
  return useQuery({
    queryKey: ["dash_attention_trades"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("id, ticker, action, option_type, direction, contracts, strike, premium, expiry, closes_trade_id")
        .returns<AttentionTrade[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

function useAttentionPositions() {
  return useQuery({
    queryKey: ["dash_attention_positions"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker, quantity, current_price, earnings_date")
        .returns<AttentionPosition[]>();
      if (error) throw error;
      return (data ?? []).filter((p) => p.quantity > 0);
    },
    staleTime: 5 * 60 * 1000,
  });
}

/** Roll up closed-by-open quantities so we can detect "still live"
 *  positions among the raw trade log. Mirrors the helper used in the
 *  TradesLogMatrix denominator math. */
function liveOpensFrom(trades: AttentionTrade[]): AttentionTrade[] {
  const closedQty = new Map<string, number>();
  for (const t of trades) {
    if (t.action === "close" && t.closes_trade_id) {
      closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
    }
  }
  return trades
    .filter((t) => t.action === "open")
    .map((t) => ({ ...t, contracts: t.contracts - (closedQty.get(t.id) ?? 0) }))
    .filter((t) => t.contracts > 0);
}

/** ITM detection given direction + type + spot. */
function isITM(t: AttentionTrade, spot: number): boolean {
  if (t.option_type === "call") return spot >= t.strike;
  return spot <= t.strike;
}

export function AttentionBlock({ n = "01" }: { n?: string }) {
  const { data: rawTrades = [] } = useAttentionTrades();
  const { data: positions = [] } = useAttentionPositions();

  const rows = useMemo(() => {
    const today = todayIso();
    const lives = liveOpensFrom(rawTrades);
    const expiringToday = lives.filter((t) => t.expiry === today);

    // Spot lookup from the positions table for ITM/OTM chips.
    const spotByTicker = new Map<string, number>();
    for (const p of positions) {
      if (p.current_price != null) spotByTicker.set(p.ticker, p.current_price);
    }

    // ── Row 1: expiring today (if any) ────────────────────────
    const r1 = expiringToday.length > 0 ? (() => {
      const lead = expiringToday[0];
      const more = expiringToday.length - 1;
      const spot = spotByTicker.get(lead.ticker);
      const itm = spot != null ? isITM(lead, spot) : null;
      const shortPremIfOTM = expiringToday
        .filter((t) => t.direction === "short")
        .reduce((s, t) => s + t.contracts * 100 * t.premium, 0);
      const right = itm === false
        ? <span className="pos">+${shortPremIfOTM.toLocaleString()} kept</span>
        : itm === true
          ? <span className="neg">ITM · assignment risk</span>
          : <span className="fg3">—</span>;
      return {
        label: "EXPIRES TODAY",
        right,
        content: (
          <>
            <span className="num-mono" style={{ fontWeight: 500 }}>
              {lead.ticker} {lead.strike}{lead.option_type === "call" ? "c" : "p"}
            </span>
            <span className="fg4"> · </span>
            {lead.contracts} contract{lead.contracts === 1 ? "" : "s"}
            {more > 0 && <><span className="fg4"> · </span>+{more} more</>}
            {itm != null && (
              <span className={"chip " + (itm ? "warn" : "pos")} style={{ marginLeft: 8 }}>
                {itm ? "ITM" : "OTM"}
              </span>
            )}
          </>
        ),
      };
    })() : null;

    // ── Row 2: short premium settling (this week) ─────────────
    // Sum short-open premium for legs expiring in next 7 days; that's
    // the cash that lands if everything ends OTM.
    const weekEnd = new Date();
    weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);
    const weekEndIso = weekEnd.toISOString().slice(0, 10);
    const expiringThisWeek = lives.filter((t) => t.expiry >= today && t.expiry <= weekEndIso);
    const settlingShort = expiringThisWeek.filter((t) => t.direction === "short");
    const settling$ = settlingShort.reduce((s, t) => s + t.contracts * 100 * t.premium, 0);
    const settlingContracts = settlingShort.reduce((s, t) => s + t.contracts, 0);
    const r2 = settling$ > 0 ? {
      label: "SETTLING",
      right: (
        <span className="num-sans pos" style={{ fontSize: 18, fontWeight: 600 }}>
          <MoneyCount value={settling$} sign="+" delay={400} />
        </span>
      ),
      content: (
        <>Premium clears if held to expiry · {settlingContracts} contract{settlingContracts === 1 ? "" : "s"} this week</>
      ),
    } : null;

    // ── Row 3: earnings in held positions (next 5 days) ───────
    const fiveDays = new Date();
    fiveDays.setUTCDate(fiveDays.getUTCDate() + 5);
    const fiveIso = fiveDays.toISOString().slice(0, 10);
    const earningsSoon = positions
      .filter((p) => p.earnings_date && p.earnings_date >= today && p.earnings_date <= fiveIso)
      .sort((a, b) => (a.earnings_date ?? "").localeCompare(b.earnings_date ?? ""));
    const r3 = earningsSoon.length > 0 ? (() => {
      const lead = earningsSoon[0];
      const days = Math.ceil(
        (new Date(lead.earnings_date! + "T00:00:00Z").getTime() -
         new Date(today + "T00:00:00Z").getTime()) / 86_400_000,
      );
      const label = days === 0 ? "EARNINGS · TODAY"
        : days === 1 ? "EARNINGS · TMW"
        : `EARNINGS · ${days}d`;
      return {
        label,
        right: <span className="warn">vol event</span>,
        content: (
          <>
            <span className="num-mono" style={{ fontWeight: 500 }}>{lead.ticker}</span>
            {" · holding "}{lead.quantity.toLocaleString()} sh
            {earningsSoon.length > 1 && <> · +{earningsSoon.length - 1} more</>}
          </>
        ),
      };
    })() : null;

    // ── Row 4: macro events today ─────────────────────────────
    const macroToday = macroEventsOn(today);
    const r4 = macroToday.length > 0 ? (() => {
      const lead = macroToday[0];
      return {
        label: "MACRO · TODAY",
        right: <span className={"chip " + (lead.tone === "warn" ? "warn" : "")}>{lead.tone === "warn" ? "VOL EVENT" : "INFO"}</span>,
        content: (
          <>{lead.label} <span className="num-mono">{lead.timeET}</span>{macroToday.length > 1 && <> · +{macroToday.length - 1} more</>}</>
        ),
      };
    })() : null;

    return [r1, r2, r3, r4].filter((x): x is NonNullable<typeof x> => x != null);
  }, [rawTrades, positions]);

  return (
    <div>
      <Section n={n} right={`${rows.length} item${rows.length === 1 ? "" : "s"}`}>
        On your radar today
      </Section>
      {rows.length === 0 ? (
        <div style={{ padding: "32px 0", color: "var(--fg3)", fontSize: 14 }}>
          Nothing urgent — markets are quiet on your book today.
        </div>
      ) : (
        rows.map((r, i) => (
          <HairRow key={i} label={r.label} right={r.right} last={i === rows.length - 1}>
            {r.content}
          </HairRow>
        ))
      )}
    </div>
  );
}

// ─────────────────── § 02 Portfolio (live) ───────────────────────
//
// Hero value = Σ qty × current_price across open positions.
// Week delta = portfolio value today − value 5 trading days ago,
//              derived from daily_closes × today's qty.
// Sparkline  = full portfolio value series over the trading days we
//              have in daily_closes (cap ~60 days).

interface PulsePosition {
  ticker: string;
  quantity: number;
  current_price: number | null;
  avg_cost: number;
  status: string;
}
interface PulseDailyClose {
  ticker: string;
  date: string;
  close_price: number;
}

const SPARK_TRADING_DAYS = 60;
const WEEK_TRADING_DAYS = 5;

function usePulsePositions() {
  return useQuery({
    queryKey: ["dash_pulse_positions"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker, quantity, current_price, avg_cost, status")
        .returns<PulsePosition[]>();
      if (error) throw error;
      return (data ?? []).filter((p) => p.status === "open" && p.quantity > 0);
    },
    staleTime: 5 * 60 * 1000,
  });
}

function usePulseCloses() {
  return useQuery({
    queryKey: ["dash_pulse_closes"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("daily_closes" as never)
        .select("ticker, date, close_price")
        .order("date", { ascending: true })
        .returns<PulseDailyClose[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 10 * 60 * 1000,
  });
}

/** Build a portfolio value series from close prices and today's qty.
 *
 *  daily_closes is captured going forward and has gaps — not every held
 *  ticker has a row on every past date. Summing only the tickers present on
 *  each date understates older dates (missing names count as $0), which
 *  manufactures a fake upward ramp. So we CARRY FORWARD: for any date a
 *  ticker has no close, use its most recent prior close (or its earliest
 *  close / current price before that), so every holding always contributes a
 *  real price and the series reflects pure mark-to-market on current shares. */
function valueSeries(positions: PulsePosition[], closes: PulseDailyClose[]): {
  series: number[];
  dates: string[];
} {
  const byTicker = new Map<string, { date: string; close: number }[]>();
  const dateSet = new Set<string>();
  for (const c of closes) {
    if (!byTicker.has(c.ticker)) byTicker.set(c.ticker, []);
    byTicker.get(c.ticker)!.push({ date: c.date, close: c.close_price });
    dateSet.add(c.date);
  }
  for (const arr of byTicker.values()) arr.sort((a, b) => a.date.localeCompare(b.date));
  const dates = [...dateSet].sort().slice(-SPARK_TRADING_DAYS);
  // Per-position resolver: carried-forward close on/before a date.
  const resolvers = positions.map((p) => {
    const arr = byTicker.get(p.ticker);
    const fallback = p.current_price ?? p.avg_cost ?? 0;
    const get = (!arr || arr.length === 0)
      ? () => fallback
      : (d: string) => {
          let val = arr[0].close;            // earliest, for dates before first close
          for (const e of arr) { if (e.date <= d) val = e.close; else break; }
          return val;
        };
    return { qty: p.quantity, get };
  });
  const series = dates.map((d) => resolvers.reduce((v, r) => v + r.get(d) * r.qty, 0));
  return { series, dates };
}

function fmtCompactUSD(v: number): string {
  const abs = Math.abs(v);
  if (abs >= 1_000_000) return `${v < 0 ? "−" : ""}$${(abs / 1_000_000).toFixed(2)}M`;
  if (abs >= 1_000)     return `${v < 0 ? "−" : ""}$${(abs / 1_000).toFixed(0)}k`;
  return `${v < 0 ? "−" : ""}$${Math.round(abs).toLocaleString()}`;
}

export function PortfolioBlock({
  heroSize = 184, bone = false, area = true, n = "02",
}: {
  heroSize?: number; bone?: boolean; area?: boolean; n?: string;
}) {
  const { data: positions = [] } = usePulsePositions();
  const { data: closes = [] } = usePulseCloses();

  const totalValue = useMemo(
    () => positions.reduce((s, p) => s + (p.current_price ?? p.avg_cost) * p.quantity, 0),
    [positions],
  );
  const { series } = useMemo(() => valueSeries(positions, closes), [positions, closes]);
  // Change over the trailing week — but when we have fewer than a full week
  // of history, fall back to the full available range instead of zeroing out
  // (otherwise a brand-new account with 4–5 days of data reads +$0).
  const { weekDelta, weekPct } = useMemo(() => {
    if (series.length < 2) return { weekDelta: 0, weekPct: 0 };
    const lastIdx = series.length - 1;
    const baseIdx = Math.max(0, lastIdx - WEEK_TRADING_DAYS);
    const base = series[baseIdx] ?? 0;
    const delta = series[lastIdx] - base;
    return { weekDelta: delta, weekPct: base > 0 ? (delta / base) * 100 : 0 };
  }, [series]);
  const oldest = series[0] ?? 0;
  const newest = series[series.length - 1] ?? totalValue;

  return (
    <div>
      <Section n={n} right="live">Portfolio</Section>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 36 }}>
        <div className={"portfolio-num " + (bone ? "bone" : "neon")} style={{ fontSize: heroSize }}>
          <MoneyCount value={Math.round(totalValue)} duration={1400} />
        </div>
        <div style={{ paddingBottom: heroSize * 0.13 }}>
          <div className="label">This week</div>
          <div className={"hero num-mono " + (weekDelta >= 0 ? "pos" : "neg")} style={{ fontSize: 48, fontWeight: 700, marginTop: 4 }}>
            <MoneyCount value={Math.round(weekDelta)} sign={weekDelta >= 0 ? "+" : "-"} delay={200} duration={1100} />
          </div>
          <div className={"num-mono " + (weekDelta >= 0 ? "pos" : "neg")} style={{ fontSize: 14, marginTop: 4 }}>
            <PctCount value={Math.abs(weekPct)} sign={weekDelta >= 0 ? "+" : "-"} delay={300} /> · 5 sessions
          </div>
        </div>
      </div>
      <div style={{ marginTop: 28 }}>
        <Spark w={820} h={56} kind={weekDelta >= 0 ? "neon" : "neg"} area={area} delay={300} series={series} />
        <div style={{ display: "flex", justifyContent: "space-between", maxWidth: 820, marginTop: 8 }}>
          <span className="label">{series.length} sessions ago · {fmtCompactUSD(oldest)}</span>
          <span className="label">today · {fmtCompactUSD(newest)}</span>
        </div>
      </div>
    </div>
  );
}

export function PortfolioBlockCompact({
  heroSize = 128, bone = false, area = true, n = "04",
}: {
  heroSize?: number; bone?: boolean; area?: boolean; n?: string;
}) {
  const { data: positions = [] } = usePulsePositions();
  const { data: closes = [] } = usePulseCloses();

  const totalValue = useMemo(
    () => positions.reduce((s, p) => s + (p.current_price ?? p.avg_cost) * p.quantity, 0),
    [positions],
  );
  const { series } = useMemo(() => valueSeries(positions, closes), [positions, closes]);
  // Change over the trailing week — but when we have fewer than a full week
  // of history, fall back to the full available range instead of zeroing out
  // (otherwise a brand-new account with 4–5 days of data reads +$0).
  const { weekDelta, weekPct } = useMemo(() => {
    if (series.length < 2) return { weekDelta: 0, weekPct: 0 };
    const lastIdx = series.length - 1;
    const baseIdx = Math.max(0, lastIdx - WEEK_TRADING_DAYS);
    const base = series[baseIdx] ?? 0;
    const delta = series[lastIdx] - base;
    return { weekDelta: delta, weekPct: base > 0 ? (delta / base) * 100 : 0 };
  }, [series]);
  const oldest = series[0] ?? 0;
  const newest = series[series.length - 1] ?? totalValue;

  return (
    <div>
      <Section n={n}>Portfolio</Section>
      <div className={"portfolio-num " + (bone ? "bone" : "neon")} style={{ fontSize: heroSize }}>
        <MoneyCount value={Math.round(totalValue)} duration={1400} />
      </div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 18, marginTop: 14 }}>
        <span className={"hero num-mono " + (weekDelta >= 0 ? "pos" : "neg")} style={{ fontSize: 32, fontWeight: 700 }}>
          <MoneyCount value={Math.round(weekDelta)} sign={weekDelta >= 0 ? "+" : "-"} delay={200} />
        </span>
        <span className={"num-mono " + (weekDelta >= 0 ? "pos" : "neg")} style={{ fontSize: 13 }}>
          <PctCount value={Math.abs(weekPct)} sign={weekDelta >= 0 ? "+" : "-"} delay={300} /> · 1 week
        </span>
      </div>
      <div style={{ marginTop: 22 }}>
        <Spark w={540} h={42} kind={weekDelta >= 0 ? "neon" : "neg"} area={area} delay={300} series={series} />
        <div style={{ display: "flex", justifyContent: "space-between", maxWidth: 540, marginTop: 6 }}>
          <span className="label">{series.length}d · {fmtCompactUSD(oldest)}</span>
          <span className="label">today · {fmtCompactUSD(newest)}</span>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── Winners / Losers ────────────────────────────

/** Top 3 weekly winners + top 3 weekly losers, derived from 5-day
 *  close deltas × today's quantity. Bar widths normalise to the
 *  biggest move so the magnitude reads at a glance. */
export function WinnersLosers() {
  const { data: positions = [] } = usePulsePositions();
  const { data: closes = [] } = usePulseCloses();

  const { winners, losers } = useMemo(() => {
    const byTicker = new Map<string, Map<string, number>>();
    const dateSet = new Set<string>();
    for (const c of closes) {
      if (!byTicker.has(c.ticker)) byTicker.set(c.ticker, new Map());
      byTicker.get(c.ticker)!.set(c.date, c.close_price);
      dateSet.add(c.date);
    }
    const dates = [...dateSet].sort();
    if (dates.length < WEEK_TRADING_DAYS + 1) return { winners: [], losers: [] };

    const today = dates[dates.length - 1];
    const wkAgo = dates[dates.length - 1 - WEEK_TRADING_DAYS];

    const moves: Array<{ ticker: string; delta: number }> = [];
    for (const p of positions) {
      const tCloses = byTicker.get(p.ticker);
      if (!tCloses) continue;
      const todayP = tCloses.get(today);
      const oldP = tCloses.get(wkAgo);
      if (todayP == null || oldP == null) continue;
      const delta = (todayP - oldP) * p.quantity;
      if (Math.abs(delta) < 50) continue;                  // skip flat
      moves.push({ ticker: p.ticker, delta });
    }
    moves.sort((a, b) => b.delta - a.delta);
    const maxAbs = Math.max(1, ...moves.map((m) => Math.abs(m.delta)));
    const decorate = (m: { ticker: string; delta: number }) =>
      [m.ticker, Math.round(Math.abs(m.delta)), Math.abs(m.delta) / maxAbs] as [string, number, number];
    return {
      winners: moves.filter((m) => m.delta > 0).slice(0, 3).map(decorate),
      losers:  moves.filter((m) => m.delta < 0).slice(-3).reverse().map(decorate),
    };
  }, [positions, closes]);

  return (
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 64 }}>
      <div>
        <Section>Winners · this week</Section>
        {winners.length === 0
          ? <div style={{ padding: "12px 0", color: "var(--fg3)", fontSize: 13 }}>—</div>
          : winners.map(([t, v, w], i) => (
              <div key={t} className="bar-row">
                <span className="num-mono" style={{ fontSize: 14, fontWeight: 500 }}>{t}</span>
                <AnimatedBar targetPct={w} kind="pos" delay={300 + i * 90} />
                <span className="num-mono pos" style={{ fontSize: 14, fontWeight: 500, textAlign: "right" }}>
                  <MoneyCount value={v} sign="+" delay={300 + i * 90} />
                </span>
              </div>
            ))}
      </div>
      <div>
        <Section>Losers · this week</Section>
        {losers.length === 0
          ? <div style={{ padding: "12px 0", color: "var(--fg3)", fontSize: 13 }}>—</div>
          : losers.map(([t, v, w], i) => (
              <div key={t} className="bar-row">
                <span className="num-mono" style={{ fontSize: 14, fontWeight: 500 }}>{t}</span>
                <AnimatedBar targetPct={w} kind="neg" delay={400 + i * 90} />
                <span className="num-mono neg" style={{ fontSize: 14, fontWeight: 500, textAlign: "right" }}>
                  <MoneyCount value={v} sign="-" delay={400 + i * 90} />
                </span>
              </div>
            ))}
      </div>
    </div>
  );
}

// ─────────────────── Income mix (call vs put) ────────────────────

/** Call vs put income for the last 7 days. Sums short-open premium
 *  by option type, net of any buybacks in the same window. */

interface IncomeTrade {
  ticker: string;
  trade_date: string;
  action: "open" | "close";
  option_type: "call" | "put";
  direction: "short" | "long";
  contracts: number;
  premium: number;
}

function useIncomeTrades() {
  return useQuery({
    queryKey: ["dash_income_trades"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("ticker, trade_date, action, option_type, direction, contracts, premium")
        .returns<IncomeTrade[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function IncomeMix({ compact = false }: { compact?: boolean }) {
  const { data: trades = [] } = useIncomeTrades();
  const entered = useEntered(300);

  const { call, put } = useMemo(() => {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    let callIn = 0, putIn = 0;
    for (const t of trades) {
      if (t.direction !== "short") continue;
      const dt = new Date(t.trade_date + "T00:00:00Z");
      const days = Math.floor((today.getTime() - dt.getTime()) / 86_400_000);
      if (days < 0 || days > 7) continue;
      const dollars = t.contracts * 100 * t.premium;
      if (t.action === "open")  (t.option_type === "call" ? (callIn += dollars) : (putIn += dollars));
      if (t.action === "close") (t.option_type === "call" ? (callIn -= dollars) : (putIn -= dollars));
    }
    return { call: Math.max(0, callIn), put: Math.max(0, putIn) };
  }, [trades]);

  const total = call + put;
  const callPctTarget = total > 0 ? (call / total) * 100 : 50;
  const callsPct = entered ? callPctTarget : 0;

  return (
    <div>
      <Section>Income mix · this week</Section>
      <div style={{ display: "flex", alignItems: "baseline", gap: compact ? 16 : 32 }}>
        <div>
          <div className="label">Calls sold</div>
          <div className="hero num-mono neon" style={{ fontSize: compact ? 28 : 44, fontWeight: 700, marginTop: 4 }}>
            <MoneyCount value={Math.round(call)} delay={150} duration={1200} />
          </div>
        </div>
        <div className="income-mix-bar">
          <div
            className="calls"
            style={{
              width: `${callsPct}%`,
              transition: "width 1.1s cubic-bezier(.16,1,.3,1)",
            }}
          />
          <div className="puts" style={{ flex: 1 }} />
        </div>
        <div style={{ textAlign: "right" }}>
          <div className="label">Puts sold</div>
          <div className="hero num-mono fg2" style={{ fontSize: compact ? 28 : 44, fontWeight: 700, marginTop: 4 }}>
            <MoneyCount value={Math.round(put)} delay={250} duration={1200} />
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── § 03 Calendar (live) ────────────────────────

type EventKind = "mine" | "plain" | "warn";

interface CalEvent {
  kind: EventKind;
  text: string;
}

interface CalDay {
  iso: string;
  dayLabel: string;
  dayNum: string;
  events: CalEvent[];
  today: boolean;
}

/** Compute Mon–Fri ISO dates for the week containing `from`. */
function workWeek(from: Date): string[] {
  const d = new Date(from);
  d.setHours(0, 0, 0, 0);
  // Shift to the week's Monday (getDay: Sun=0 .. Sat=6).
  const dow = d.getDay();
  const mondayOffset = dow === 0 ? -6 : 1 - dow;
  d.setDate(d.getDate() + mondayOffset);
  const out: string[] = [];
  for (let i = 0; i < 5; i++) {
    const dd = new Date(d);
    dd.setDate(d.getDate() + i);
    out.push(dd.toISOString().slice(0, 10));
  }
  return out;
}

const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTH_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function CalendarBlock({
  n = "03", highlight = "neon", compact = false,
}: {
  n?: string;
  highlight?: "amber" | "neon" | "off";
  compact?: boolean;
}) {
  // Same data sources Attention block uses — the React Query cache makes
  // these effectively free here.
  const { data: rawTrades = [] } = useAttentionTrades();
  const { data: positions = [] } = useAttentionPositions();

  const today = todayIso();
  const days: CalDay[] = useMemo(() => {
    const weekDates = workWeek(new Date());
    const lives = liveOpensFrom(rawTrades);

    // Bucket events into per-day arrays.
    return weekDates.map((iso) => {
      const dt = new Date(iso + "T00:00:00Z");
      const events: CalEvent[] = [];

      // 1) My option expiries on this date
      const expiries = lives.filter((t) => t.expiry === iso);
      // Group by ticker so we don't spam a row per leg.
      const expByTicker = new Map<string, number>();
      for (const t of expiries) {
        expByTicker.set(t.ticker, (expByTicker.get(t.ticker) ?? 0) + t.contracts);
      }
      for (const [tk] of expByTicker) {
        events.push({ kind: "mine", text: `${tk} exp` });
      }

      // 2) Held-position earnings on this date
      const earningsToday = positions.filter((p) => p.earnings_date === iso);
      for (const p of earningsToday) {
        events.push({ kind: "plain", text: `${p.ticker} earn` });
      }

      // 3) Macro events on this date
      for (const me of macroEventsOn(iso)) {
        events.push({ kind: "warn", text: me.kind });
      }

      return {
        iso,
        dayLabel: DAY_NAMES[dt.getUTCDay()],
        dayNum: String(dt.getUTCDate()),
        events,
        today: iso === today,
      };
    });
  }, [rawTrades, positions, today]);

  const weekLabel = days.length > 0 ? (() => {
    const d = new Date(days[0].iso + "T00:00:00Z");
    return `Week of ${MONTH_SHORT[d.getUTCMonth()]} ${d.getUTCDate()}`;
  })() : "";

  const highlightClass = highlight === "neon" ? " neon-highlight"
    : highlight === "off" ? " no-highlight"
    : "";

  return (
    <div>
      <Section n={n} right={weekLabel}>Week ahead</Section>
      <div className="cal">
        {days.map((d) => (
          <div
            key={d.iso}
            className={"cal-cell" + (d.today ? " today" + highlightClass : "")}
            style={compact ? { minHeight: 140, padding: 10 } : undefined}
          >
            <div className="day-label" style={compact ? { marginBottom: 8 } : undefined}>
              {d.dayLabel} {d.dayNum}{d.today && !compact && " · TODAY"}
            </div>
            {d.events.length === 0 && (
              <div className="cal-event" style={compact ? { fontSize: 10, opacity: 0.4 } : { opacity: 0.4 }}>
                quiet
              </div>
            )}
            {d.events.map((e, j) => (
              e.kind === "warn" ? (
                <div key={j} style={{ marginBottom: 6 }}>
                  <span className="chip warn" style={compact ? { fontSize: 8 } : undefined}>{e.text}</span>
                </div>
              ) : (
                <div
                  key={j}
                  className={"cal-event" + (e.kind === "mine" ? " mine" : "")}
                  style={compact ? { fontSize: 10 } : undefined}
                >
                  {e.text}
                </div>
              )
            ))}
            {d.today && !compact && <div className="focus-tag">↑ FOCUS</div>}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────── § 04 Macro zoom (live) ──────────────────────
//
// Six live ETF rows pulled from bnf_universe_data (SPY/QQQ/IWM cover
// broad indices; KWEB/SMH/ARKK proxy China, semis, innovation —
// preserves the "around the world" feel). 10Y / VIX / DXY render as
// muted placeholders until those instruments land in the cache.
//
// Each row's "note" is auto-generated from intraday % + 25-day
// deviation — quick canned phrases driven by simple thresholds, not
// model-generated commentary.

interface MacroLatestRow {
  ticker: string;
  latest_close: number;
  today_intraday_pct: number | null;
  deviation_pct: number | null;
}
interface MacroCloseRow {
  ticker: string;
  date: string;
  close: number;
}

// Six live tickers from the bnf_universe_data cache. 10Y / VIX / DXY
// dropped from the visible list until they're in the cache — empty
// placeholder rows added more noise than they earned.
const MACRO_TICKERS = ["SPY", "QQQ", "IWM", "KWEB", "SMH", "ARKK"] as const;

function useMacroLatest() {
  return useQuery({
    queryKey: ["dash_macro_latest"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bnf_universe_latest" as never)
        .select("ticker, latest_close, today_intraday_pct, deviation_pct")
        .in("ticker", MACRO_TICKERS as unknown as string[])
        .returns<MacroLatestRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

function useMacroSparks() {
  return useQuery({
    queryKey: ["dash_macro_sparks"],
    queryFn: async () => {
      // 30 trading days of closes per macro ticker — enough to draw a
      // smooth sparkline at the row's small height.
      const cutoff = new Date();
      cutoff.setUTCDate(cutoff.getUTCDate() - 45);
      const { data, error } = await supabase
        .from("bnf_universe_data" as never)
        .select("ticker, date, close")
        .in("ticker", MACRO_TICKERS as unknown as string[])
        .gte("date", cutoff.toISOString().slice(0, 10))
        .order("date", { ascending: true })
        .returns<MacroCloseRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 10 * 60 * 1000,
  });
}

/** Live today-% for the macro tickers via the quote-macro edge function
 *  (Yahoo). The cache's today_intraday_pct goes stale between nightly
 *  updates, so the % change is pulled live; SMA25 deviation still comes
 *  from the cache (needs history). */
function useMacroLiveQuotes() {
  return useQuery({
    queryKey: ["dash_macro_live"],
    queryFn: async () => {
      const { data, error } = await supabase.functions.invoke("quote-macro", {
        body: { tickers: MACRO_TICKERS },
      });
      if (error) throw error;
      return (data as { items?: Record<string, { changePct: number | null; price: number | null }> } | null)?.items ?? null;
    },
    staleTime: 2 * 60_000,
    refetchInterval: 5 * 60_000,
  });
}

/** Canned phrase per macro row. Drives the human-readable "note"
 *  column based on intraday % + 25-day deviation from SMA25. */
function macroInsight(ticker: string, intraday: number | null, deviation: number | null): string {
  const intr = intraday ?? 0;
  const dev = deviation ?? 0;

  const intraPart =
    intr >  1.0 ? "strong bid" :
    intr >  0.3 ? "risk-on" :
    intr > -0.3 ? "quiet, no extremes" :
    intr > -1.0 ? "soft tape" :
                  "selling pressure";

  // Deviation gives the "stretched" cue
  const devPart =
    dev >  5  ? "stretched +" + dev.toFixed(0) + "% from SMA25" :
    dev <  -5 ? "oversold " + dev.toFixed(0) + "% from SMA25" :
    "";

  // Ticker-specific flavour beats the generic phrase
  const flavour: Record<string, string> = {
    SPY:  "broad market",
    QQQ:  "tech leadership",
    IWM:  "small caps",
    KWEB: "China internet",
    SMH:  "semis leading",
    ARKK: "innovation, vol-sensitive",
  };
  const f = flavour[ticker];

  if (devPart) return `${f ?? intraPart} · ${devPart}`;
  return `${f ?? "—"} · ${intraPart}`;
}

function fmtSignedPct(v: number | null): { txt: string; tone: "pos" | "neg" } {
  if (v == null || !Number.isFinite(v)) return { txt: "—", tone: "pos" };
  return { txt: `${v >= 0 ? "+" : "−"}${Math.abs(v).toFixed(2)}%`, tone: v >= 0 ? "pos" : "neg" };
}

export function MacroBlock({ n = "04", compact = false }: { n?: string; compact?: boolean }) {
  const { data: latest = [] } = useMacroLatest();
  const { data: sparkRows = [] } = useMacroSparks();

  // Build per-ticker close series for the sparkline.
  const closesByTicker = useMemo(() => {
    const m = new Map<string, number[]>();
    const sorted = [...sparkRows].sort((a, b) => a.date.localeCompare(b.date));
    for (const r of sorted) {
      const arr = m.get(r.ticker) ?? [];
      arr.push(r.close);
      m.set(r.ticker, arr);
    }
    return m;
  }, [sparkRows]);

  const latestByTicker = new Map(latest.map((r) => [r.ticker, r]));
  const { data: live = null } = useMacroLiveQuotes();

  return (
    <div>
      <Section n={n}>Macro zoom</Section>
      {MACRO_TICKERS.map((t, i) => {
        const r = latestByTicker.get(t);
        const series = closesByTicker.get(t);
        // Prefer the live % change (Yahoo) over the cache's stale intraday.
        const liveChg = live?.[t]?.changePct ?? null;
        const todayPct = liveChg != null ? liveChg : (r?.today_intraday_pct ?? null);
        const ch = fmtSignedPct(todayPct);
        const note = macroInsight(t, todayPct, r?.deviation_pct ?? null);
        return (
          <div
            key={t}
            className="macro-row"
            style={compact ? { gridTemplateColumns: "56px 1fr 78px 64px", gap: 14, padding: "10px 0" } : undefined}
          >
            <span className="ticker-name" style={compact ? { fontSize: 14 } : undefined}>{t}</span>
            <span className="note" style={compact ? { fontSize: 12 } : undefined}>{note}</span>
            <Spark
              w={compact ? 78 : 90}
              h={compact ? 18 : 22}
              kind={ch.tone === "pos" ? "muted" : "muted-down"}
              dense
              delay={500 + i * 60}
              series={series}
            />
            <span className={"change " + ch.tone} style={compact ? { fontSize: 12 } : undefined}>{ch.txt}</span>
          </div>
        );
      })}
    </div>
  );
}

// ─────────────────── § 05 BNF Strategy (live) ────────────────────

interface BNFRow {
  ticker: string;
  sector: string | null;
  deviation_pct: number | null;
  borderline: boolean | null;
}

function useBNFCandidates() {
  return useQuery({
    queryKey: ["dash_bnf"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bnf_candidates" as never)
        .select("ticker, sector, deviation_pct, borderline")
        .order("deviation_pct", { ascending: true })
        .limit(4)
        .returns<BNFRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function BNFBlock({
  n = "05", compact = false, onOpenScanner,
}: { n?: string; compact?: boolean; onOpenScanner?: () => void }) {
  const { data: picks = [] } = useBNFCandidates();

  // Short sector labels for the compact card.
  const shortSector = (s: string | null): string => {
    if (!s) return "—";
    if (s.startsWith("Communication")) return "Comm";
    if (s.startsWith("Consumer Discretionary")) return "Cons Disc";
    if (s.startsWith("Consumer Staples")) return "Staples";
    if (s.startsWith("Information")) return "Tech";
    if (s.startsWith("Technology")) return "Tech";
    if (s.startsWith("Financial")) return "Fin";
    if (s.startsWith("Industrial")) return "Indus";
    if (s.startsWith("Health")) return "Health";
    if (s.startsWith("Real Estate")) return "REIT";
    if (s.startsWith("Materials")) return "Materials";
    if (s.startsWith("Energy")) return "Energy";
    if (s.startsWith("Utilities")) return "Util";
    return s;
  };

  return (
    <div>
      <Section
        n={n}
        right={compact ? `${picks.length} picks` : `${picks.length} picks · mean-reversion`}
      >
        BNF · today
      </Section>
      {picks.length === 0 ? (
        <div style={{ padding: "20px 0", color: "var(--fg3)", fontSize: 13 }}>
          No candidates today. Run the scanner from the Strategy page.
        </div>
      ) : (
        <div style={compact ? { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 } : undefined}>
          {picks.map((p) => {
            const dev = p.deviation_pct;
            const devLabel = dev != null
              ? `${dev >= 0 ? "+" : "−"}${Math.abs(dev).toFixed(1)}%`
              : "—";
            const status = p.borderline ? "near miss" : "ready";
            const chipClass = p.borderline ? "warn" : "neon";
            const meta = compact
              ? `${devLabel} · ${shortSector(p.sector)}`
              : `${shortSector(p.sector)} · ${devLabel} from SMA25`;
            return (
              <div key={p.ticker} className="bnf-tile" style={compact ? undefined : { marginBottom: 10 }}>
                <div className="head">
                  <span className="ticker-name hero num-mono" style={{ fontSize: compact ? 22 : 26, fontWeight: 700 }}>
                    {p.ticker}
                  </span>
                  <span className={"chip " + chipClass} style={compact ? { fontSize: 8 } : undefined}>
                    {status}
                  </span>
                </div>
                <div className="label" style={{ marginTop: 6 }}>{meta}</div>
              </div>
            );
          })}
        </div>
      )}
      <div style={{ marginTop: 14 }}>
        <span className="pill" onClick={onOpenScanner} role={onOpenScanner ? "button" : undefined}>
          → Open scanner
        </span>
      </div>
    </div>
  );
}

// ─────────────────── § 06 Risk check (live) ──────────────────────
//
// Constant-beta shock math from riskMath.ts — fast, approximate, good
// enough for "is this a big number?" governance. Three scenarios:
// SPY −5% / top-holding −10% / VIX +50%.
//
// Cadence: weekly review. localStorage tracks the last "Mark
// reviewed" click; if older than 7 days the section header lights up
// "DUE" in amber. Numbers refresh live every load regardless.

interface RiskPositionRow {
  ticker: string;
  quantity: number;
  current_price: number | null;
  avg_cost: number;
  status: string;
}
interface RiskTradeRow {
  id: string;
  ticker: string;
  action: "open" | "close";
  option_type: "call" | "put";
  direction: "short" | "long";
  contracts: number;
  strike: number;
  premium: number;
  closes_trade_id: string | null;
}

function useRiskPositions() {
  return useQuery({
    queryKey: ["dash_risk_positions"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker, quantity, current_price, avg_cost, status")
        .returns<RiskPositionRow[]>();
      if (error) throw error;
      return (data ?? []).filter((p) => p.status === "open" && p.quantity > 0);
    },
    staleTime: 5 * 60 * 1000,
  });
}

function useRiskTrades() {
  return useQuery({
    queryKey: ["dash_risk_trades"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("id, ticker, action, option_type, direction, contracts, strike, premium, closes_trade_id")
        .returns<RiskTradeRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

function fmtReviewedAgo(d: Date | null): { phrase: string; overdue: boolean } {
  if (!d) return { phrase: "never reviewed", overdue: true };
  const ageMs = Date.now() - d.getTime();
  const days = Math.floor(ageMs / 86_400_000);
  const overdue = days >= 7;
  if (days === 0) return { phrase: "reviewed today", overdue };
  if (days === 1) return { phrase: "reviewed yesterday", overdue };
  return { phrase: `reviewed ${days}d ago`, overdue };
}

export function RiskBlock({ n = "06", compact = false }: { n?: string; compact?: boolean }) {
  const { data: positionsRaw = [] } = useRiskPositions();
  const { data: rawTrades = [] } = useRiskTrades();
  const [reviewedAt, setReviewedAt] = useState<Date | null>(loadLastReviewed());

  // Derive live opens (for delta-equivalent options exposure).
  const liveOpts = useMemo<RiskOptionInput[]>(() => {
    const closedQty = new Map<string, number>();
    for (const t of rawTrades) {
      if (t.action === "close" && t.closes_trade_id) {
        closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
      }
    }
    return rawTrades
      .filter((t) => t.action === "open")
      .map((t) => ({ ...t, contracts: t.contracts - (closedQty.get(t.id) ?? 0) }))
      .filter((t) => t.contracts > 0)
      .map((t) => ({
        ticker: t.ticker,
        option_type: t.option_type,
        direction: t.direction,
        contracts: t.contracts,
        strike: t.strike,
        premium: t.premium,
      }));
  }, [rawTrades]);

  const positions: RiskPositionInput[] = positionsRaw.map((p) => ({
    ticker: p.ticker,
    quantity: p.quantity,
    current_price: p.current_price,
    avg_cost: p.avg_cost,
  }));

  const scenarios = useMemo(
    () => buildRiskScenarios(positions, liveOpts),
    [positions, liveOpts],
  );

  const reviewLabel = fmtReviewedAgo(reviewedAt);
  const onMarkReviewed = () => {
    const now = new Date();
    saveLastReviewed(now);
    setReviewedAt(now);
  };

  return (
    <div>
      <Section
        n={n}
        right={
          <>
            <span className={reviewLabel.overdue ? "warn" : "fg2"}>{reviewLabel.phrase}</span>
            {reviewLabel.overdue && <span className="chip warn" style={{ marginLeft: 8 }}>DUE</span>}
          </>
        }
      >
        Risk check
      </Section>
      {scenarios.map((s, i) => {
        const last = i === scenarios.length - 1;
        return (
          <HairRow
            key={s.label}
            label={s.label}
            last={last}
            right={
              <span className={"num-mono " + (s.dollars < 0 ? "neg" : "pos")} style={{ fontSize: compact ? 18 : 22, fontWeight: 600 }}>
                <MoneyCount
                  value={Math.round(Math.abs(s.dollars))}
                  sign={s.dollars < 0 ? "-" : "+"}
                  delay={300 + i * 80}
                />
              </span>
            }
          >
            {s.detail}
          </HairRow>
        );
      })}
      <div style={{ marginTop: 14 }}>
        <span className="pill" onClick={onMarkReviewed}>✓ Mark reviewed</span>
      </div>
    </div>
  );
}

// ─────────────────── § 07 News band (live) ───────────────────────
//
// Calls the dashboard-news edge function with the user's held tickers.
// Yahoo Finance is the source; brittle by design but free. Cached for
// 15 min per session via React Query.

interface NewsApiItem {
  ticker: string;
  headline: string;
  url: string | null;
  publisher: string | null;
  ts: number | null;
}

function useNewsForHeldTickers() {
  // Reuse the lightweight positions query so this band doesn't duplicate
  // the fetch — React Query dedupes by key.
  const { data: positions = [] } = useQuery({
    queryKey: ["dash_news_held"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker, status, quantity")
        .returns<Array<{ ticker: string; status: string; quantity: number }>>();
      if (error) throw error;
      return (data ?? []).filter((p) => p.status === "open" && p.quantity > 0);
    },
    staleTime: 10 * 60 * 1000,
  });

  // Distinct held tickers, capped at 10 (edge function also caps).
  const tickers = useMemo(
    () => Array.from(new Set(positions.map((p) => p.ticker))).slice(0, 10),
    [positions],
  );

  return useQuery({
    queryKey: ["dash_news", tickers.join(",")],
    enabled: tickers.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.functions.invoke("dashboard-news", {
        body: { tickers },
      });
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error as string);
      return (data?.items ?? []) as NewsApiItem[];
    },
    staleTime: 15 * 60 * 1000,
  });
}

/** "5h ago" / "23m ago" / "2d ago" — concise relative time. */
function fmtRelTime(ts: number | null): string {
  if (ts == null) return "—";
  const ageMs = Date.now() - ts * 1000;
  const mins = Math.floor(ageMs / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

export function NewsBand({ n = "07" }: { n?: string }) {
  const { data: items = [], isLoading } = useNewsForHeldTickers();

  // Sort newest-first.
  const sorted = useMemo(
    () => [...items].sort((a, b) => (b.ts ?? 0) - (a.ts ?? 0)),
    [items],
  );

  return (
    <div>
      <Section
        n={n}
        right={isLoading ? "loading…" : `${sorted.length} held ticker${sorted.length === 1 ? "" : "s"}`}
      >
        Tape · headlines
      </Section>
      <div className="news-band">
        {sorted.length === 0 ? (
          <div style={{ color: "var(--fg3)", fontSize: 13, padding: "8px 0" }}>
            {isLoading ? "Pulling headlines…" : "No recent news for your held tickers."}
          </div>
        ) : sorted.map((it) => {
          const card = (
            <div className="news-card" key={it.ticker}>
              <div className="head">
                <span className="ticker-tag">{it.ticker}</span>
                <span className="time">{fmtRelTime(it.ts)}</span>
              </div>
              <div className="headline">
                {it.headline}
                {it.publisher && <span className="fg4"> — {it.publisher}</span>}
              </div>
            </div>
          );
          return it.url ? (
            <a key={it.ticker} href={it.url} target="_blank" rel="noopener noreferrer" style={{ textDecoration: "none" }}>
              {card}
            </a>
          ) : card;
        })}
      </div>
    </div>
  );
}

// ─────────────────── Tools rail (footer) ─────────────────────────

export function ToolsRail({
  onPositions, onStrategy, onMath,
}: {
  onPositions?: () => void;
  onStrategy?: () => void;
  onMath?: () => void;
}) {
  return (
    <div className="tools-rail">
      <a className="tool-link" onClick={onPositions}>→ Positions</a>
      <a className="tool-link" onClick={onStrategy}>→ Strategy</a>
      <a className="tool-link" onClick={onMath}>→ Math</a>
      <span className="build">v0 · Sunnyfi desk · last sync 06:42</span>
    </div>
  );
}
