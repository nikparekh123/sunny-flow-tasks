/**
 * Cockpit layout (LayoutB) — ported from the Claude design handoff.
 *
 * Visual structure:
 *
 *   ┌─────────────────────────────────────────────────────────────┐
 *   │  BrandBar                                                    │
 *   │─────────────────────────────────────────────────────────────│
 *   │  Greeting (left)              MarketsClock + Date (right)    │
 *   │─────────────────────────────────────────────────────────────│
 *   │  TickerStrip (compact)                                       │
 *   │─────────────────────────────────────────────────────────────│
 *   │  ← DECIDE                              OBSERVE →             │
 *   │  ┌─────────────────────┐   ┌─────────────────────────────┐  │
 *   │  │ AttentionBlock      │   │ PortfolioBlockCompact       │  │
 *   │  │ CalendarBlock       │   │ IncomeMix (compact)         │  │
 *   │  │ BNFBlock            │   │ MacroBlock (compact)        │  │
 *   │  │                     │   │ RiskBlock (compact)         │  │
 *   │  └─────────────────────┘   └─────────────────────────────┘  │
 *   │─────────────────────────────────────────────────────────────│
 *   │  NewsBand                                                    │
 *   │─────────────────────────────────────────────────────────────│
 *   │  ToolsRail                                                   │
 *   └─────────────────────────────────────────────────────────────┘
 *
 * Default settings (locked per design approval):
 *   greeting = formal · heroAccent = neon · heroSize = 120
 *   todayHighlight = neon · areaFill = true · showNews = true
 */
import {
  BrandBar, Greeting, MarketsClock, TickerStrip,
  AttentionBlock, CalendarBlock, BNFBlock,
  PortfolioBlockCompact, IncomeMix, MacroBlock, RiskBlock,
  NewsBand, ToolsRail,
} from "./blocks";
import { useNow, marketClock, fmtBrandDate } from "./time";

export interface CockpitProps {
  /** Display name for the greeting hero ("Good morning, X."). */
  name?: string;
  heroSize?: number;
  bone?: boolean;
  areaFill?: boolean;
  todayHighlight?: "amber" | "neon" | "off";
  showNews?: boolean;
  formalGreeting?: boolean;
  onPositions?: () => void;
  onStrategy?: () => void;
  onMath?: () => void;
}

export function CockpitLayout({
  name = "Niket",
  heroSize = 120,
  bone = false,
  areaFill = true,
  todayHighlight = "neon",
  showNews = true,
  formalGreeting = true,
  onPositions, onStrategy, onMath,
}: CockpitProps) {
  const now = useNow(60_000);
  const dateLabel = fmtBrandDate(now);
  const clock = marketClock(now);

  return (
    <div className="dash">
      <div className="dash-inner">

        <BrandBar dateLabel={dateLabel} />

        {/* Hero band — greeting + markets clock in one tight row */}
        <div className="row first">
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
            <Greeting
              size={Math.min(96, heroSize * 0.6)}
              bone={bone}
              formal={formalGreeting}
              name={name}
              hour={now.getHours()}
            />
            <div style={{ textAlign: "right", paddingBottom: 10 }}>
              <MarketsClock size={22} phrase={clock.phrase} live={clock.live} />
              <div className="label" style={{ marginTop: 8 }}>{dateLabel}</div>
            </div>
          </div>
        </div>

        <div className="row" style={{ marginTop: 28 }}>
          <TickerStrip compact />
        </div>

        {/* Two-column body */}
        <div className="row" style={{ marginTop: 48 }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 64 }}>
            <div className="col-label">← DECIDE</div>
            <div className="col-label" style={{ textAlign: "right" }}>OBSERVE →</div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 64 }}>

            {/* LEFT — DECIDE */}
            <div>
              <AttentionBlock n="01" />
              <div style={{ marginTop: 56 }}>
                <CalendarBlock n="02" highlight={todayHighlight} compact />
              </div>
              <div style={{ marginTop: 56 }}>
                <BNFBlock n="03" compact onOpenScanner={onStrategy} />
              </div>
            </div>

            {/* RIGHT — OBSERVE */}
            <div>
              <PortfolioBlockCompact heroSize={heroSize * 0.7} bone={bone} area={areaFill} n="04" />
              <div style={{ marginTop: 40 }}>
                <IncomeMix compact />
              </div>
              <div style={{ marginTop: 48 }}>
                <MacroBlock n="05" compact />
              </div>
              <div style={{ marginTop: 48 }}>
                <RiskBlock n="06" compact />
              </div>
            </div>

          </div>
        </div>

        {showNews && (
          <div className="row" style={{ marginTop: 64 }}>
            <NewsBand n="07" />
          </div>
        )}

        <div className="row" style={{ marginTop: 56 }}>
          <ToolsRail
            onPositions={onPositions}
            onStrategy={onStrategy}
            onMath={onMath}
          />
        </div>

      </div>
    </div>
  );
}
