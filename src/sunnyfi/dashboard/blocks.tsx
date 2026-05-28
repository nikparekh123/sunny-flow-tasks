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
import { Spark, AnimatedBar, HairRow, Section } from "./atoms";
import { MoneyCount, PctCount, useEntered } from "./animation";

// ─────────────────── Brand bar ───────────────────────────────────

export function BrandBar() {
  return (
    <div className="brandbar">
      <div className="mark">
        <span className="logo">◆ SUNNYFI</span>
        <span className="slash">/</span>
        <span className="route">Morning brief<span className="cursor" /></span>
      </div>
      <div className="actions">
        <span className="label">FRI · JUN 27 · 06:42 AM PT</span>
        <span className="pill muted">⌘ K · Search</span>
        <span className="pill muted">Account</span>
      </div>
    </div>
  );
}

// ─────────────────── Greeting ────────────────────────────────────

export function Greeting({
  size = 128, bone = false, formal = false,
}: {
  size?: number; bone?: boolean; formal?: boolean;
}) {
  if (formal) {
    // Formal greeting has its own floor so it stays legible when the
    // hero is dialled small (e.g. cockpit layout).
    const formalSize = Math.max(56, size * 0.72);
    return (
      <div
        className={"greeting display " + (bone ? "bone" : "")}
        style={{ fontSize: formalSize, lineHeight: 0.95, fontWeight: 300, letterSpacing: "-.025em" }}
      >
        Good morning<span className="accent">,</span> Niket<span className="accent">.</span>
      </div>
    );
  }
  return (
    <div className={"greeting display " + (bone ? "bone" : "")} style={{ fontSize: size }}>
      MORNING<span className="accent">,</span><br />NIKET<span className="accent">.</span>
    </div>
  );
}

// ─────────────────── Markets clock ───────────────────────────────

export function MarketsClock({ size = 28 }: { size?: number }) {
  return (
    <div className="markets-clock" style={{ fontSize: size }}>
      <span className="live-dot" style={{ marginRight: 10 }} />
      Markets open in <span className="time">2h 48m</span>
    </div>
  );
}

// ─────────────────── Ticker strip ────────────────────────────────

export function TickerStrip({ compact = false }: { compact?: boolean }) {
  const data: Array<[string, string, string, "pos" | "neg", boolean]> = [
    ["SPY", "655.06", "+0.44%", "pos", true],
    ["QQQ", "495.20", "+0.61%", "pos", false],
    ["IWM", "228.14", "−0.18%", "neg", false],
    ["10Y", "4.21",   "−0.03",  "neg", false],
    ["VIX", "13.20",  "−2.10%", "pos", false],
    ["DXY", "103.42", "+0.12%", "pos", false],
  ];
  return (
    <div className={"ticker" + (compact ? " compact" : "")}>
      {data.map(([t, p, c, k, live]) => (
        <div key={t} className={"tick" + (compact ? " compact" : "")}>
          <div className="head">
            {live && <span className="live-dot" />}
            <span className="label">{t}</span>
          </div>
          <div className="price">{p}</div>
          <div className={"change " + k}>{c}</div>
        </div>
      ))}
    </div>
  );
}

// ─────────────────── § 01 Attention ──────────────────────────────

export function AttentionBlock({ n = "01" }: { n?: string }) {
  return (
    <div>
      <Section n={n} right="4 items">On your radar today</Section>
      <HairRow label="EXPIRES TODAY" right={<span className="pos">$0 risk</span>}>
        <span className="num-mono" style={{ fontWeight: 500 }}>NVDA 880c</span>
        <span className="fg4"> · </span>
        3 contracts
        <span className="fg4"> · </span>
        <span className="chip pos" style={{ marginLeft: 4 }}>OTM</span>
      </HairRow>
      <HairRow
        label="SETTLING"
        right={
          <span className="num-sans pos" style={{ fontSize: 18, fontWeight: 600 }}>
            <MoneyCount value={4280} sign="+" delay={400} />
          </span>
        }
      >
        Premium collected this week · 7 contracts cleared
      </HairRow>
      <HairRow label="EARNINGS · TMW" right={<span className="warn">9% IV crush</span>}>
        <span className="num-mono" style={{ fontWeight: 500 }}>CRM</span> after close · holding 220 sh
      </HairRow>
      <HairRow label="MACRO · TODAY" right={<span className="chip warn">VOL EVENT</span>} last>
        FOMC minutes <span className="num-mono">14:00 ET</span> · positions sized down ahead
      </HairRow>
    </div>
  );
}

// ─────────────────── § 02 Portfolio (full + compact) ─────────────

