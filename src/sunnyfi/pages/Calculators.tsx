/**
 * Calculators — canvas shell.
 *
 * Styled to match Positions (np-app root, positions.css tokens, same top bar,
 * same card / section / button patterns). Layout: full-width top bar → stage
 * with an optional left drawer panel + centered 720px canvas card.
 */
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import "../../positions/positions.css";

type CalcKey =
  | "pct-diff" | "expected-income" | "put-cost" | "income-vs-cost"
  | "scenario" | "stress";

interface CalcItem {
  key: CalcKey;
  name: string;
  desc: string;
}
interface CalcGroup {
  name: string;
  comingSoon?: boolean;
  items: CalcItem[];
}

const GROUPS: CalcGroup[] = [
  {
    name: "Pre-Trade Planning",
    items: [
      { key: "pct-diff",        name: "Percentage Difference", desc: "Strike vs spot, distance to the line" },
      { key: "expected-income", name: "Expected Income",       desc: "Premium yield against capital at risk" },
      { key: "put-cost",        name: "Put Cost",              desc: "Hedge spend vs portfolio exposure" },
      { key: "income-vs-cost",  name: "Income vs Cost",        desc: "Net carry after protection" },
    ],
  },
  {
    name: "Scenario & Risk",
    items: [
      { key: "scenario", name: "Scenario Calculator", desc: "Project P&L across price paths" },
      { key: "stress",   name: "Stress Calculator",   desc: "Tail-risk drawdown by shock factor" },
    ],
  },
  { name: "Macro",             comingSoon: true, items: [] },
  { name: "Post-Trade Review", comingSoon: true, items: [] },
];

const CATEGORY_BY_KEY: Record<CalcKey, string> = {
  "pct-diff":        "Pre-Trade Planning",
  "expected-income": "Pre-Trade Planning",
  "put-cost":        "Pre-Trade Planning",
  "income-vs-cost":  "Pre-Trade Planning",
  scenario:          "Scenario & Risk",
  stress:            "Scenario & Risk",
};

const CALC_DESC: Record<CalcKey, string> = {
  "pct-diff":        "Computes the percentage gap between two prices — e.g. current spot vs target strike.",
  "expected-income": "Estimates annualised premium yield relative to the capital at risk on the position.",
  "put-cost":        "Sizes the cost of a protective put as a percentage of portfolio exposure.",
  "income-vs-cost":  "Nets covered-call income against put-protection spend to show true carry.",
  scenario:          "Projects P&L across a range of expiry price paths for a given set of open trades.",
  stress:            "Applies a volatility or price-shock factor to show tail-risk drawdown.",
};

