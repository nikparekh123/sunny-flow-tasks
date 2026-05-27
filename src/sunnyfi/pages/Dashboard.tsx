/**
 * Dashboard — the new "morning briefing" homepage.
 *
 * Layout: a 12-column grid of cards on top of a magazine-cover greeting
 * strip. Each card is a self-contained section (Today / Portfolio Pulse
 * / Week Calendar / Macro / Strategy / Risk / News). The greeting + the
 * tools rail at the foot anchor the page; everything in between is the
 * personalised brief.
 *
 * Sections ship in their own PRs:
 *   PR-1 (this commit) — scaffold + greeting + placeholders + tools rail
 *   PR-2 → PR-8        — each card replaces its placeholder in turn
 *
 * Auth + logout + name resolution stay the same as the previous tiles
 * page, just relocated into the new shell.
 */
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { signOut, getDisplayName } from "@/sunnyfi/lib/auth";
import { supabase } from "@/integrations/supabase/client";
import "./dashboard.css";

// ─────────────────────── Tools rail (footer) ─────────────────────
// Slim navigation strip — pure access, no longer the centerpiece. Cards
// above are what the user actually consumes.

type ToolKey = "positions" | "math" | "strategy";
interface Tool {
  key: ToolKey;
  name: string;
  href?: string;
  internal?: string;
  hotkey: string;
}

const TOOLS: Tool[] = [
  { key: "positions", name: "Positions", hotkey: "1", href: "https://positions.sunnyfi.co" },
  { key: "strategy",  name: "Strategy",  hotkey: "2", internal: "/new-strategy" },
  { key: "math",      name: "Math",      hotkey: "3", internal: "/math" },
];

// ─────────────────────── Time hooks ──────────────────────────────

function useNow() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    // 30-second tick — enough to keep the countdown accurate, cheap on
    // re-renders (the rest of the page is mostly static cards).
    const id = setInterval(() => setNow(new Date()), 30000);
    return () => clearInterval(id);
  }, []);
  return now;
}

/** Time-of-day greeting word. We bias 'Morning' wide because the
 *  dashboard is most useful pre-market; the user explicitly asked for
 *  the "morning brief" feeling. */
function greetingWord(hour: number): string {
  if (hour < 5)  return "Late night,";
  if (hour < 12) return "Morning,";
  if (hour < 17) return "Afternoon,";
  if (hour < 21) return "Evening,";
  return "Late night,";
}

function fmtDateBig(d: Date): string {
  const days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
  const months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
  return `${days[d.getDay()]} ${d.getDate()} ${months[d.getMonth()]}`;
}

function fmtTimeET(d: Date): string {
  // Render in user's local time but label as ET; close enough for a
  // status strip and matches how the user reads market hours.
  return d.toLocaleTimeString("en-US", {
    hour: "numeric", minute: "2-digit",
  }).replace(/\s?[AP]M/i, (m) => m.trim());
}

/** Trading-day market clock — US equity regular hours. Returns
 *  "MARKETS OPEN IN Xh Ym", "MARKETS OPEN", "MARKETS CLOSED" depending
 *  on day-of-week and time. Weekends => "MARKETS CLOSED". */
function marketStatus(now: Date): string {
  const dow = now.getDay();
  if (dow === 0 || dow === 6) return "MARKETS CLOSED — WEEKEND";

  // Convert to ET (UTC-4 EDT / UTC-5 EST). Approximation: assume EDT
  // during March-Nov, EST otherwise. Good enough for a status string.
  const month = now.getMonth();
  const etOffset = month >= 2 && month <= 10 ? -4 : -5;
  const utc = now.getTime() + now.getTimezoneOffset() * 60000;
  const et = new Date(utc + etOffset * 3600000);
  const etHour = et.getHours();
  const etMin = et.getMinutes();
  const etMins = etHour * 60 + etMin;
  const open = 9 * 60 + 30;
  const close = 16 * 60;

  if (etMins >= open && etMins < close) {
    const mins = close - etMins;
    return `MARKETS OPEN · CLOSES IN ${Math.floor(mins / 60)}H ${mins % 60}M`;
  }
  if (etMins < open) {
    const mins = open - etMins;
    return `MARKETS OPEN IN ${Math.floor(mins / 60)}H ${mins % 60}M`;
  }
  return "MARKETS CLOSED";
}

// ─────────────────────── Status ticker (bottom of greeting) ──────
// Pulls SPY / QQQ / IWM intraday change from the bnf_universe_latest
// view. VIX / DXY / 10Y are placeholders until PR-5 wires the cache
// backfill for them.

interface TickerRow {
  ticker: string;
  today_intraday_pct: number | null;
  latest_close: number | null;
}