export function PortfolioBlock({
  heroSize = 184, bone = false, area = true, n = "02",
}: {
  heroSize?: number; bone?: boolean; area?: boolean; n?: string;
}) {
  return (
    <div>
      <Section n={n} right="updated 06:42">Portfolio</Section>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 36 }}>
        <div className={"portfolio-num " + (bone ? "bone" : "neon")} style={{ fontSize: heroSize }}>
          <MoneyCount value={642830} duration={1400} />
        </div>
        <div style={{ paddingBottom: heroSize * 0.13 }}>
          <div className="label">This week</div>
          <div className="hero num-mono pos" style={{ fontSize: 48, fontWeight: 700, marginTop: 4 }}>
            <MoneyCount value={4820} sign="+" delay={200} duration={1100} />
          </div>
          <div className="num-mono pos" style={{ fontSize: 14, marginTop: 4 }}>
            <PctCount value={0.76} sign="+" delay={300} /> · 5 sessions
          </div>
        </div>
      </div>
      <div style={{ marginTop: 28 }}>
        <Spark w={820} h={56} kind="neon" area={area} delay={300} />
        <div style={{ display: "flex", justifyContent: "space-between", maxWidth: 820, marginTop: 8 }}>
          <span className="label">12 weeks ago · $607,180</span>
          <span className="label">today · $642,830</span>
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
  return (
    <div>
      <Section n={n}>Portfolio</Section>
      <div className={"portfolio-num " + (bone ? "bone" : "neon")} style={{ fontSize: heroSize }}>
        <MoneyCount value={642830} duration={1400} />
      </div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 18, marginTop: 14 }}>
        <span className="hero num-mono pos" style={{ fontSize: 32, fontWeight: 700 }}>
          <MoneyCount value={4820} sign="+" delay={200} />
        </span>
        <span className="num-mono pos" style={{ fontSize: 13 }}>
          <PctCount value={0.76} sign="+" delay={300} /> · 1 week
        </span>
      </div>
      <div style={{ marginTop: 22 }}>
        <Spark w={540} h={42} kind="neon" area={area} delay={300} />
        <div style={{ display: "flex", justifyContent: "space-between", maxWidth: 540, marginTop: 6 }}>
          <span className="label">12w · $607k</span>
          <span className="label">today · $642k</span>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── Winners / Losers ────────────────────────────