// ── tiny SVG icons ────────────────────────────────────────────────
const I = { fill: "none", stroke: "currentColor", strokeWidth: 1.5, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
const Ic = ({ d, size = 16 }: { d: string; size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" {...I} aria-hidden>
    <path d={d} />
  </svg>
);
const IcHistory = () => (
  <svg width={16} height={16} viewBox="0 0 24 24" {...I} aria-hidden>
    <path d="M3 12a9 9 0 1 0 3-6.7L3 8" />
    <path d="M3 3v5h5" />
    <path d="M12 7v5l3 2" />
  </svg>
);
const IcInfo = () => (
  <svg width={13} height={13} viewBox="0 0 24 24" {...I} aria-hidden>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 11v5M12 7.5v.01" />
  </svg>
);
const IcX = () => <Ic d="M6 6l12 12M18 6L6 18" />;
const IcMenu = () => <Ic d="M4 7h16M4 12h16M4 17h16" />;

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

// ── component ─────────────────────────────────────────────────────
export default function Calculators() {
  const navigate = useNavigate();
  const [drawerOpen,  setDrawerOpen]  = useState(true);
  const [selected,    setSelected]    = useState<CalcKey | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [saveOpen,    setSaveOpen]    = useState(false);

  const selectedItem     = GROUPS.flatMap(g => g.items).find(i => i.key === selected) ?? null;
  const selectedCategory = selected ? CATEGORY_BY_KEY[selected] : null;
  const selectedDesc     = selected ? CALC_DESC[selected] : null;

  const onPick = (key: CalcKey) => {
    setSelected(key);
    setDrawerOpen(false);
    setHistoryOpen(false);
  };

  return (
    <div className="np-app">
      {/* ── Top bar ── */}
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">Calculators</span>
        </div>
        <div className="np-actions">
          <button
            className="np-btn ghost"
            onClick={() => setDrawerOpen(v => !v)}
            title="Toggle calculator list"
          >
            <IcMenu />
            {drawerOpen ? "Hide list" : "Show list"}
          </button>
        </div>
      </header>

      {/* ── Content ── */}
      <div
        style={{
          maxWidth: 1480,
          margin: "0 auto",
          padding: "36px 32px 80px",
          display: "flex",
          gap: 28,
          alignItems: "flex-start",
        }}
      >
        {/* ── Drawer panel ── */}
        {drawerOpen && (
          <aside
            style={{
              width: 260,
              minWidth: 260,
              background: "var(--navi-card)",
              borderRadius: 12,
              padding: "6px 0 16px",
              flexShrink: 0,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "14px 20px 10px",
                borderBottom: "1px solid rgba(30,90,80,.25)",
                marginBottom: 4,
              }}
            >
              <span
                style={{
                  fontSize: 8,
                  fontWeight: 600,
                  letterSpacing: 2,
                  textTransform: "uppercase",
                  color: "var(--navi-fg3)",
                }}
              >
                Calculators
              </span>
              <button
                className="np-btn ghost"
                style={{ padding: "4px 6px" }}
                onClick={() => setDrawerOpen(false)}
                aria-label="Close"
              >
                <IcX />
              </button>
            </div>

            {GROUPS.map(group => (
              <div key={group.name}>
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "14px 20px 6px",
                  }}
                >
                  <span
                    style={{
                      fontSize: 8,
                      fontWeight: 600,
                      letterSpacing: 2,
                      textTransform: "uppercase",
                      color: "var(--navi-fg4)",
                    }}
                  >
                    {group.name}
                  </span>
                  {group.comingSoon && (
                    <span
                      style={{
                        fontSize: 8,
                        letterSpacing: 1.5,
                        textTransform: "uppercase",
                        color: "var(--navi-fg5)",
                        fontWeight: 500,
                      }}
                    >
                      Soon
                    </span>
                  )}
                </div>

                {group.items.map(item => {
                  const active = selected === item.key;
                  return (
                    <button
                      key={item.key}
                      onClick={() => onPick(item.key)}
                      style={{
                        display: "block",
                        width: "100%",
                        background: active ? "var(--navi-tint-neon)" : "transparent",
                        border: "none",
                        borderLeft: `2px solid ${active ? "var(--navi-neon)" : "transparent"}`,
                        padding: "8px 18px 8px 18px",
                        textAlign: "left",
                        cursor: "pointer",
                        fontFamily: "inherit",
                        transition: "background .1s",
                      }}
                    >
                      <div
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          color: active ? "var(--navi-neon)" : "var(--navi-fg1)",
                          marginBottom: 2,
                        }}
                      >
                        {item.name}
                      </div>
                      <div
                        style={{
                          fontSize: 11,
                          color: "var(--navi-fg4)",
                          lineHeight: 1.4,
                        }}
                      >
                        {item.desc}
                      </div>
                    </button>
                  );
                })}
              </div>
            ))}
          </aside>
        )}

        {/* ── Canvas ── */}
        <div style={{ flex: 1, minWidth: 0, display: "flex", justifyContent: "center" }}>
          <div
            style={{
              width: 720,
              minHeight: 600,
              background: "var(--navi-card)",
              borderRadius: 12,
              display: "flex",
              flexDirection: "column",
              position: "relative",
              overflow: "hidden",
            }}
          >
            {!selectedItem ? (
              // ── Empty state ──
              <div
                style={{
                  flex: 1,
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: 14,
                  padding: 40,
                }}
              >
                <span
                  style={{
                    fontSize: 13,
                    color: "var(--navi-fg4)",
                    fontFamily: "var(--navi-font-mono)",
                  }}
                >
                  Select a calculator from the left to begin
                </span>
                {!drawerOpen && (
                  <button
                    className="np-btn neon"
                    onClick={() => setDrawerOpen(true)}
                  >
                    Show calculators
                  </button>
                )}
              </div>
            ) : (
              <>
                {/* ── Canvas header ── */}
                <div
                  style={{
                    display: "flex",
                    alignItems: "flex-start",
                    justifyContent: "space-between",
                    padding: "22px 28px 16px",
                    borderBottom: "1px solid rgba(30,90,80,.25)",
                  }}
                >
                  <div>
                    <div
                      style={{
                        fontSize: 8,
                        fontWeight: 600,
                        letterSpacing: 2,
                        textTransform: "uppercase",
                        color: "var(--navi-fg3)",
                        marginBottom: 8,
                      }}
                    >
                      {selectedCategory}
                    </div>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <span
                        style={{
                          fontSize: 22,
                          fontWeight: 500,
                          letterSpacing: -0.3,
                          color: "var(--navi-fg1)",
                        }}
                      >
                        {selectedItem.name}
                      </span>
                      <button
                        className="np-btn ghost"
                        style={{ padding: "3px 5px" }}
                        title="About this calculator"
                        aria-label="About"
                      >
                        <IcInfo />
                      </button>
                    </div>
                  </div>
                  <button
                    className={`np-btn ${historyOpen ? "neon" : "ghost"}`}
                    onClick={() => setHistoryOpen(v => !v)}
                    title="Saved calculations"
                    style={{ marginTop: 4 }}
                  >
                    <IcHistory />
                    History
                  </button>
                </div>

                {/* ── Description ── */}
                <div
                  style={{
                    padding: "14px 28px 4px",
                    fontSize: 13,
                    color: "var(--navi-fg3)",
                    lineHeight: 1.6,
                  }}
                >
                  {selectedDesc}
                </div>

                {/* ── Inputs placeholder ── */}
                <div style={{ margin: "18px 28px 0" }}>
                  <div
                    style={{
                      fontSize: 8,
                      fontWeight: 600,
                      letterSpacing: 2,
                      textTransform: "uppercase",
                      color: "var(--navi-fg3)",
                      marginBottom: 10,
                      paddingBottom: 10,
                      borderBottom: "1px solid rgba(30,90,80,.25)",
                    }}
                  >
                    Inputs
                  </div>
                  <div
                    style={{
                      border: "1px dashed rgba(50,110,100,.4)",
                      borderRadius: 8,
                      padding: "36px 20px",
                      textAlign: "center",
                      fontFamily: "var(--navi-font-mono)",
                      fontSize: 12,
                      color: "var(--navi-fg4)",
                    }}
                  >
                    Inputs render here
                  </div>
                </div>

                {/* ── Results placeholder ── */}
                <div style={{ margin: "18px 28px 0" }}>
                  <div
                    style={{
                      fontSize: 8,
                      fontWeight: 600,
                      letterSpacing: 2,
                      textTransform: "uppercase",
                      color: "var(--navi-fg3)",
                      marginBottom: 10,
                      paddingBottom: 10,
                      borderBottom: "1px solid rgba(30,90,80,.25)",
                    }}
                  >
                    Results
                  </div>
                  <div
                    style={{
                      border: "1px dashed rgba(50,110,100,.4)",
                      borderRadius: 8,
                      padding: "36px 20px",
                      textAlign: "center",
                      fontFamily: "var(--navi-font-mono)",
                      fontSize: 12,
                      color: "var(--navi-fg4)",
                    }}
                  >
                    Results render here
                  </div>
                </div>

                {/* ── Footer ── */}
                <div
                  style={{
                    marginTop: "auto",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "20px 28px 24px",
                    borderTop: "1px solid rgba(30,90,80,.25)",
                  }}
                >
                  <button className="np-btn ghost">Reset</button>
                  <button className="np-btn neon" onClick={() => setSaveOpen(true)}>
                    Save Calculation
                  </button>
                </div>

                {/* ── History side panel ── */}
                {historyOpen && (
                  <div
                    style={{
                      position: "absolute",
                      top: 0,
                      right: 0,
                      width: 300,
                      height: "100%",
                      background: "var(--navi-surface, #0f3333)",
                      borderLeft: "1px solid rgba(30,90,80,.35)",
                      display: "flex",
                      flexDirection: "column",
                    }}
                  >
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        padding: "18px 20px 14px",
                        borderBottom: "1px solid rgba(30,90,80,.25)",
                      }}
                    >
                      <span
                        style={{
                          fontSize: 8,
                          fontWeight: 600,
                          letterSpacing: 2,
                          textTransform: "uppercase",
                          color: "var(--navi-fg3)",
                        }}
                      >
                        Saved Calculations
                      </span>
                      <button
                        className="np-btn ghost"
                        style={{ padding: "4px 6px" }}
                        onClick={() => setHistoryOpen(false)}
                        aria-label="Close history"
                      >
                        <IcX />
                      </button>
                    </div>
                    <div
                      style={{
                        flex: 1,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        padding: 24,
                        fontFamily: "var(--navi-font-mono)",
                        fontSize: 12,
                        color: "var(--navi-fg4)",
                      }}
                    >
                      No saved calculations yet
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      {/* ── Save modal ── */}
      {saveOpen && selectedItem && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(6,26,16,.75)",
            backdropFilter: "blur(2px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 100,
          }}
          onClick={() => setSaveOpen(false)}
        >
          <div
            style={{
              width: 460,
              background: "var(--navi-surface, #0f3333)",
              border: "1px solid rgba(50,110,100,.35)",
              borderRadius: 12,
              padding: 28,
            }}
            onClick={e => e.stopPropagation()}
          >
            <div
              style={{
                fontSize: 8,
                fontWeight: 600,
                letterSpacing: 2,
                textTransform: "uppercase",
                color: "var(--navi-fg3)",
                marginBottom: 16,
              }}
            >
              Save Calculation
            </div>

            {/* Name */}
            <div style={{ marginBottom: 14 }}>
              <label
                style={{
                  display: "block",
                  fontSize: 8,
                  fontWeight: 600,
                  letterSpacing: 2,
                  textTransform: "uppercase",
                  color: "var(--navi-fg4)",
                  marginBottom: 6,
                }}
              >
                Name <span style={{ color: "var(--navi-neon)" }}>*</span>
              </label>
              <input
                autoFocus
                placeholder="e.g. AAPL Jan 220p hedge"
                style={{
                  width: "100%",
                  background: "var(--navi-page, #0a2828)",
                  border: "1px solid rgba(30,90,80,.35)",
                  borderRadius: 6,
                  padding: "9px 12px",
                  color: "var(--navi-fg1)",
                  fontFamily: "var(--navi-font-sans)",
                  fontSize: 13,
                  outline: "none",
                  boxSizing: "border-box",
                }}
              />
            </div>

            {/* Purpose */}
            <div style={{ marginBottom: 6 }}>
              <label
                style={{
                  display: "block",
                  fontSize: 8,
                  fontWeight: 600,
                  letterSpacing: 2,
                  textTransform: "uppercase",
                  color: "var(--navi-fg4)",
                  marginBottom: 6,
                }}
              >
                Purpose <span style={{ color: "var(--navi-fg5)" }}>optional</span>
              </label>
              <textarea
                rows={3}
                placeholder="What this scenario is for"
                style={{
                  width: "100%",
                  background: "var(--navi-page, #0a2828)",
                  border: "1px solid rgba(30,90,80,.35)",
                  borderRadius: 6,
                  padding: "9px 12px",
                  color: "var(--navi-fg1)",
                  fontFamily: "var(--navi-font-sans)",
                  fontSize: 13,
                  outline: "none",
                  resize: "vertical",
                  boxSizing: "border-box",
                }}
              />
            </div>

            {/* Metadata */}
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(3, 1fr)",
                gap: 12,
                padding: "14px 0",
                borderTop: "1px solid rgba(30,90,80,.2)",
                borderBottom: "1px solid rgba(30,90,80,.2)",
                margin: "16px 0 20px",
              }}
            >
              {[
                { label: "Calculator", value: selectedItem.name },
                { label: "Category",   value: selectedCategory! },
                { label: "Timestamp",  value: new Date().toISOString().slice(0, 16).replace("T", " ") },
              ].map(({ label, value }) => (
                <div key={label}>
                  <div
                    style={{
                      fontSize: 8,
                      fontWeight: 600,
                      letterSpacing: 2,
                      textTransform: "uppercase",
                      color: "var(--navi-fg4)",
                      marginBottom: 4,
                    }}
                  >
                    {label}
                  </div>
                  <div
                    style={{
                      fontFamily: "var(--navi-font-mono)",
                      fontSize: 11,
                      color: "var(--navi-fg2)",
                    }}
                  >
                    {value}
                  </div>
                </div>
              ))}
            </div>

            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: 16,
              }}
            >
              <button className="np-btn ghost" onClick={() => setSaveOpen(false)}>Cancel</button>
              <button className="np-btn neon" onClick={() => setSaveOpen(false)}>Save</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