function useTickerStrip(): TickerRow[] {
  const { data = [] } = useQuery({
    queryKey: ["dash_ticker_strip"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bnf_universe_latest" as never)
        .select("ticker, today_intraday_pct, latest_close")
        .in("ticker", ["SPY", "QQQ", "IWM"])
        .returns<TickerRow[]>();
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 60_000,
  });
  return data;
}

function fmtPct(v: number | null): string {
  if (v == null) return "—";
  return `${v >= 0 ? "+" : ""}${v.toFixed(2)}%`;
}

// ─────────────────────── Page ────────────────────────────────────

interface ToastState { msg: string }

export default function Dashboard() {
  const navigate = useNavigate();
  const now = useNow();
  const [toast, setToast] = useState<ToastState | null>(null);
  const [fading, setFading] = useState(false);
  const [name, setName] = useState<string>("there");
  const tickers = useTickerStrip();

  useEffect(() => {
    let cancelled = false;
    supabase.auth.getUser().then(async ({ data }) => {
      if (cancelled || !data.user) return;
      const n = await getDisplayName(data.user);
      if (!cancelled) setName(n);
    });
    return () => { cancelled = true; };
  }, []);

  const onOpenTool = (t: Tool) => {
    setToast({ msg: `Opening ${t.name}…` });
    window.clearTimeout((window as unknown as { __sunnyfiToastT?: number }).__sunnyfiToastT);
    (window as unknown as { __sunnyfiToastT?: number }).__sunnyfiToastT = window.setTimeout(() => setToast(null), 1500);
    if (t.internal) { navigate(t.internal); return; }
    if (t.href)     { window.location.href = t.href; return; }
  };

  const onLogout = () => {
    setFading(true);
    setTimeout(async () => {
      await signOut();
      navigate("/", { replace: true });
    }, 400);
  };

  // Hotkeys: Cmd+1..3 open tools.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey)) return;
      const idx = parseInt(e.key, 10);
      if (isNaN(idx) || idx < 1 || idx > TOOLS.length) return;
      e.preventDefault();
      onOpenTool(TOOLS[idx - 1]);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className={"dash-v2" + (fading ? " fading" : "")}>
      {/* ───────── GREETING STRIP ───────── */}
      <header className="dash2-greet">
        <div className="dash2-greet-row">
          <h1 className="dash2-hero">
            {greetingWord(now.getHours())}<br />
            <span className="dash2-hero-name">{name}.</span>
          </h1>
          <div className="dash2-greet-meta">
            <div className="dash2-greet-date">{fmtDateBig(now)}</div>
            <div className="dash2-greet-time">{fmtTimeET(now)} ET</div>
            <div className="dash2-greet-mkt">{marketStatus(now)}</div>
            <button className="dash2-logout" onClick={onLogout}>log out ↗</button>
          </div>
        </div>

        <div className="dash2-ticker">
          {["SPY", "QQQ", "IWM"].map((sym) => {
            const row = tickers.find((t) => t.ticker === sym);
            const v = row?.today_intraday_pct ?? null;
            const tone = v == null ? "" : v >= 0 ? "pos" : "neg";
            return (
              <span key={sym} className="dash2-ticker-item">
                <span className="sym">{sym}</span>
                <span className={`pct ${tone}`}>{fmtPct(v)}</span>
              </span>
            );
          })}
          {/* Placeholders for the macro indicators PR-5 will wire up. */}
          {[
            ["10Y",  "—"],
            ["VIX",  "—"],
            ["DXY",  "—"],
          ].map(([sym, val]) => (
            <span key={sym} className="dash2-ticker-item muted">
              <span className="sym">{sym}</span>
              <span className="pct">{val}</span>
            </span>
          ))}
        </div>
      </header>

      {/* ───────── 12-COLUMN GRID OF CARDS ─────────
          Each <Placeholder> is replaced in a subsequent PR. The grid
          spans are fixed here so the layout never shifts as cards land. */}
      <main className="dash2-grid">
        <Placeholder span={4} title="TODAY"             label="PR-2" />
        <Placeholder span={8} title="PORTFOLIO PULSE"   label="PR-3" />
        <Placeholder span={8} title="THIS WEEK"         label="PR-4" />
        <Placeholder span={4} title="MACRO"             label="PR-5" />
        <Placeholder span={6} title="BNF STRATEGY"      label="PR-6" />
        <Placeholder span={6} title="RISK CHECK"        label="PR-7" />
        <Placeholder span={12} title="NEWS"             label="PR-8" />
      </main>

      {/* ───────── TOOLS RAIL (footer) ───────── */}
      <footer className="dash2-toolsrail">
        {TOOLS.map((t) => (
          <button key={t.key} className="dash2-tool" onClick={() => onOpenTool(t)}>
            <span>{t.name}</span>
            <span className="dash2-tool-hk">⌘{t.hotkey}</span>
          </button>
        ))}
      </footer>

      {toast && <div className="dash2-toast">{toast.msg}</div>}
    </div>
  );
}

/** Placeholder card — shows where a future PR will land. Same look as
 *  the real cards (lifted dark surface, section title in mono) so the
 *  page already feels structured before the data goes in. */
function Placeholder({ span, title, label }: {
  span: 4 | 6 | 8 | 12;
  title: string;
  label: string;
}) {
  return (
    <section className={`dash2-card dash2-span-${span}`}>
      <div className="dash2-card-head">
        <span className="dash2-card-title">{title}</span>
        <span className="dash2-card-coming">{label}</span>
      </div>
      <div className="dash2-card-body dash2-card-empty">
        coming next
      </div>
    </section>
  );
}