export function WinnersLosers() {
  const winners: Array<[string, number, number]> = [
    ["NVDA", 2140, 0.95],
    ["META", 880, 0.40],
    ["AAPL", 620, 0.28],
  ];
  const losers: Array<[string, number, number]> = [
    ["TSLA", 640, 0.50],
    ["CRM",  180, 0.15],
    ["SMCI", 120, 0.10],
  ];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 64 }}>
      <div>
        <Section>Winners · this week</Section>
        {winners.map(([t, v, w], i) => (
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
        {losers.map(([t, v, w], i) => (
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

export function IncomeMix({ compact = false }: { compact?: boolean }) {
  const entered = useEntered(300);
  const callsPct = entered ? 73 : 0;
  return (
    <div>
      <Section>Income mix · this week</Section>
      <div style={{ display: "flex", alignItems: "baseline", gap: compact ? 16 : 32 }}>
        <div>
          <div className="label">Calls sold</div>
          <div className="hero num-mono neon" style={{ fontSize: compact ? 28 : 44, fontWeight: 700, marginTop: 4 }}>
            <MoneyCount value={3120} delay={150} duration={1200} />
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
            <MoneyCount value={1160} delay={250} duration={1200} />
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── § 03 Calendar ───────────────────────────────

type EventKind = "mine" | "plain" | "warn";
type CalDay = [string, string, Array<[string, EventKind]>, boolean?];

export function CalendarBlock({
  n = "03", highlight = "neon", compact = false,
}: {
  n?: string;
  highlight?: "amber" | "neon" | "off";
  compact?: boolean;
}) {
  const days: CalDay[] = [
    ["MON", "23", [["FOMC", "warn"]]],
    ["TUE", "24", [["MSFT exp", "mine"], ["AAPL exp", "mine"]]],
    ["WED", "25", [["CRM earn", "plain"]]],
    ["THU", "26", [["NVDA earn", "plain"], ["PCE", "warn"]]],
    ["FRI", "27", [["NVDA 880c exp", "mine"], ["settle $4.2k", "mine"]], true],
  ];
  const highlightClass = highlight === "neon" ? " neon-highlight"
    : highlight === "off" ? " no-highlight"
    : "";
  return (
    <div>
      <Section n={n} right="Week of Jun 23">Week ahead</Section>
      <div className="cal">
        {days.map(([day, d, events, today], i) => (
          <div
            key={i}
            className={"cal-cell" + (today ? " today" + highlightClass : "")}
            style={compact ? { minHeight: 140, padding: 10 } : undefined}
          >
            <div className="day-label" style={compact ? { marginBottom: 8 } : undefined}>
              {day} {d}{today && !compact && " · TODAY"}
            </div>
            {events.map(([txt, kind], j) => (
              kind === "warn" ? (
                <div key={j} style={{ marginBottom: 6 }}>
                  <span className="chip warn" style={compact ? { fontSize: 8 } : undefined}>{txt}</span>
                </div>
              ) : (
                <div
                  key={j}
                  className={"cal-event" + (kind === "mine" ? " mine" : "")}
                  style={compact ? { fontSize: 10 } : undefined}
                >
                  {txt}
                </div>
              )
            ))}
            {today && !compact && <div className="focus-tag">↑ FOCUS</div>}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────── § 04 Macro zoom ─────────────────────────────

export function MacroBlock({ n = "04", compact = false }: { n?: string; compact?: boolean }) {
  const rows: Array<[string, string, string, "pos" | "neg"]> = [
    ["SPY", "low fear · opt premium cheap", "+0.44%", "pos"],
    ["QQQ", "tech bid · NVDA leads",        "+0.61%", "pos"],
    ["IWM", "small caps lagging",           "−0.18%", "neg"],
    ["10Y", "yields easing into FOMC",      "−0.03",  "neg"],
    ["VIX", "calm, complacent",             "−2.10%", "pos"],
    ["DXY", "dollar firm into Asia close",  "+0.12%", "pos"],
    ["EWJ", "BoJ steady, JP up 0.3%",       "+0.30%", "pos"],
    ["FXI", "China stim hopes lifting names", "+1.10%", "pos"],
  ];
  return (
    <div>
      <Section n={n}>Macro zoom</Section>
      {rows.map(([t, note, c, k], i) => (
        <div
          key={t}
          className="macro-row"
          style={compact ? { gridTemplateColumns: "56px 1fr 78px 64px", gap: 14, padding: "10px 0" } : undefined}
        >
          <span className="ticker-name" style={compact ? { fontSize: 14 } : undefined}>{t}</span>
          <span className="note" style={compact ? { fontSize: 12 } : undefined}>{note}</span>
          <Spark w={compact ? 78 : 90} h={compact ? 18 : 22} kind={k === "pos" ? "muted" : "muted-down"} dense delay={500 + i * 60} />
          <span className={"change " + k} style={compact ? { fontSize: 12 } : undefined}>{c}</span>
        </div>
      ))}
    </div>
  );
}

// ─────────────────── § 05 BNF Strategy ───────────────────────────

export function BNFBlock({ n = "05", compact = false }: { n?: string; compact?: boolean }) {
  type Pick = [string, string, string, "neon" | "warn"];
  const picks: Pick[] = [
    ["AVGO", compact ? "−2.1σ · Tech"   : "Tech · −2.1σ",      "watch", "warn"],
    ["XOM",  compact ? "−1.9σ · Energy" : "Energy · −1.9σ",    "ready", "neon"],
    ["JPM",  compact ? "−1.8σ · Fin"    : "Financial · −1.8σ", "watch", "warn"],
    ["LMT",  compact ? "−1.7σ · Def"    : "Defense · −1.7σ",   "ready", "neon"],
  ];
  return (
    <div>
      <Section n={n} right={compact ? "4 picks" : "4 picks · mean-reversion"}>BNF · today</Section>
      <div style={compact ? { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 } : undefined}>
        {picks.map(([t, meta, st, col]) => (
          <div key={t} className="bnf-tile" style={compact ? undefined : { marginBottom: 10 }}>
            <div className="head">
              <span className="ticker-name hero num-mono" style={{ fontSize: compact ? 22 : 26, fontWeight: 700 }}>{t}</span>
              <span className={"chip " + col} style={compact ? { fontSize: 8 } : undefined}>{st}</span>
            </div>
            <div className="label" style={{ marginTop: 6 }}>{meta}</div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 14 }}>
        <span className="pill">→ Open scanner</span>
      </div>
    </div>
  );
}

// ─────────────────── § 06 Risk check ─────────────────────────────

export function RiskBlock({ n = "06", compact = false }: { n?: string; compact?: boolean }) {
  const numNeg = (v: number, delay: number) => (
    <span className="num-mono neg" style={{ fontSize: compact ? 18 : 22, fontWeight: 600 }}>
      <MoneyCount value={v} sign="-" delay={delay} />
    </span>
  );
  return (
    <div>
      <Section n={n} right={<>Last run <span className="num-mono fg2">Mon 09:14</span> · due Mon</>}>
        Risk check
      </Section>
      <HairRow label="SPY −5%"   right={numNeg(94200, 300)}>shock to portfolio · constant beta</HairRow>
      <HairRow label="NVDA −10%" right={numNeg(28400, 380)}>single-name shock</HairRow>
      <HairRow label="VIX +50%"  right={numNeg(12800, 460)} last>vol regime shift · vega exposure</HairRow>
    </div>
  );
}

// ─────────────────── § 07 News band ──────────────────────────────

export function NewsBand({ n = "07" }: { n?: string }) {
  const items: Array<[string, string, string]> = [
    ["NVDA", "06:14", "Blackwell ramps ahead of schedule — Bloomberg"],
    ["CRM",  "05:48", "Q2 revenue beat, guidance light — WSJ"],
    ["META", "05:22", "VR division cut 12% — Reuters"],
    ["AAPL", "04:50", "iPhone 17 sourcing leaks — Nikkei"],
    ["TSLA", "04:12", "China deliveries flat MoM — CnEVPost"],
  ];
  return (
    <div>
      <Section n={n} right="06:14 AM · 5 held tickers">Tape · headlines</Section>
      <div className="news-band">
        {items.map(([t, time, h]) => (
          <div key={t} className="news-card">
            <div className="head">
              <span className="ticker-tag">{t}</span>
              <span className="time">{time}</span>
            </div>
            <div className="headline">{h}</div>
          </div>
        ))}
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
